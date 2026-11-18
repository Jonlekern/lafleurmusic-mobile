import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lafleurmusic/sources/source.dart';
import 'package:lafleurmusic/sources/subsonic.dart';

String fixture(String name) =>
    File('test/fixtures/subsonic/$name.json').readAsStringSync();

http.Response json(String body, [int code = 200]) => http.Response(
      body,
      code,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

SubsonicSource make(
  http.Client client, {
  String base = 'https://music.example.com',
  String password = 'pw',
  Map<String, String> headers = const {},
}) =>
    SubsonicSource(
      accountId: 'acc1',
      base: Uri.parse(base),
      user: 'johnny',
      password: password,
      headers: headers,
      client: client,
      salt: () => 'abc',
    );

void main() {
  group('test()', () {
    test('ok on a successful ping', () async {
      final s = make(MockClient((r) async => json(fixture('ping'))));
      expect(await s.test(), TestResult.ok);
    });

    test('wrongPassword on error 40', () async {
      final s = make(MockClient((r) async => json(fixture('error40'))));
      expect(await s.test(), TestResult.wrongPassword);
    });

    test('wrongPassword on the bare error-40 body from the brief', () async {
      final s = make(MockClient((r) async => json(
          '{"subsonic-response":{"status":"failed","error":{"code":40}}}')));
      expect(await s.test(), TestResult.wrongPassword);
    });

    test('unreachable on SocketException', () async {
      final s = make(MockClient((r) async => throw const SocketException('x')));
      expect(await s.test(), TestResult.unreachable);
    });

    test('unreachable on http ClientException', () async {
      final s = make(MockClient((r) async => throw http.ClientException('x')));
      expect(await s.test(), TestResult.unreachable);
    });

    test('headerRefused on 401/403 without Subsonic body', () async {
      for (final code in [401, 403]) {
        final s = make(MockClient(
            (r) async => http.Response('<html>Access denied</html>', code)));
        expect(await s.test(), TestResult.headerRefused, reason: '$code');
      }
    });

    test('a 401 carrying a Subsonic error 40 is a wrong password', () async {
      final s = make(MockClient((r) async => json(fixture('error40'), 401)));
      expect(await s.test(), TestResult.wrongPassword);
    });

    test('notSubsonic on an HTML 200', () async {
      final s = make(MockClient(
          (r) async => http.Response('<html><body>Hi</body></html>', 200)));
      expect(await s.test(), TestResult.notSubsonic);
    });

    test('notSubsonic on JSON without subsonic-response', () async {
      final s = make(MockClient((r) async => json('{"a":1}')));
      expect(await s.test(), TestResult.notSubsonic);
    });
  });

  group('auth', () {
    test('token is md5(password + salt), encoded in the URL', () async {
      late Uri seen;
      final s = make(
        MockClient((r) async {
          seen = r.url;
          return json(fixture('ping'));
        }),
        password: 'é&+ x',
      );
      await s.test();
      final expected = md5.convert(utf8.encode('é&+ xabc')).toString();
      final q = seen.queryParameters;
      expect(q['t'], expected);
      expect(q['s'], 'abc');
      expect(q['u'], 'johnny');
      expect(q['v'], '1.16.1');
      expect(q['c'], 'LAFLEURMUSIC');
      expect(q['f'], 'json');
      expect(seen.toString(), contains('t=$expected'));
      expect(seen.toString(), isNot(contains('é')));
      expect(seen.toString(), isNot(contains('p=')));
    });

    test('the password never appears in a URL', () async {
      final s = make(MockClient((r) async => json(fixture('ping'))),
          password: 'sekret');
      expect(s.streamUri('s-1').toString(), isNot(contains('sekret')));
      expect(s.coverUri('al-1', 300).toString(), isNot(contains('sekret')));
    });

    test('default salt is random 12 hex chars', () {
      SubsonicSource mk() => SubsonicSource(
            accountId: 'a',
            base: Uri.parse('https://h'),
            user: 'u',
            password: 'p',
          );
      final a = mk().streamUri('1').queryParameters['s']!;
      final b = mk().streamUri('1').queryParameters['s']!;
      expect(a, matches(RegExp(r'^[0-9a-f]{12}$')));
      expect(a, isNot(b));
    });
  });

  group('urls', () {
    test('base with and without trailing slash, and with sub-path', () {
      for (final base in [
        'https://h.example',
        'https://h.example/',
        'https://h.example/music',
        'https://h.example/music/',
      ]) {
        final s =
            make(MockClient((r) async => json(fixture('ping'))), base: base);
        final prefix = base.endsWith('/') ? base : '$base/';
        final u = s.streamUri('s-1').toString();
        expect(u, startsWith('${prefix}rest/stream.view?'), reason: base);
        expect(s.streamUri('s-1').queryParameters['id'], 's-1');
      }
    });

    test('request on a sub-path hits <base>/rest/ping.view', () async {
      late Uri seen;
      final s = make(
          MockClient((r) async {
            seen = r.url;
            return json(fixture('ping'));
          }),
          base: 'https://h.example/music');
      await s.test();
      expect(seen.path, '/music/rest/ping.view');
    });

    test('coverUri and streamUri carry auth params', () {
      final s = make(MockClient((r) async => json(fixture('ping'))));
      final c = s.coverUri('al-1', 300);
      expect(c.path, '/rest/getCoverArt.view');
      expect(c.queryParameters['id'], 'al-1');
      expect(c.queryParameters['size'], '300');
      expect(c.queryParameters['t'], isNotEmpty);
      final st = s.streamUri('s-1');
      expect(st.path, '/rest/stream.view');
      expect(st.queryParameters['id'], 's-1');
      expect(st.queryParameters['u'], 'johnny');
    });
  });

  group('headers', () {
    test('every request carries the account headers', () async {
      final seen = <String, String?>{};
      final client = MockClient((r) async {
        seen[r.url.path] = r.headers['CF-Access-Client-Id'];
        if (r.url.path.endsWith('getAlbumList2.view')) {
          return json(fixture('getAlbumList2'));
        }
        if (r.url.path.endsWith('getAlbum.view')) {
          return json(fixture('getAlbum'));
        }
        if (r.url.path.endsWith('getCoverArt.view')) {
          return http.Response('img', 200);
        }
        return json(fixture('ping'));
      });
      final s = make(client, headers: {'CF-Access-Client-Id': 'id1'});
      await s.test();
      await s.albums().toList();
      await s.albumSongs('al-1');
      await s.scrobble('s-1', DateTime.fromMillisecondsSinceEpoch(1));
      // The app fetches covers itself, with s.headers.
      await client.get(s.coverUri('al-1', 100), headers: s.headers);
      expect(
          seen.keys,
          containsAll([
            '/rest/ping.view',
            '/rest/getAlbumList2.view',
            '/rest/getAlbum.view',
            '/rest/scrobble.view',
            '/rest/getCoverArt.view',
          ]));
      expect(seen.values, everyElement('id1'));
      expect(s.headers, {'CF-Access-Client-Id': 'id1'});
    });
  });

  group('albums()', () {
    test('1200 albums -> pages of 500, 500, 200, fetched lazily', () async {
      final offsets = <int>[];
      final client = MockClient((r) async {
        expect(r.url.path, '/rest/getAlbumList2.view');
        expect(r.url.queryParameters['type'], 'alphabeticalByName');
        expect(r.url.queryParameters['size'], '500');
        final off = int.parse(r.url.queryParameters['offset']!);
        offsets.add(off);
        final n = (1200 - off).clamp(0, 500);
        final items = [
          for (var i = 0; i < n; i++)
            {'id': 'a${off + i}', 'name': 'N${off + i}', 'artist': 'Johnny'}
        ];
        return json(jsonEncode({
          'subsonic-response': {
            'status': 'ok',
            'version': '1.16.1',
            'albumList2': {'album': items}
          }
        }));
      });
      final it = StreamIterator(make(client).albums(pageSize: 500));
      expect(offsets, isEmpty);
      expect(await it.moveNext(), isTrue);
      expect(it.current.length, 500);
      expect(offsets, [0]);
      expect(await it.moveNext(), isTrue);
      expect(it.current.length, 500);
      expect(offsets, [0, 500]);
      expect(await it.moveNext(), isTrue);
      expect(it.current.length, 200);
      expect(await it.moveNext(), isFalse);
      expect(offsets, [0, 500, 1000]);
    });

    test('maps fields from the recorded response', () async {
      final s = make(MockClient((r) async => json(fixture('getAlbumList2'))));
      final pages = await s.albums().toList();
      expect(pages.length, 1);
      final a = pages.single;
      expect(a.map((e) => e.name),
          ['Studio Lafleur', 'Lafleur Surf', 'Summer Mix']);
      expect(a[0].artist, 'LAFLEURSTUDIO');
      expect(a[0].coverId, 'al-1');
      expect(a[0].songCount, 10);
      expect(a[2].coverId, isNull);
    });

    test('an exact multiple of pageSize ends on an empty page', () async {
      var calls = 0;
      final client = MockClient((r) async {
        calls++;
        final off = int.parse(r.url.queryParameters['offset']!);
        return json(jsonEncode({
          'subsonic-response': {
            'status': 'ok',
            'version': '1.16.1',
            'albumList2': off == 0
                ? {
                    'album': [
                      {'id': 'a', 'name': 'A', 'artist': 'x'},
                      {'id': 'b', 'name': 'B', 'artist': 'x'}
                    ]
                  }
                : {}
          }
        }));
      });
      final pages = await make(client).albums(pageSize: 2).toList();
      expect(pages.map((p) => p.length), [2]);
      expect(calls, 2);
    });

    test('a Subsonic error surfaces as an exception', () async {
      final s = make(MockClient((r) async => json(fixture('error40'))));
      expect(s.albums().toList(), throwsA(isA<SubsonicException>()));
    });
  });

  group('albumSongs()', () {
    test('reads songs, replayGain when present, null otherwise', () async {
      late Uri seen;
      final s = make(MockClient((r) async {
        seen = r.url;
        return json(fixture('getAlbum'));
      }));
      final songs = await s.albumSongs('al-1');
      expect(seen.queryParameters['id'], 'al-1');
      expect(songs.length, 2);
      final a = songs[0];
      expect(a.id, 's-1');
      expect(a.title, 'Night Drive');
      expect(a.artist, 'Kavinsky');
      expect(a.albumArtist, 'LAFLEURSTUDIO');
      expect(a.genre, 'Synthwave');
      expect(a.track, 1);
      expect(a.disc, 1);
      expect(a.durationMs, 215000);
      expect(a.size, 8601234);
      expect(a.suffix, 'flac');
      expect(a.coverId, 'al-1');
      expect(a.playCount, 3);
      expect(a.replayGainTrack, -6.5);
      expect(a.replayGainAlbum, -7.2);
      final b = songs[1];
      expect(b.replayGainTrack, isNull);
      expect(b.replayGainAlbum, isNull);
      expect(b.disc, isNull);
      expect(b.durationMs, 180500);
      expect(b.playCount, 0);
    });
  });

  group('scrobble()', () {
    test('sends id, time in ms and submission=true', () async {
      late Uri seen;
      final s = make(MockClient((r) async {
        seen = r.url;
        return json(fixture('ping'));
      }));
      final at = DateTime.fromMillisecondsSinceEpoch(1700000000123);
      await s.scrobble('s-1', at);
      expect(seen.path, '/rest/scrobble.view');
      expect(seen.queryParameters['id'], 's-1');
      expect(seen.queryParameters['time'], '1700000000123');
      expect(seen.queryParameters['submission'], 'true');
    });
  });

  test('accountId is exposed', () {
    expect(make(MockClient((r) async => json(fixture('ping')))).accountId,
        'acc1');
  });
}
