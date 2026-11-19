// Contract with a real Jellyfin (plan 4, task 4): our Jellyfin client against the server itself,
// not against recordings. Skipped unless JELLYFIN_URL is set (CI job `jellyfin`, see
// tool/jellyfin-ci.sh, which makes the library: album "CI Tones" by "LAFLEUR CI", two songs):
//
//   JELLYFIN_URL=http://localhost:8096 JELLYFIN_USER=… JELLYFIN_PASSWORD=… \
//     flutter test test/sources/jellyfin_contract_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lafleurmusic/sources/jellyfin.dart';
import 'package:lafleurmusic/sources/source.dart';

final _env = Platform.environment;
final _url = _env['JELLYFIN_URL'] ?? '';
final String? _skip = _url.isEmpty
    ? 'JELLYFIN_URL not set (runs in the CI job `jellyfin`)'
    : null;

void main() {
  final client = http.Client();
  tearDownAll(client.close);

  JellyfinSource source({String? password}) => JellyfinSource(
    accountId: 'jellyfin',
    base: Uri.parse(_url),
    user: _env['JELLYFIN_USER'] ?? '',
    password: password ?? _env['JELLYFIN_PASSWORD'] ?? '',
    client: http.Client(),
    deviceName: 'CI',
  );

  group('Jellyfin contract', skip: _skip, () {
    test('Tester: ok', () async {
      final s = source();
      expect(await s.test(), TestResult.ok);
      s.close();
    });

    test('Tester: a wrong password is reported as such', () async {
      final s = source(password: 'not-the-password');
      expect(await s.test(), TestResult.wrongPassword);
      s.close();
    });

    test('albums, songs, stream, download, listen, playlists', () async {
      final s = source();
      addTearDown(s.close);

      final albums = (await s.albums().toList()).expand((p) => p).toList();
      final album = albums.firstWhere(
        (a) => a.name == 'CI Tones',
        orElse: () => fail('no "CI Tones" in $albums'),
      );
      expect(album.artist, 'LAFLEUR CI'); // AlbumArtist: what the merge uses

      final songs = await s.albumSongs(album.id);
      expect(songs.map((x) => (x.title, x.track)), [
        ('Tone One', 1),
        ('Tone Two', 2),
      ]);
      final song = songs.first;
      expect(song.album, 'CI Tones');
      expect(song.albumArtist, 'LAFLEUR CI');
      expect(song.durationMs, closeTo(10000, 1000)); // the 10 s tone
      expect(song.suffix, 'flac');

      // stream: what mpv sends (comma-free header), then the address alone (api_key: what's
      // left after a redirect that drops the headers)
      await s.prepare();
      for (final headers in [s.streamHeaders, const <String, String>{}]) {
        final audio = await client.get(s.streamUri(song.id), headers: headers);
        final how = headers.isEmpty ? 'api_key only' : 'stream headers';
        expect(audio.statusCode, 200, reason: how);
        expect(
          audio.headers['content-type'],
          startsWith('audio/'),
          reason: how,
        );
        expect(audio.bodyBytes.length, greaterThan(1000));
      }

      // download: the original file, the token in the headers only
      final file = await client.get(s.downloadUri(song.id), headers: s.headers);
      expect(file.statusCode, 200);
      expect(ascii.decode(file.bodyBytes.sublist(0, 4)), 'fLaC');

      // listen: the song is marked played on the server
      await s.scrobble(song.id, DateTime.now());
      final item = jsonDecode(
        (await s.authedGet('Users/${s.userId}/Items/${song.id}')).body,
      );
      expect((item as Map)['UserData']['Played'], isTrue);

      // a cover the tones don't have is a 404, not an error
      final cover = await s.authedGetUri(s.coverUri(album.id, 300));
      expect(cover.statusCode, anyOf(200, 404));

      // playlists: none, and listing them works
      expect(await s.playlists(), isA<List<SourcePlaylist>>());
    });
  });
}
