// Contract with a real Navidrome (plan 1, task 10): our Subsonic client against the server itself,
// not against recordings. Skipped unless NAVIDROME_URL is set (CI job `navidrome`, see
// tool/navidrome-ci.sh):
//
//   NAVIDROME_URL=http://localhost:4533 NAVIDROME_USER=… NAVIDROME_PASSWORD=… \
//     flutter test test/sources/navidrome_contract_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lafleurmusic/sources/source.dart';
import 'package:lafleurmusic/sources/subsonic.dart';

final _env = Platform.environment;
final _url = _env['NAVIDROME_URL'] ?? '';
final String? _skip = _url.isEmpty
    ? 'NAVIDROME_URL not set (runs in the CI job `navidrome`)'
    : null;

void main() {
  final client = http.Client();
  tearDownAll(client.close);

  SubsonicSource source() => SubsonicSource(
    accountId: 'navidrome',
    base: Uri.parse(_url),
    user: _env['NAVIDROME_USER'] ?? '',
    password: _env['NAVIDROME_PASSWORD'] ?? '',
    client: client,
  );

  group('Navidrome contract', skip: _skip, () {
    test('ping is ok', () async {
      expect(await source().test(), TestResult.ok);
    });

    test('wrong password is reported as such', () async {
      final bad = SubsonicSource(
        accountId: 'navidrome',
        base: Uri.parse(_url),
        user: _env['NAVIDROME_USER'] ?? '',
        password: 'not-the-password',
        client: client,
      );
      expect(await bad.test(), TestResult.wrongPassword);
    });

    test('albums, songs of the first one, stream and cover', () async {
      final s = source();
      final albums = (await s.albums().toList()).expand((p) => p).toList();
      expect(albums, isNotEmpty);

      final songs = await s.albumSongs(albums.first.id);
      expect(songs, isNotEmpty);
      expect(songs.first.id, isNotEmpty);

      final audio = await client.get(s.streamUri(songs.first.id));
      expect(audio.statusCode, 200);
      expect(audio.headers['content-type'], startsWith('audio/'));
      expect(audio.bodyBytes, isNotEmpty);

      final coverId = albums.first.coverId ?? songs.first.coverId;
      if (coverId != null) {
        final cover = await client.get(s.coverUri(coverId, 300));
        expect(cover.statusCode, anyOf(200, 404));
      }
    });
  });
}
