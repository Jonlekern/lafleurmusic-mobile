// The fake Jellyfin of the end-to-end run (integration_test/fake_jellyfin.dart): our Jellyfin
// client talks to it like to a real server, and it carries the fake Navidrome's album.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lafleurmusic/sources/jellyfin.dart';
import 'package:lafleurmusic/sources/source.dart';

import '../integration_test/fake_jellyfin.dart';
import '../integration_test/fake_subsonic.dart'
    show albumJson, fakeHeader, fakeHeaderValue;

void main() {
  late FakeJellyfin fake;
  final client = http.Client();
  setUp(() async => fake = await FakeJellyfin.start());
  tearDown(() => fake.close());
  tearDownAll(client.close);

  JellyfinSource source({
    String? password,
    Map<String, String> headers = const {fakeHeader: fakeHeaderValue},
  }) => JellyfinSource(
    accountId: 'jf',
    base: Uri.parse(fake.address),
    user: fake.user,
    password: password ?? fake.password,
    headers: headers,
    client: http.Client(),
    deviceName: 'iPhone',
  );

  test(
    'Tester: ok, wrong password, and the proxy header is required',
    () async {
      expect(await source().test(), TestResult.ok);
      expect(await source(password: 'nope').test(), TestResult.wrongPassword);
      expect(await source(headers: const {}).test(), TestResult.headerRefused);
    },
  );

  test('the album and its songs are the fake Navidrome ones', () async {
    final s = source();
    final albums = (await s.albums().toList()).expand((p) => p).toList();
    expect(albums.map((a) => (a.name, a.artist)), [
      ('Studio Lafleur', 'LAFLEURSTUDIO'),
    ]);
    final songs = await s.albumSongs(albums.single.id);
    final navidrome =
        ((((jsonDecode(albumJson) as Map)['subsonic-response'] as Map)['album']
                    as Map)['song']
                as List)
            .cast<Map>();
    expect(songs.map((x) => (x.title, x.track, x.album, x.albumArtist)), [
      for (final n in navidrome)
        (n['title'], n['track'], n['album'], n['albumArtist']),
    ]);
  });

  test(
    'stream (token as api_key), download, listen; nothing without the token',
    () async {
      final s = source();
      await s.prepare();
      final id = (await s.albumSongs(FakeJellyfin.albumId)).first.id;

      final audio = await client.get(s.streamUri(id), headers: s.headers);
      expect(audio.statusCode, 200);
      expect(audio.headers['content-type'], startsWith('audio/'));
      expect(audio.bodyBytes, isNotEmpty);

      final file = await client.get(s.downloadUri(id), headers: s.headers);
      expect(file.statusCode, 200);
      expect(file.bodyBytes, audio.bodyBytes);

      final bare = await client.get(
        s.downloadUri(id),
        headers: const {fakeHeader: fakeHeaderValue},
      );
      expect(bare.statusCode, 401);

      await s.scrobble(id, DateTime.utc(2026, 11, 19, 12));
      final played = fake.requests.where((r) => r.method == 'played').single;
      expect(played.params['id'], id);
      expect(played.params['DatePlayed'], startsWith('2026-11-19T12:00:00'));
      expect(fake.playCount(id), 1);
      // the token never lands in the log
      expect(
        fake.requests.expand((r) => r.params.values),
        isNot(contains(fake.token)),
      );
    },
  );

  test('down: the connection is cut', () async {
    fake.down = true;
    expect(await source().test(), TestResult.unreachable);
    expect(fake.refused, greaterThan(0));
  });
}
