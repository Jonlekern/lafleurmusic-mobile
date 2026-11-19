import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lafleurmusic/library/play_counter.dart' show scrobbleRefused;
import 'package:lafleurmusic/sources/plex.dart';
import 'package:lafleurmusic/sources/plex_link.dart';
import 'package:lafleurmusic/sources/source.dart';

import 'fake_plex.dart';
import 'fake_secret_store.dart';

const albumOf = {
  '101': '11',
  '102': '11',
  '121': '12',
  '122': '12',
  '211': '21',
};

/// A fake Plex Media Server: songs (`/library/metadata/{id}`), albums' children, listens.
class Pms {
  final pms = FakePms();
  final log = <http.Request>[];
  Set<String> gone = {}; // songs the server doesn't have
  Set<String> noPart = {}; // songs that have no file
  Set<String> childrenFailing = {};
  Map<String, int> scrobbleStatus = {}; // per key
  int songStatus = 200; // forced status for a song read
  bool twoParts = false;

  Map song(String id) {
    final file = File('test/fixtures/plex/children_${albumOf[id]}.json');
    final items =
        (jsonDecode(file.readAsStringSync())['MediaContainer']['Metadata']
                as List)
            .cast<Map>();
    final m = Map.of(items.firstWhere((m) => m['ratingKey'] == id));
    m['parentRatingKey'] = albumOf[id];
    if (noPart.contains(id)) {
      m['Media'] = [<String, Object?>{}];
    } else if (twoParts) {
      final media = Map.of((m['Media'] as List).first as Map);
      media['Part'] = [
        ...(media['Part'] as List),
        {'id': 9, 'key': '/library/parts/9/1/file.wav', 'size': 1},
      ];
      m['Media'] = [media];
    }
    return m;
  }

  bool isDown(http.Request r) => pms.down.contains(r.url.host);

  Future<http.Response> handle(http.Request r) async {
    final p = r.url.path;
    if (isDown(r)) throw const SocketException('no route to host');
    if (r.url.host == homeLocal || r.url.host == homeRemote) {
      final one = RegExp(r'^/library/metadata/(\d+)$').firstMatch(p);
      if (one != null) {
        log.add(r);
        final id = one.group(1)!;
        if (songStatus != 200) return http.Response('', songStatus);
        if (gone.contains(id) || !albumOf.containsKey(id)) {
          return http.Response('', 404);
        }
        return jsonResponse(
          jsonEncode({
            'MediaContainer': {
              'size': 1,
              'Metadata': [song(id)],
            },
          }),
        );
      }
      final kids = RegExp(r'^/library/metadata/(\d+)/children$').firstMatch(p);
      if (kids != null) {
        log.add(r);
        final id = kids.group(1)!;
        if (childrenFailing.contains(id)) return http.Response('', 500);
        final f = File('test/fixtures/plex/children_$id.json');
        return f.existsSync()
            ? jsonResponse(f.readAsStringSync())
            : http.Response('', 404);
      }
      if (p == '/:/scrobble') {
        log.add(r);
        final k = r.url.queryParameters['key'];
        final code = scrobbleStatus[k] ?? 200;
        return http.Response('', code);
      }
    }
    return pms.handle(r);
  }

  PlexSource source({FakeSecretStore? secrets}) {
    final s = secrets ?? FakeSecretStore();
    s.data[PlexSource.tokenKey('acc1')] = 'server-token-home';
    return PlexSource(
      accountId: 'acc1',
      server: PlexServer.fromResource(resourceJson(homeResource))!,
      clientId: 'client-abc',
      client: MockClient(handle),
      secrets: s,
      deviceName: 'iPhone',
      platform: 'iOS',
    );
  }

  List<String> get paths => [for (final r in log) r.url.path];
}

