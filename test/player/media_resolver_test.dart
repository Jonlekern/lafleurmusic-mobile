import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lafleurmusic/library/models.dart';
import 'package:lafleurmusic/player/media_resolver.dart';
import 'package:lafleurmusic/sources/source.dart';
import 'package:lafleurmusic/sources/subsonic.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart' hide Track;

SubsonicSource source(String id, {http.Client? client}) => SubsonicSource(
  accountId: id,
  base: Uri.parse('https://music.example.com'),
  user: 'johnny',
  password: 'pw',
  headers: const {'CF-Access-Client-Id': 'id1'},
  client: client ?? MockClient((r) async => http.Response('', 500)),
  salt: () => 'abc',
);

Track remote(String song, {String? coverId = 'al-1'}) => Track(
  path: 'subsonic://acc1/$song',
  accountId: 'acc1',
  remoteId: song,
  coverId: coverId,
  title: 'Night Swim',
  artist: 'Lafleur Surf',
  album: 'Summer Mix',
  durationMs: 1000,
  hasCover: true,
  size: 1,
);

void main() {
  group('MediaResolver', () {
    late List<String> asked;
    late MediaResolver r;
    setUp(() {
      asked = [];
      r = MediaResolver((id) async {
        asked.add(id);
        return source(id);
      });
    });

    test(
      'subsonic:// → authenticated stream URL with the account headers',
      () async {
        final m = await r.media('subsonic://acc1/s9');
        final u = Uri.parse(m.uri);
        expect(u.path, '/rest/stream.view');
        expect(u.queryParameters['id'], 's9');
        expect(u.queryParameters['u'], 'johnny');
        expect(u.queryParameters['t'], isNotEmpty);
        expect(m.httpHeaders, {'CF-Access-Client-Id': 'id1'});
      },
    );

    test('local file → Media(path) without headers', () async {
      final m = await r.media('/x/a.flac');
      expect(m.uri, '/x/a.flac');
      expect(m.httpHeaders, isNull);
      expect(asked, isEmpty);
    });

    test('the source of an account is built once, until invalidated', () async {
      await Future.wait([
        r.media('subsonic://acc1/s1'),
        r.media('subsonic://acc1/s2'),
      ]);
      await r.media('subsonic://acc1/s3');
      expect(asked, ['acc1']);
      r.invalidate('acc1');
      await r.media('subsonic://acc1/s4');
      expect(asked, ['acc1', 'acc1']);
    });

    test('account case kept: the id is not a lowercased host', () async {
      await r.media('subsonic://AbC/s1');
      expect(asked, ['AbC']);
    });

    test('account unusable (password gone) → the raw key: mpv fails it and the track is skipped', () async {
      var calls = 0;
      var now = DateTime(2026);
      final broken = MediaResolver((id) async {
        calls++;
        throw StateError('Missing password for account $id');
      }, clock: () => now);
      final m = await broken.media('subsonic://acc1/s9');
      expect(m.uri, 'subsonic://acc1/s9');
      expect(m.httpHeaders, isNull);
      // within a minute: no new database + keychain read
      now = now.add(const Duration(seconds: 59));
      await broken.media('subsonic://acc1/s9');
      await expectLater(broken.source('acc1'), throwsStateError);
      expect(calls, 1);
      // afterwards: tried again
      now = now.add(const Duration(seconds: 2));
      await broken.media('subsonic://acc1/s9');
      expect(calls, 2);
      // invalidate (password just fixed): tried at once
      broken.invalidate('acc1');
      await broken.media('subsonic://acc1/s9');
      expect(calls, 3);
    });
  });

  group('remoteCover', () {
    test('GET coverUri with the account headers', () async {
      late http.Request seen;
      final s = source(
        'acc1',
        client: MockClient((req) async {
          seen = req;
          return http.Response.bytes([1, 2, 3], 200);
        }),
      );
      final bytes = await remoteCover(s, 'al-1', 300);
      expect(bytes, Uint8List.fromList([1, 2, 3]));
      expect(seen.url.path, '/rest/getCoverArt.view');
      expect(seen.url.queryParameters['id'], 'al-1');
      expect(seen.url.queryParameters['size'], '300');
      expect(seen.headers['CF-Access-Client-Id'], 'id1');
    });

    test('SVG is an image, not an error body', () async {
      final s = source(
        'acc1',
        client: MockClient(
          (_) async => http.Response.bytes(
            [60, 115],
            200,
            headers: {'content-type': 'image/svg+xml'},
          ),
        ),
      );
      expect(await remoteCover(s, 'al-1', 64), isNotNull);
    });

    test('404, empty body or Subsonic error body → null', () async {
      for (final res in [
        http.Response('nope', 404),
        http.Response.bytes([], 200),
        http.Response('{}', 200, headers: {'content-type': 'application/json'}),
        http.Response(
          '<e/>',
          200,
          headers: {'content-type': 'text/xml; charset=utf-8'},
        ),
        http.Response(
          '<e/>',
          200,
          headers: {'content-type': 'application/xml'},
        ),
      ]) {
        final s = source('acc1', client: MockClient((_) async => res));
        expect(await remoteCover(s, 'al-1', 64), isNull);
      }
    });

    test('network error → SourceNetworkException without the URL', () async {
      final s = source(
        'acc1',
        client: MockClient(
          (req) async => throw http.ClientException('refused', req.url),
        ),
      );
      await expectLater(
        remoteCover(s, 'al-1', 64),
        throwsA(
          isA<SourceNetworkException>().having(
            (e) => '$e',
            'text',
            isNot(contains('t=')),
          ),
        ),
      );
    });
  });

  group('remoteCovers (Covers.remote)', () {
    test('looks up the track cover id, then downloads it', () async {
      final fetched = <String>[];
      final r = MediaResolver(
        (id) async => source(
          id,
          client: MockClient((req) async {
            fetched.add(req.url.queryParameters['id']!);
            return http.Response.bytes([9], 200);
          }),
        ),
      );
      final fetch = remoteCovers(r, (path) async => remote('s9'));
      expect(await fetch('subsonic://acc1/s9', 300), Uint8List.fromList([9]));
      expect(fetched, ['al-1']);
    });

    test('no cover id → null, nothing downloaded', () async {
      var built = 0;
      final r = MediaResolver((id) async {
        built++;
        return source(id);
      });
      final fetch = remoteCovers(
        r,
        (path) async => remote('s9', coverId: null),
      );
      expect(await fetch('subsonic://acc1/s9', 300), isNull);
      expect(
        await remoteCovers(r, (_) async => null)('subsonic://acc1/x', 64),
        isNull,
      );
      expect(built, 0);
    });
  });

  group('remoteCoverKey (Covers.remoteKey)', () {
    test('account + cover id: one key for the whole album', () async {
      final key = remoteCoverKey((path) async => remote(path.split('/').last));
      expect(await key('subsonic://acc1/s1'), 'acc1/al-1');
      expect(await key('subsonic://acc1/s2'), 'acc1/al-1');
      final none = remoteCoverKey((path) async => remote('s1', coverId: null));
      expect(await none('subsonic://acc1/s1'), isNull);
      expect(
        await remoteCoverKey((_) async => null)('subsonic://acc1/x'),
        isNull,
      );
    });
  });

  group('lock screen', () {
    test('server track: tags from the library, artwork as bytes', () {
      final art = Uint8List.fromList([1, 2]);
      final s = sessionFor(remote('s9'), art);
      expect(s.title, 'Night Swim');
      expect(s.artist, 'Lafleur Surf');
      expect(s.album, 'Summer Mix');
      final a = s.artwork as MediaSessionArtworkCustom;
      expect(a.cover.bytes, art);
      expect(a.cover.mimeType, 'image/jpeg');
    });

    test('server track without cover: no artwork, never a URL', () {
      expect(sessionFor(remote('s9'), null).artwork, MediaSessionArtwork.none);
    });

    test('local file: mpv reads tags and embedded cover', () {
      final local = Track(
        path: '/x/a.flac',
        title: 'a',
        artist: 'b',
        album: 'c',
        durationMs: 1,
        hasCover: true,
        size: 1,
      );
      final s = sessionFor(local, null);
      expect(s.title, isNull);
      expect(s.artwork, MediaSessionArtwork.embedded);
    });
  });
}
