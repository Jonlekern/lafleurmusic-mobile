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

const emptyAlbumList =
    '{"subsonic-response":{"status":"ok","version":"1.16.1","albumList2":{}}}';

/// The recorded album list at offset 0, then an empty page.
http.Response albumList(http.Request r) =>
    r.url.queryParameters['offset'] == '0'
    ? json(fixture('getAlbumList2'))
    : json(emptyAlbumList);

/// A server that never answers (home server seen from outside the house).
MockClient hanging() => MockClient((r) => Completer<http.Response>().future);

String albumPage(List<Map<String, Object?>> albums) => jsonEncode({
  'subsonic-response': {
    'status': 'ok',
    'version': '1.16.1',
    'albumList2': {'album': albums},
  },
});

SubsonicSource make(
  http.Client client, {
  String base = 'https://music.example.com',
  String password = 'pw',
  Map<String, String> headers = const {},
  Duration timeout = requestTimeout,
}) => SubsonicSource(
  accountId: 'acc1',
  base: Uri.parse(base),
  user: 'johnny',
  password: password,
  headers: headers,
  client: client,
  salt: () => 'abc',
  timeout: timeout,
);

void main() {
  group('test()', () {
    group('redirects', () {
      http.Response moved(String to, [int code = 301]) =>
          http.Response('', code, headers: {'location': to});

      test('same host http -> https: followed, new base reported', () async {
        final seen = <String>[];
        final headersSeen = <String?>[];
        final s = make(
          MockClient((r) async {
            seen.add(
              '${r.url.scheme}://${r.url.host}:${r.url.port}${r.url.path}',
            );
            headersSeen.add(r.headers['CF-Access-Client-Id']);
            if (r.url.scheme == 'http') {
              return moved('https://h:4533/rest/ping');
            }
            return json(fixture('ping'));
          }),
          base: 'http://h:4533',
          headers: {'CF-Access-Client-Id': 'id1'},
        );
        expect(s.redirectedBase, isNull);
        expect(await s.test(), TestResult.ok);
        expect(s.redirectedBase, Uri.parse('https://h:4533'));
        expect(seen, [
          'http://h:4533/rest/ping.view',
          'https://h:4533/rest/ping.view',
        ]);
        expect(headersSeen, ['id1', 'id1']);
      });

      test('http -> https on the default port', () async {
        final urls = <Uri>[];
        final s = make(
          MockClient((r) async {
            urls.add(r.url);
            return r.url.scheme == 'http'
                ? moved('https://h/rest/ping.view')
                : json(fixture('ping'));
          }),
          base: 'http://h:4533',
        );
        expect(await s.test(), TestResult.ok);
        expect(s.redirectedBase, Uri.parse('https://h'));
        expect(urls, hasLength(2));
        expect(urls[1].scheme, 'https');
        expect(urls[1].port, 443);
        expect(urls[1].hasPort, isFalse);
        expect(urls[1].path, '/rest/ping.view');
        expect(urls[1].toString(), isNot(contains('4533')));
      });

      test('another host stays headerRefused', () async {
        final s = make(
          MockClient((r) async => moved('https://login.autre.com', 302)),
          base: 'http://h:4533',
        );
        expect(await s.test(), TestResult.headerRefused);
        expect(s.redirectedBase, isNull);
      });

      test('a redirect loop (4 hops) is headerRefused', () async {
        var n = 0;
        final s = make(
          MockClient((r) async {
            n++;
            return moved('https://h:4533/rest/ping');
          }),
          base: 'https://h:4533',
        );
        expect(await s.test(), TestResult.headerRefused);
        expect(n, 4);
      });

      test('https -> http is refused', () async {
        final s = make(
          MockClient((r) async => moved('http://h:4533/rest/ping')),
          base: 'https://h:4533',
        );
        expect(await s.test(), TestResult.headerRefused);
      });

      test(
        'credentials stay out of exceptions: query kept on the hop',
        () async {
          final queries = <String>[];
          final s = make(
            MockClient((r) async {
              queries.add(r.url.queryParameters['u'] ?? '');
              return r.url.scheme == 'http'
                  ? moved('https://h:4533/rest/ping')
                  : json(fixture('ping'));
            }),
            base: 'http://h:4533',
          );
          await s.test();
          expect(queries, everyElement(isNotEmpty));
        },
      );
    });

    test('ok on a successful ping', () async {
      final s = make(MockClient((r) async => json(fixture('ping'))));
      expect(await s.test(), TestResult.ok);
    });

    test('wrongPassword on error 40', () async {
      final s = make(MockClient((r) async => json(fixture('error40'))));
      expect(await s.test(), TestResult.wrongPassword);
    });

    test('wrongPassword on the bare error-40 body from the brief', () async {
      final s = make(
        MockClient(
          (r) async => json(
            '{"subsonic-response":{"status":"failed","error":{"code":40}}}',
          ),
        ),
      );
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
        final s = make(
          MockClient(
            (r) async => http.Response('<html>Access denied</html>', code),
          ),
        );
        expect(await s.test(), TestResult.headerRefused, reason: '$code');
      }
    });

    test('a 401 carrying a Subsonic error 40 is a wrong password', () async {
      final s = make(MockClient((r) async => json(fixture('error40'), 401)));
      expect(await s.test(), TestResult.wrongPassword);
    });

    test('notSubsonic on an HTML 200', () async {
      final s = make(
        MockClient(
          (r) async => http.Response('<html><body>Hi</body></html>', 200),
        ),
      );
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
      final s = make(
        MockClient((r) async => json(fixture('ping'))),
        password: 'sekret',
      );
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
        final s = make(
          MockClient((r) async => json(fixture('ping'))),
          base: base,
        );
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
        base: 'https://h.example/music',
      );
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

    test('downloadUri asks for the original file with auth params', () {
      final s = make(MockClient((r) async => json(fixture('ping'))));
      final d = s.downloadUri('s-1');
      expect(d.path, '/rest/download.view');
      expect(d.queryParameters['id'], 's-1');
      expect(d.queryParameters['u'], 'johnny');
      expect(d.queryParameters['t'], isNotEmpty);
    });
  });

  group('headers', () {
    test('every request carries the account headers', () async {
      final seen = <String, String?>{};
      final client = MockClient((r) async {
        seen[r.url.path] = r.headers['CF-Access-Client-Id'];
        if (r.url.path.endsWith('getAlbumList2.view')) return albumList(r);
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
        ]),
      );
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
            {'id': 'a${off + i}', 'name': 'N${off + i}', 'artist': 'Johnny'},
        ];
        return json(
          jsonEncode({
            'subsonic-response': {
              'status': 'ok',
              'version': '1.16.1',
              'albumList2': {'album': items},
            },
          }),
        );
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
      expect(offsets, [0, 500, 1000]);
      // only an empty page ends the list (a server may cap pages below 500)
      expect(await it.moveNext(), isFalse);
      expect(offsets, [0, 500, 1000, 1200]);
    });

    test('a server capping pages at 100 still lists every album', () async {
      final offsets = <int>[];
      final client = MockClient((r) async {
        final off = int.parse(r.url.queryParameters['offset']!);
        offsets.add(off);
        final n = (250 - off).clamp(0, 100); // ignores size=500
        return json(
          albumPage([
            for (var i = 0; i < n; i++)
              {'id': 'a${off + i}', 'name': 'N${off + i}', 'artist': 'J'},
          ]),
        );
      });
      final pages = await make(client).albums().toList();
      expect(pages.map((p) => p.length), [100, 100, 50]);
      expect(offsets, [0, 100, 200, 250]);
    });

    test(
      'a server ignoring the offset: stops with an error, no endless loop',
      () async {
        var calls = 0;
        final client = MockClient((r) async {
          calls++;
          return json(
            albumPage([
              {'id': 'a', 'name': 'A', 'artist': 'x'},
              {'id': 'b', 'name': 'B', 'artist': 'x'},
            ]),
          );
        });
        final pages = <List<SourceAlbum>>[];
        Object? error;
        try {
          await for (final p in make(client).albums(pageSize: 2)) {
            pages.add(p);
          }
        } catch (e) {
          error = e;
        }
        expect(pages, hasLength(1));
        expect(error, isA<SubsonicException>());
        expect(calls, 2);
      },
    );

    test('maps fields from the recorded response', () async {
      final s = make(MockClient((r) async => albumList(r)));
      final pages = await s.albums().toList();
      expect(pages.length, 1);
      final a = pages.single;
      expect(a.map((e) => e.name), [
        'Studio Lafleur',
        'Lafleur Surf',
        'Summer Mix',
      ]);
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
        return json(
          jsonEncode({
            'subsonic-response': {
              'status': 'ok',
              'version': '1.16.1',
              'albumList2': off == 0
                  ? {
                      'album': [
                        {'id': 'a', 'name': 'A', 'artist': 'x'},
                        {'id': 'b', 'name': 'B', 'artist': 'x'},
                      ],
                    }
                  : {},
            },
          }),
        );
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
      final s = make(
        MockClient((r) async {
          seen = r.url;
          return json(fixture('getAlbum'));
        }),
      );
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
      final s = make(
        MockClient((r) async {
          seen = r.url;
          return json(fixture('ping'));
        }),
      );
      final at = DateTime.fromMillisecondsSinceEpoch(1700000000123);
      await s.scrobble('s-1', at);
      expect(seen.path, '/rest/scrobble.view');
      expect(seen.queryParameters['id'], 's-1');
      expect(seen.queryParameters['time'], '1700000000123');
      expect(seen.queryParameters['submission'], 'true');
    });
  });

  group('network errors carry no credentials', () {
    final failures = <String, Object>{
      'ClientException': http.ClientException(
        'Connection refused',
        Uri.parse(
          'https://music.example.com/rest/getAlbum.view?u=johnny&t=deadbeef&s=abc&id=1',
        ),
      ),
      'SocketException': const SocketException('Connection refused'),
      'TimeoutException': TimeoutException('slow'),
    };
    for (final MapEntry(key: kind, value: error) in failures.entries) {
      test(kind, () async {
        final s = make(MockClient((r) async => throw error));
        Object? caught;
        try {
          await s.albumSongs('1');
        } catch (e) {
          caught = e;
        }
        expect(caught, isA<SourceNetworkException>());
        final e = caught! as SourceNetworkException;
        expect(e.kind, kind); // the original type stays recognisable
        expect(e, isA<Exception>()); // sync still treats it as a failure
        for (final secret in ['t=', 's=', 'u=', 'deadbeef', 'johnny']) {
          expect('$e', isNot(contains(secret)), reason: '$e');
        }
      });
    }

    test('scrobble wraps network errors too', () async {
      final s = make(
        MockClient((r) async => throw http.ClientException('reset', r.url)),
      );
      await expectLater(
        s.scrobble('9', DateTime(2026)),
        throwsA(isA<SourceNetworkException>()),
      );
    });
  });

  group('timeouts (home server seen from outside the house)', () {
    const short = Duration(milliseconds: 50);

    test('a request that never answers fails as a network error', () async {
      final s = make(hanging(), timeout: short);
      final sw = Stopwatch()..start();
      await expectLater(
        s.albumSongs('1'),
        throwsA(isA<SourceNetworkException>()),
      );
      expect(sw.elapsed, lessThan(const Duration(seconds: 5)));
    });

    test('the album list fails too (sync ends incomplete)', () async {
      final s = make(hanging(), timeout: short);
      await expectLater(
        s.albums().toList(),
        throwsA(isA<SourceNetworkException>()),
      );
    });

    test('Tester: unreachable within the timeout', () async {
      final s = make(hanging(), timeout: short);
      expect(await s.test(), TestResult.unreachable);
    });

    test('the timeout text carries no credentials', () async {
      final s = make(hanging(), timeout: short);
      try {
        await s.scrobble('1', DateTime(2026));
        fail('no error');
      } on SourceNetworkException catch (e) {
        expect(e.kind, 'TimeoutException');
        for (final secret in ['t=', 's=', 'u=', 'johnny', 'http']) {
          expect('$e', isNot(contains(secret)));
        }
      }
    });

    test('defaults: 15 s per request, 8 s to connect', () {
      expect(requestTimeout, const Duration(seconds: 15));
      expect(connectTimeout, const Duration(seconds: 8));
      expect(
        SubsonicSource(
          accountId: 'a',
          base: Uri.parse('http://h'),
          user: 'u',
          password: 'p',
        ).timeout,
        requestTimeout,
      );
    });
  });

  group('Tester: redirects and certificates', () {
    test('redirects are not followed; a 3xx is a refused header', () async {
      for (final code in [301, 302, 303, 307, 308]) {
        late bool follow;
        final s = make(
          MockClient((r) async {
            follow = r.followRedirects;
            return http.Response(
              '',
              code,
              headers: {'location': 'https://login.example.com/'},
            );
          }),
        );
        expect(await s.test(), TestResult.headerRefused, reason: '$code');
        expect(follow, isFalse);
      }
    });

    test(
      'a refused certificate is told apart from an unreachable server',
      () async {
        for (final e in [
          const HandshakeException('CERTIFICATE_VERIFY_FAILED'),
          const TlsException('bad certificate'),
        ]) {
          final s = make(MockClient((r) async => throw e));
          expect(await s.test(), TestResult.certificateRejected, reason: '$e');
        }
      },
    );
  });

  group('lenient JSON (numbers where strings are expected)', () {
    test('albums and songs with numeric ids, cover ids and suffix', () async {
      final s = make(
        MockClient((r) async {
          if (r.url.path.endsWith('getAlbumList2.view')) {
            return json(
              r.url.queryParameters['offset'] == '0'
                  ? albumPage([
                      {
                        'id': 7,
                        'name': 2024,
                        'artist': 'J',
                        'coverArt': 42,
                        'songCount': '3',
                      },
                    ])
                  : emptyAlbumList,
            );
          }
          return json(
            jsonEncode({
              'subsonic-response': {
                'status': 'ok',
                'album': {
                  'id': 7,
                  'name': 'A',
                  'song': [
                    {
                      'id': 99,
                      'title': 1999,
                      'coverArt': 42,
                      'suffix': 3,
                      'track': '4',
                      'duration': '61.5',
                      'size': 1000,
                      'replayGain': {'trackGain': '-6.5', 'albumGain': -7},
                      'playCount': '2',
                    },
                    'not a song',
                  ],
                },
              },
            }),
          );
        }),
      );
      final albums = (await s.albums().toList()).expand((p) => p).toList();
      expect(albums.single.id, '7');
      expect(albums.single.name, '2024');
      expect(albums.single.coverId, '42');
      expect(albums.single.songCount, 3);
      final song = (await s.albumSongs('7')).single;
      expect(song.id, '99');
      expect(song.title, '1999');
      expect(song.coverId, '42');
      expect(song.suffix, '3');
      expect(song.track, 4);
      expect(song.durationMs, 61500);
      expect(song.replayGainTrack, -6.5);
      expect(song.replayGainAlbum, -7.0);
      expect(song.playCount, 2);
    });
  });

  group('playlists()', () {
    String body(Map<String, Object?> r) => jsonEncode({
      'subsonic-response': {'status': 'ok', 'version': '1.16.1', ...r},
    });

    test(
      'getPlaylists then getPlaylist for each, songs in order with duplicates',
      () async {
        final calls = <String>[];
        final s = make(
          MockClient((r) async {
            calls.add(r.url.pathSegments.last);
            expect(r.headers['X-Gate'], 'open');
            if (r.url.path.endsWith('getPlaylists.view')) {
              return json(
                body({
                  'playlists': {
                    'playlist': [
                      {'id': 'p1', 'name': 'Soirée', 'songCount': 3},
                      {'id': 7, 'name': 'Running'},
                    ],
                  },
                }),
              );
            }
            final id = r.url.queryParameters['id'];
            return json(
              body({
                'playlist': {
                  'id': id,
                  'name': id == 'p1' ? 'Soirée' : 'Running',
                  if (id == 'p1')
                    'entry': [
                      {'id': 's1', 'title': 'Ocean Drive'},
                      {'id': 's2', 'title': 'Lafleur Surf'},
                      {'id': 's1', 'title': 'Ocean Drive'},
                    ],
                },
              }),
            );
          }),
          headers: {'X-Gate': 'open'},
        );
        final lists = await s.playlists();
        expect(calls, [
          'getPlaylists.view',
          'getPlaylist.view',
          'getPlaylist.view',
        ]);
        expect(
          [for (final p in lists) (p.id, p.name)],
          [('p1', 'Soirée'), ('7', 'Running')],
        );
        expect(lists[0].songIds, ['s1', 's2', 's1']);
        expect(lists[1].songIds, isEmpty);
      },
    );

    test('no playlist at all: an empty list', () async {
      final s = make(MockClient((r) async => json(body({'playlists': {}}))));
      expect(await s.playlists(), isEmpty);
    });

    test('a Subsonic error surfaces as an exception', () async {
      final s = make(
        MockClient(
          (r) async => json(
            '{"subsonic-response":{"status":"failed","error":{"code":0,"message":"x"}}}',
          ),
        ),
      );
      await expectLater(s.playlists(), throwsA(isA<SubsonicException>()));
    });
  });

  test('close() closes the HTTP client', () {
    var closed = false;
    final s = make(_ClosingClient(() => closed = true));
    s.close();
    expect(closed, isTrue);
  });

  test('accountId is exposed', () {
    expect(
      make(MockClient((r) async => json(fixture('ping')))).accountId,
      'acc1',
    );
  });
}

class _ClosingClient extends http.BaseClient {
  _ClosingClient(this.onClose);
  final void Function() onClose;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      throw UnimplementedError();
  @override
  void close() => onClose();
}
