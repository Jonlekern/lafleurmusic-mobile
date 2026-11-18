// The fake server of the end-to-end run (integration_test/fake_subsonic.dart): its answers are
// still the recorded ones, and our Subsonic client talks to it like to Navidrome.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lafleurmusic/sources/source.dart';
import 'package:lafleurmusic/sources/subsonic.dart';

import '../integration_test/fake_subsonic.dart';

Object? fixture(String name) =>
    jsonDecode(File('test/fixtures/subsonic/$name.json').readAsStringSync());

void main() {
  test('the embedded answers are the recorded fixtures', () {
    expect(jsonDecode(pingJson), fixture('ping'));
    expect(jsonDecode(error40Json), fixture('error40'));
    expect(jsonDecode(albumList2Json), fixture('getAlbumList2'));
    expect(jsonDecode(albumJson), fixture('getAlbum'));
  });

  group('against the fake server', () {
    late FakeSubsonic fake;
    final client = http.Client();
    setUp(() async => fake = await FakeSubsonic.start());
    tearDown(() => fake.close());
    tearDownAll(client.close);

    SubsonicSource source({
      String? password,
      Map<String, String> headers = const {fakeHeader: fakeHeaderValue},
    }) => SubsonicSource(
      accountId: 'acc',
      base: Uri.parse(fake.address),
      user: fake.user,
      password: password ?? fake.password,
      headers: headers,
      client: client,
    );

    test('ping: ok, header refused, wrong password', () async {
      expect(await source().test(), TestResult.ok);
      expect(await source(headers: const {}).test(), TestResult.headerRefused);
      expect(await source(password: 'nope').test(), TestResult.wrongPassword);
    });

    test(
      'one consistent album, its two songs, the stream and the cover',
      () async {
        final s = source();
        final albums = (await s.albums().toList()).expand((p) => p).toList();
        expect(albums.map((a) => a.id), ['al-1']);
        expect(albums.single.songCount, 2);
        final songs = await s.albumSongs('al-1');
        expect(songs.map((x) => x.id), ['s-1', 's-2']);

        final audio = await client.get(s.streamUri('s-1'), headers: s.headers);
        expect(audio.statusCode, 200);
        expect(audio.headers['content-type'], startsWith('audio/'));
        expect(audio.bodyBytes, File('test/fixtures/a.flac').readAsBytesSync());

        final cover = await client.get(
          s.coverUri('al-1', 300),
          headers: s.headers,
        );
        expect(cover.statusCode, 200);
        expect(cover.headers['content-type'], 'image/png');

        await s.scrobble('s-1', DateTime(2026));
        expect(fake.requests.last.method, 'scrobble');
        expect(fake.requests.last.status, 200);
        // the log keeps neither the token nor the salt
        expect(fake.requests.every((r) => !r.params.containsKey('t')), isTrue);
      },
    );
  });
}