void main() {
  setUp(PlexSource.resetStateForTests);
  tearDown(PlexSource.resetStateForTests);

  group('stream and download addresses', () {
    test('the original file, token in a header only', () async {
      final f = Pms();
      final s = f.source();
      await s.resolveSong('101');
      final stream = s.streamUri('101');
      expect(stream.host, homeLocal);
      expect(stream.path, '/library/parts/1010/1700000000/file.flac');
      expect(stream.hasQuery, isFalse);
      final dl = s.downloadUri('101');
      expect(dl.path, stream.path);
      expect(dl.queryParameters, {'download': '1'});
      for (final u in [stream, dl]) {
        expect(u.toString(), isNot(contains('server-token-home')));
      }
      expect(s.headers['X-Plex-Token'], 'server-token-home');
    });

    test('headers mpv accepts: no comma, no control character', () async {
      final f = Pms();
      final s = f.source();
      await s.prepare();
      for (final e in s.headers.entries) {
        expect(e.key, isNot(matches(RegExp('[\\r\\n,\\x00:]'))));
        expect(e.value, isNot(matches(RegExp('[\\r\\n,\\x00]'))));
      }
    });

    test('a song not resolved yet has no address (never a guess)', () async {
      final s = Pms().source();
      await s.prepare();
      expect(() => s.streamUri('101'), throwsStateError);
      expect(() => s.downloadUri('101'), throwsStateError);
    });

    test('several Parts: the first one is played and kept', () async {
      final f = Pms()..twoParts = true;
      final s = f.source();
      await s.resolveSong('101');
      expect(
        s.streamUri('101').path,
        '/library/parts/1010/1700000000/file.flac',
      );
    });

    test('a song without a file is refused like a missing one (404)', () async {
      final f = Pms()..noPart = {'101'};
      final s = f.source();
      await expectLater(
        s.resolveSong('101'),
        throwsA(
          isA<PlexException>().having((e) => e.statusCode, 'status', 404),
        ),
      );
    });
  });

  group('looking the Part up', () {
    test('one song: a single read of that song, cached', () async {
      final f = Pms();
      final s = f.source();
      await s.resolveSong('101');
      await s.resolveSong('101');
      expect(f.paths, ['/library/metadata/101']);
      expect(f.log.single.headers['X-Plex-Token'], 'server-token-home');
    });

    test(
      'a download run: the album is read once, its other songs cost nothing',
      () async {
        final f = Pms();
        final s = f.source();
        await s.resolveSong('101', batch: true);
        await s.resolveSong('102', batch: true);
        expect(f.paths, [
          '/library/metadata/101',
          '/library/metadata/11/children',
        ]);
        expect(
          s.downloadUri('102').path,
          '/library/parts/1020/1700000000/file.mp3',
        );
        // another album: its own two reads
        await s.resolveSong('121', batch: true);
        await s.resolveSong('122', batch: true);
        expect(f.paths.length, 4);
      },
    );

    test(
      'the album read failing is not fatal: songs are read one by one',
      () async {
        final f = Pms()..childrenFailing = {'11'};
        final s = f.source();
        await s.resolveSong('101', batch: true);
        await s.resolveSong('102', batch: true);
        expect(
          f.paths.where((p) => p == '/library/metadata/102'),
          hasLength(1),
        );
        expect(s.streamUri('102').path, contains('1020'));
      },
    );

    test(
      'a kept answer is forgotten after a while (the file may change)',
      () async {
        var now = DateTime(2026, 1, 1);
        final f = Pms();
        final s = PlexSource(
          accountId: 'acc1',
          server: PlexServer.fromResource(resourceJson(homeResource))!,
          clientId: 'c',
          client: MockClient(f.handle),
          secrets: FakeSecretStore()
            ..data[PlexSource.tokenKey('acc1')] = 'server-token-home',
          now: () => now,
        );
        await s.resolveSong('101');
        now = now.add(const Duration(hours: 2));
        await s.resolveSong('101');
        expect(f.paths, ['/library/metadata/101', '/library/metadata/101']);
      },
    );

    test(
      '404 is a refusal of this song; 401 asks for a new code; 500 is neither',
      () async {
        final f = Pms()..gone = {'101'};
        final s = f.source();
        await expectLater(
          s.resolveSong('101'),
          throwsA(isA<PlexException>().having((e) => e.statusCode, 's', 404)),
        );
        f.songStatus = 401;
        await expectLater(
          s.resolveSong('102'),
          throwsA(
            isA<PlexException>().having((e) => e.tokenRefused, 't', isTrue),
          ),
        );
        f.songStatus = 500;
        await expectLater(
          s.resolveSong('122'),
          throwsA(
            isA<PlexException>()
                .having((e) => e.statusCode, 's', 500)
                .having((e) => e.tokenRefused, 't', isFalse),
          ),
        );
      },
    );

    test('errors never carry the token', () async {
      final f = Pms()..songStatus = 500;
      final s = f.source();
      try {
        await s.resolveSong('101');
      } on PlexException catch (e) {
        expect(e.toString(), isNot(contains('server-token')));
      }
    });
  });

  group('listens (scrobble)', () {
    test('GET /:/scrobble with the song and the library identifier', () async {
      final f = Pms();
      final s = f.source();
      await s.scrobble('101', DateTime(2026, 5, 1));
      final r = f.log.single;
      expect(r.method, 'GET');
      expect(r.url.path, '/:/scrobble');
      expect(r.url.queryParameters, {
        'key': '101',
        'identifier': 'com.plexapp.plugins.library',
      });
      expect(r.headers['X-Plex-Token'], 'server-token-home');
      expect(r.url.toString(), isNot(contains('server-token-home')));
      // Plex has no date: the one given is not sent
      expect(r.url.toString(), isNot(contains('2026')));
    });

    test(
      '404 (the song is gone) is refused for good; other failures retry',
      () async {
        final f = Pms()..scrobbleStatus = {'1': 404, '2': 500, '3': 401};
        final s = f.source();
        Future<Object?> err(String id) async {
          try {
            await s.scrobble(id, DateTime(2026));
          } on Object catch (e) {
            return e;
          }
          return null;
        }

        expect(scrobbleRefused((await err('1'))!), isTrue);
        expect(scrobbleRefused((await err('2'))!), isFalse);
        final unauthorized = (await err('3'))! as PlexException;
        expect(unauthorized.tokenRefused, isTrue);
        expect(scrobbleRefused(unauthorized), isFalse);
      },
    );

    test(
      'a network failure is a SourceNetworkException (retried later)',
      () async {
        final f = Pms();
        final s = f.source();
        await s.prepare();
        f.pms.down = {homeLocal, homeRemote};
        Object? e;
        try {
          await s.scrobble('101', DateTime(2026));
        } on Object catch (x) {
          e = x;
        }
        expect(e, isA<SourceNetworkException>());
        expect(scrobbleRefused(e!), isFalse);
      },
    );
  });
}
