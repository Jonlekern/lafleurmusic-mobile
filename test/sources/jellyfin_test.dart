import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lafleurmusic/app_version.dart';
import 'package:lafleurmusic/library/db.dart';
import 'package:lafleurmusic/library/models.dart' show unknownAlbumName;
import 'package:lafleurmusic/library/sync.dart';
import 'package:lafleurmusic/player/media_resolver.dart' show remoteCover;
import 'package:lafleurmusic/sources/accounts.dart';
import 'package:lafleurmusic/sources/jellyfin.dart';
import 'package:lafleurmusic/sources/remote_key.dart';
import 'package:lafleurmusic/sources/source.dart';

import 'fake_secret_store.dart';

const _info =
    '{"LocalAddress":"http://x:8096","ServerName":"home","Version":"10.9.11",'
    '"ProductName":"Jellyfin Server","OperatingSystem":"Linux","Id":"abc","StartupWizardCompleted":true}';
const _auth =
    '{"User":{"Name":"max","Id":"user-1"},"AccessToken":"tok-secret-1","ServerId":"abc"}';

http.Response json(String body, [int code = 200]) =>
    http.Response(body, code, headers: {'content-type': 'application/json'});

final base = Uri.parse('http://jf.example:8096');

JellyfinSource source(
  MockClient c, {
  FakeSecretStore? secrets,
  Map<String, String> headers = const {},
  String password = 'pw-secret',
}) => JellyfinSource(
  accountId: 'acc1',
  base: base,
  user: 'max',
  password: password,
  headers: headers,
  client: c,
  secrets: secrets,
  deviceName: 'iPhone',
);

/// A well-behaved server: public info, then auth with the right password.
MockClient server({
  List<http.Request>? log,
  String pw = 'pw-secret',
  String token = 'tok-secret-1',
}) => MockClient((r) => serve(r, log: log, pw: pw, token: token));

Future<http.Response> serve(
  http.Request r, {
  List<http.Request>? log,
  String pw = 'pw-secret',
  String token = 'tok-secret-1',
}) async {
  log?.add(r);
  if (r.url.path == '/System/Info/Public') return json(_info);
  if (r.url.path == '/Users/AuthenticateByName') {
    final b = jsonDecode(r.body) as Map;
    return b['Pw'] == pw
        ? json(_auth.replaceAll('tok-secret-1', token))
        : http.Response('', 401);
  }
  return http.Response('', 404);
}

void main() {
  libraryTests();
  group('JellyfinSource.test', () {
    test('ok: public info, then sign-in, token kept in the store', () async {
      final log = <http.Request>[];
      final secrets = FakeSecretStore();
      final s = source(server(log: log), secrets: secrets);
      expect(await s.test(), TestResult.ok);
      expect(log.map((r) => '${r.method} ${r.url.path}'), [
        'GET /System/Info/Public',
        'POST /Users/AuthenticateByName',
      ]);
      expect(jsonDecode(log[1].body), {'Username': 'max', 'Pw': 'pw-secret'});
      expect(secrets.data[JellyfinSource.tokenKey('acc1')], 'tok-secret-1');
      expect(secrets.data[JellyfinSource.userIdKey('acc1')], 'user-1');
      // the password is not written again by the source
      expect(secrets.data.values, isNot(contains('pw-secret')));
      expect(s.headers['Authorization'], contains('Token="tok-secret-1"'));
    });

    test('Authorization header format, sign-in without a token', () async {
      final log = <http.Request>[];
      await source(server(log: log)).test();
      final h = log.last.headers['Authorization']!;
      expect(h, startsWith('MediaBrowser Client="LAFLEURMUSIC", '));
      expect(h, contains('Device="iPhone"'));
      expect(h, matches(RegExp(r'DeviceId="[0-9a-f]{32}"')));
      expect(h, matches(RegExp(r'Version="\d+\.\d+\.\d+"')));
      expect(h, isNot(contains('Token=')));
    });

    test('device id is stable for an account, differs between accounts', () {
      String id(String acc) => JellyfinSource(
        accountId: acc,
        base: base,
        user: 'u',
        password: 'p',
        client: server(),
      ).headers['Authorization']!;
      expect(id('a'), id('a'));
      expect(id('a'), isNot(id('b')));
    });

    test('custom headers go with every request, sign-in included', () async {
      final log = <http.Request>[];
      await source(
        server(log: log),
        headers: {'X-Proxy-Key': 'k1', 'CF-Access-Client-Id': 'c1'},
      ).test();
      expect(log, hasLength(2));
      for (final r in log) {
        expect(r.headers['X-Proxy-Key'], 'k1');
        expect(r.headers['CF-Access-Client-Id'], 'c1');
      }
    });

    test('a proxy Authorization header is kept; ours moves to X-Emby-Authorization', () async {
      final log = <http.Request>[];
      await source(
        server(log: log),
        headers: {'authorization': 'Basic abc'},
      ).test();
      for (final r in log) {
        expect(r.headers['authorization'], 'Basic abc');
        expect(r.headers['X-Emby-Authorization'], startsWith('MediaBrowser '));
      }
    });

    test('wrong password: 401 on sign-in, nothing stored', () async {
      final secrets = FakeSecretStore();
      final s = source(server(pw: 'other'), secrets: secrets);
      expect(await s.test(), TestResult.wrongPassword);
      expect(secrets.data, isEmpty);
    });

    test('proxy 403 without the header: headerRefused', () async {
      final c = MockClient((r) async => http.Response('<html>no</html>', 403));
      expect(await source(c).test(), TestResult.headerRefused);
      final c2 = MockClient((r) async => http.Response('', 401));
      expect(await source(c2).test(), TestResult.headerRefused);
    });

    test(
      'a proxy refusing the sign-in itself (403) is headerRefused',
      () async {
        final c = MockClient(
          (r) async => r.url.path == '/System/Info/Public'
              ? json(_info)
              : http.Response('', 403),
        );
        expect(await source(c).test(), TestResult.headerRefused);
      },
    );

    test('redirect to another host: headerRefused', () async {
      final c = MockClient(
        (r) async => http.Response(
          '',
          302,
          headers: {'location': 'https://login.other.example/'},
        ),
      );
      expect(await source(c).test(), TestResult.headerRefused);
    });

    test('not a Jellyfin server', () async {
      expect(
        await source(
          MockClient((r) async => http.Response('<html>hi</html>', 200)),
        ).test(),
        TestResult.notJellyfin,
      );
      expect(
        await source(
          MockClient((r) async => json('{"ProductName":"Something Else"}')),
        ).test(),
        TestResult.notJellyfin,
      );
      expect(
        await source(MockClient((r) async => http.Response('', 404))).test(),
        TestResult.notJellyfin,
      );
    });

    test('unreachable, certificate, timeout', () async {
      expect(
        await source(
          MockClient((r) async => throw const SocketException('down')),
        ).test(),
        TestResult.unreachable,
      );
      expect(
        await source(MockClient((r) async => throw http.ClientException('x')))
            .test(),
        TestResult.unreachable,
      );
      expect(
        await source(
          MockClient((r) async => throw const HandshakeException('bad cert')),
        ).test(),
        TestResult.certificateRejected,
      );
      final s = JellyfinSource(
        accountId: 'a',
        base: base,
        user: 'u',
        password: 'p',
        client: MockClient((r) => Completer<http.Response>().future),
        timeout: const Duration(milliseconds: 50),
      );
      expect(await s.test(), TestResult.unreachable);
    });

    test('http → https on the same host is followed and reported', () async {
      final c = MockClient((r) async {
        if (r.url.scheme == 'http') {
          return http.Response(
            '',
            301,
            headers: {'location': 'https://jf.example:8096${r.url.path}'},
          );
        }
        return serve(r);
      });
      final s = source(c);
      expect(await s.test(), TestResult.ok);
      expect(s.redirectedBase, Uri.parse('https://jf.example:8096'));
    });

    test('base path (reverse proxy under /jellyfin) is kept', () async {
      final log = <http.Request>[];
      final s = JellyfinSource(
        accountId: 'a',
        base: Uri.parse('https://x.example/jellyfin/'),
        user: 'max',
        password: 'pw-secret',
        client: MockClient((r) async {
          log.add(r);
          return r.url.path.endsWith('Info/Public') ? json(_info) : json(_auth);
        }),
      );
      expect(await s.test(), TestResult.ok);
      expect(log.first.url.path, '/jellyfin/System/Info/Public');
      expect(log.last.url.path, '/jellyfin/Users/AuthenticateByName');
    });
  });

  group('token and secrets', () {
    test('token and password never reach an exception or its text', () async {
      final c = MockClient(
        (r) async => throw http.ClientException('boom', r.url),
      );
      final s = source(c);
      Object? err;
      try {
        await s.authedGet('/Anything');
      } catch (e) {
        err = e;
      }
      expect(err, isA<SourceNetworkException>());
      for (final secret in ['pw-secret', 'tok-secret-1', 'jf.example']) {
        expect('$err', isNot(contains(secret)));
      }
    });

    test('no log line carries them (debugPrint, print)', () async {
      final lines = <String>[];
      await runZoned(
        () async => source(server()).test(),
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) => lines.add(line),
        ),
      );
      expect(lines.join(), isNot(contains('tok-secret-1')));
      expect(lines.join(), isNot(contains('pw-secret')));
    });

    test(
      'a source built later reuses the stored token without signing in',
      () async {
        final secrets = FakeSecretStore();
        await source(server(), secrets: secrets).test();
        final log = <http.Request>[];
        final later = source(
          MockClient((r) async {
            log.add(r);
            return json('{}');
          }),
          secrets: secrets,
        );
        final res = await later.authedGet('/Items');
        expect(res.statusCode, 200);
        expect(log, hasLength(1));
        expect(
          log.single.headers['Authorization'],
          contains('Token="tok-secret-1"'),
        );
      },
    );

    test('Review Focus 1: revoked token, 401, one re-sign-in with the stored password, then retried', () async {
      final secrets = FakeSecretStore()
        ..data[JellyfinSource.tokenKey('acc1')] = 'old-token'
        ..data[JellyfinSource.userIdKey('acc1')] = 'user-1';
      final log = <http.Request>[];
      final c = MockClient((r) async {
        log.add(r);
        if (r.url.path == '/Users/AuthenticateByName') {
          return json(_auth.replaceAll('tok-secret-1', 'new-token'));
        }
        final t = r.headers['Authorization'] ?? '';
        return t.contains('Token="new-token"')
            ? json('{"ok":true}')
            : http.Response('', 401);
      });
      final s = source(c, secrets: secrets);
      final res = await s.authedGet('/Items');
      expect(res.statusCode, 200);
      expect(log.map((r) => '${r.method} ${r.url.path}'), [
        'GET /Items',
        'POST /Users/AuthenticateByName',
        'GET /Items',
      ]);
      expect(secrets.data[JellyfinSource.tokenKey('acc1')], 'new-token');
    });

    test('Review Focus 1: 401 again after re-sign-in (password changed): wrongPassword, no loop', () async {
      final secrets = FakeSecretStore()
        ..data[JellyfinSource.tokenKey('acc1')] = 'old-token';
      final log = <http.Request>[];
      final c = MockClient((r) async {
        log.add(r);
        return http.Response('', 401);
      });
      final s = source(c, secrets: secrets);
      await expectLater(
        s.authedGet('/Items'),
        throwsA(
          isA<JellyfinException>().having(
            (e) => e.wrongPassword,
            'wrong',
            true,
          ),
        ),
      );
      // GET, one sign-in, nothing more
      expect(
        log.where((r) => r.url.path == '/Users/AuthenticateByName'),
        hasLength(1),
      );
      expect(log, hasLength(2));
      expect(
        secrets.data.containsKey(JellyfinSource.tokenKey('acc1')),
        isFalse,
      );
    });

    test('simultaneous 401s share one re-sign-in', () async {
      final secrets = FakeSecretStore()
        ..data[JellyfinSource.tokenKey('acc1')] = 'old-token';
      var signIns = 0;
      final c = MockClient((r) async {
        if (r.url.path == '/Users/AuthenticateByName') {
          signIns++;
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return json(_auth.replaceAll('tok-secret-1', 'new-token'));
        }
        return (r.headers['Authorization'] ?? '').contains('new-token')
            ? json('{}')
            : http.Response('', 401);
      });
      final s = source(c, secrets: secrets);
      final rs = await Future.wait([
        for (var i = 0; i < 4; i++) s.authedGet('/Items'),
      ]);
      expect(rs.map((r) => r.statusCode), everyElement(200));
      expect(signIns, 1);
    });

    test('custom headers go with the authenticated requests too', () async {
      final log = <http.Request>[];
      final s = source(
        MockClient((r) async {
          log.add(r);
          return r.url.path == '/Users/AuthenticateByName'
              ? json(_auth)
              : json('{}');
        }),
        headers: {'X-Proxy-Key': 'k1'},
      );
      await s.authedGet('/Items');
      expect(log, hasLength(2));
      expect(log.map((r) => r.headers['X-Proxy-Key']), everyElement('k1'));
    });
  });

  group('remote keys', () {
    test('both schemes round trip', () {
      expect(remoteKey(AccountType.jellyfin, 'a1', 's9'), 'jellyfin://a1/s9');
      expect(remoteKey(AccountType.subsonic, 'a1', 's9'), 'subsonic://a1/s9');
      expect(parseRemoteKey('jellyfin://a1/s9'), ('a1', 's9'));
      expect(parseRemoteKey('subsonic://a1/s9'), ('a1', 's9'));
      expect(parseRemoteKey('jellyfin://a1/'), isNull);
      expect(parseRemoteKey('/music/a.flac'), isNull);
      expect(isRemotePath('jellyfin://a/b'), isTrue);
      expect(isRemotePath('subsonic://a/b'), isTrue);
      expect(isRemotePath('/x/y'), isFalse);
    });

    test('an id with slashes is kept whole', () {
      expect(parseRemoteKey('jellyfin://a1/x/y'), ('a1', 'x/y'));
    });

    test('LIKE condition covers both', () {
      expect(sqlIsRemote('r.path'), contains("'subsonic://%'"));
      expect(sqlIsRemote('r.path'), contains("'jellyfin://%'"));
    });
  });

  test('accounts: the token is erased with the account', () async {
    final secrets = FakeSecretStore();
    final db = LibraryDb(NativeDatabase.memory());
    final accounts = Accounts(db, secrets);
    final a = await accounts.add(
      type: AccountType.jellyfin,
      name: 'JF',
      base: base,
      user: 'max',
      password: 'pw-secret',
    );
    secrets.data[JellyfinSource.tokenKey(a.id)] = 't';
    secrets.data[JellyfinSource.userIdKey(a.id)] = 'u';
    final src = await accounts.source(a.id, client: server());
    expect(src, isA<JellyfinSource>());
    await accounts.remove(a.id, root: null);
    expect(secrets.data, isEmpty);
    await db.close();
  });

  test('appVersion equals the version in pubspec.yaml', () {
    final m = RegExp(
      r'^version:\s*([0-9.]+)',
      multiLine: true,
    ).firstMatch(File('pubspec.yaml').readAsStringSync());
    expect(appVersion, m![1]);
    expect(JellyfinSource.clientVersion, appVersion);
  });

  test('a source closed during sign-in stores no token', () async {
    final secrets = FakeSecretStore();
    late JellyfinSource s;
    s = source(
      MockClient((r) async {
        if (r.url.path.endsWith('Info/Public')) return json(_info);
        s.close(); // the account is removed while the answer is on its way
        return json(_auth);
      }),
      secrets: secrets,
    );
    expect(await s.test(), isNot(TestResult.ok));
    expect(secrets.data, isEmpty);
    expect(s.headers['Authorization'], isNot(contains('Token=')));
  });

  test(
    'a changed password, address or user clears the Jellyfin token',
    () async {
      final secrets = FakeSecretStore();
      final db = LibraryDb(NativeDatabase.memory());
      final accounts = Accounts(db, secrets);
      final a = await accounts.add(
        type: AccountType.jellyfin,
        name: 'JF',
        base: base,
        user: 'max',
        password: 'pw',
      );
      void seed() {
        secrets.data[JellyfinSource.tokenKey(a.id)] = 't';
        secrets.data[JellyfinSource.userIdKey(a.id)] = 'u';
      }

      Account with_({Uri? b, String? user}) => Account(
        id: a.id,
        type: a.type,
        name: a.name,
        base: b ?? a.base,
        user: user ?? a.user,
        order: a.order,
      );
      bool kept() => secrets.data.containsKey(JellyfinSource.tokenKey(a.id));

      seed();
      await accounts.update(with_()); // nothing changed
      expect(kept(), isTrue);
      await accounts.update(with_(), password: 'new');
      expect(kept(), isFalse);
      seed();
      await accounts.update(with_(b: Uri.parse('https://other.example')));
      expect(kept(), isFalse);
      seed();
      await accounts.update(with_(user: 'other'));
      expect(kept(), isFalse);
      expect(secrets.data.containsKey(JellyfinSource.userIdKey(a.id)), isFalse);
      await db.close();
    },
  );

  test('sync keys a Jellyfin account\'s tracks with jellyfin://', () async {
    final db = LibraryDb(NativeDatabase.memory());
    await LibrarySync(db).run(_Lib(AccountType.jellyfin));
    await LibrarySync(db).run(_Lib(AccountType.subsonic, id: 'old'));
    expect(await db.trackByPath('jellyfin://acc1/s1'), isNotNull);
    expect(await db.trackByPath('subsonic://old/s1'), isNotNull);
    await db.close();
  });
}

class _Lib implements MusicSource, TypedSource {
  _Lib(this.accountType, {String id = 'acc1'}) : accountId = id;
  @override
  final AccountType accountType;
  @override
  final String accountId;

  @override
  Stream<List<SourceAlbum>> albums({int pageSize = 500}) async* {
    yield [const SourceAlbum(id: 'al', name: 'A', artist: 'X', songCount: 1)];
  }

  @override
  Future<List<SourceSong>> albumSongs(String albumId) async => [
    const SourceSong(
      id: 's1',
      title: 'T',
      artist: 'X',
      album: 'A',
      albumArtist: 'X',
    ),
  ];

  @override
  Future<List<SourcePlaylist>> playlists() async => const [];

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

String fx(String name) =>
    File('test/fixtures/jellyfin/$name').readAsStringSync();

/// A signed-in server serving the recorded library answers. [loose]: also answers the
/// `Audio` scan with songs outside any album.
MockClient library({
  List<http.Request>? log,
  bool albums = true,
  bool views = true,
  Set<String> brokenPlaylists = const {'pl2'},
}) => MockClient((r) async {
  log?.add(r);
  final p = r.url.path;
  final q = r.url.queryParameters;
  if (p == '/Users/AuthenticateByName') return json(_auth);
  if (r.headers['Authorization'] == null ||
      !r.headers['Authorization']!.contains('Token="tok-secret-1"')) {
    return http.Response('', 401);
  }
  String page(String name) {
    final d = jsonDecode(fx(name)) as Map;
    final start = int.parse(q['StartIndex'] ?? '0');
    final all = d['Items'] as List;
    return jsonEncode({
      'Items': all.skip(start).take(int.parse(q['Limit'] ?? '100')).toList(),
      'TotalRecordCount': all.length,
      'StartIndex': start,
    });
  }

  if (p == '/Users/user-1/Views') {
    return json(views ? fx('views.json') : '{"Items":[]}');
  }
  if (p == '/Users/user-1/Items' && q['Ids'] != null) {
    final ids = q['Ids']!.split(',');
    final d = jsonDecode(fx('audio_all.json')) as Map;
    final items = [
      for (final i in d['Items'] as List)
        if (ids.contains((i as Map)['Id'])) i,
    ];
    return json(jsonEncode({'Items': items, 'TotalRecordCount': items.length}));
  }
  if (p == '/Users/user-1/Items') {
    switch ((q['IncludeItemTypes'], q['ParentId'])) {
      case ('MusicAlbum', 'v-music1'):
        return json(
          albums ? page('albums_v1.json') : '{"Items":[],"TotalRecordCount":0}',
        );
      case ('MusicAlbum', 'v-music2'):
        return json(
          albums ? page('albums_v2.json') : '{"Items":[],"TotalRecordCount":0}',
        );
      case ('Audio', 'v-music1'):
        // a lean scan: the server only sends the heavy fields when asked
        final d = jsonDecode(page('audio_all.json')) as Map;
        if (!(q['Fields'] ?? '').contains('MediaSources')) {
          for (final i in d['Items'] as List) {
            (i as Map)
              ..remove('MediaSources')
              ..remove('RunTimeTicks')
              ..remove('ImageTags')
              ..remove('Genres');
          }
        }
        return json(jsonEncode(d));
      case ('Audio', 'v-music2'):
        return json('{"Items":[],"TotalRecordCount":0}');
      case ('Audio', 'al1'):
        return json(page('album_al1_songs.json'));
      case ('Audio', 'al2' || 'al3'):
        return json('{"Items":[],"TotalRecordCount":0}');
      case ('Playlist', null):
        return json(page('playlists.json'));
    }
  }
  if (p == '/Playlists/pl1/Items') return json(page('playlist_pl1.json'));
  if (p == '/Playlists/pl2/Items' && brokenPlaylists.contains('pl2')) {
    return http.Response('', 500);
  }
  return http.Response('', 404);
});

void libraryTests() {
  group('JellyfinSource library', () {
    test('albums: every music view, an album in two views once, requests as specified', () async {
      final log = <http.Request>[];
      final s = source(library(log: log), secrets: FakeSecretStore());
      final pages = await s.albums().toList();
      final all = pages.expand((p) => p).toList();
      expect(all.map((a) => a.id), [
        'al1',
        'al2',
        'al3',
        'loose:Solo',
        'loose:',
      ]);
      final a1 = all.first;
      expect(
        (a1.name, a1.artist, a1.coverId, a1.songCount),
        ('First Light', 'Nova', 'al1', 2),
      );
      expect(all[1].artist, 'Echo'); // from AlbumArtists
      expect(all[1].coverId, isNull); // no Primary image
      final req = log
          .where(
            (r) => r.url.queryParameters['IncludeItemTypes'] == 'MusicAlbum',
          )
          .toList();
      expect(req.map((r) => r.url.queryParameters['ParentId']), [
        'v-music1',
        'v-music2',
      ]);
      final q = req.first.url.queryParameters;
      expect(q['Recursive'], 'true');
      expect(q['Limit'], '500');
      expect(q['StartIndex'], '0');
      expect(req.first.url.path, '/Users/user-1/Items');
      expect(
        log.any((r) => r.url.queryParameters['ParentId'] == 'v-films'),
        isFalse,
      );
    });

    test('albums: pages of 1 are followed until the total', () async {
      final log = <http.Request>[];
      final pages = await source(
        library(log: log),
        secrets: FakeSecretStore(),
      ).albums(pageSize: 1).toList();
      expect(pages.expand((p) => p).map((a) => a.id), [
        'al1',
        'al2',
        'al3',
        'loose:Solo',
        'loose:',
      ]);
      final starts = log
          .where(
            (r) =>
                r.url.queryParameters['ParentId'] == 'v-music1' &&
                r.url.queryParameters['IncludeItemTypes'] == 'MusicAlbum',
          )
          .map((r) => r.url.queryParameters['StartIndex']);
      expect(starts, ['0', '1']);
    });

    test(
      'albums: a server ignoring the offset fails instead of looping',
      () async {
        final c = MockClient((r) async {
          if (r.url.path == '/Users/AuthenticateByName') return json(_auth);
          if (r.url.path.endsWith('/Views')) return json(fx('views.json'));
          return json(
            jsonEncode({
              'Items': [
                {'Id': 'same', 'Name': 'x'},
              ],
              'TotalRecordCount': 99,
            }),
          );
        });
        await expectLater(
          source(c).albums().toList(),
          throwsA(isA<JellyfinException>()),
        );
      },
    );

    test('no music view: nothing, no error', () async {
      final r = await source(library(views: false)).albums().toList();
      expect(r.expand((p) => p), isEmpty);
    });

    test('server error is thrown, not swallowed', () async {
      final c = MockClient((r) async {
        if (r.url.path == '/Users/AuthenticateByName') return json(_auth);
        return http.Response('', 500);
      });
      await expectLater(
        source(c).albums().toList(),
        throwsA(
          isA<JellyfinException>().having((e) => e.statusCode, 'status', 500),
        ),
      );
    });

    test('albumSongs: field mapping', () async {
      final log = <http.Request>[];
      final s = source(library(log: log));
      final songs = await s.albumSongs('al1');
      final q = log.last.url.queryParameters;
      expect(q['ParentId'], 'al1');
      expect(q['IncludeItemTypes'], 'Audio');
      expect(q['SortBy'], 'ParentIndexNumber,IndexNumber');
      final a = songs[0];
      expect(a.id, 's1');
      expect(a.title, 'Opening');
      expect(a.artist, 'Nova, Guest');
      expect(a.album, 'First Light');
      expect(a.albumArtist, 'Nova');
      expect((a.track, a.disc), (1, 1));
      expect(a.durationMs, 180500); // 1805000000 ticks of 100 ns
      expect(a.size, 31457280);
      expect(a.suffix, 'flac');
      expect(a.replayGainTrack, -7.25);
      expect(a.replayGainAlbum, isNull);
      expect(a.playCount, 4);
      expect(a.genre, 'Pop, Indie');
      expect(a.coverId, 'al1'); // the album's picture
      final b = songs[1];
      expect(b.coverId, 's2'); // its own picture
      expect(b.suffix, 'm4a'); // container list: the file's extension
      expect(b.replayGainTrack, isNull);
      expect(b.playCount, 0);
    });

    test(
      'songs outside any album are kept under "Album inconnu" of their artist',
      () async {
        final s = source(library());
        final albums = (await s.albums().toList()).expand((p) => p).toList();
        final solo = albums.firstWhere((a) => a.id == 'loose:Solo');
        expect(
          (solo.name, solo.artist, solo.songCount),
          (unknownAlbumName, 'Solo', 2),
        );
        final songs = await s.albumSongs('loose:Solo');
        expect(songs.map((e) => e.id), ['s9', 's10']);
        expect(
          songs.every(
            (e) => e.album == unknownAlbumName && e.albumArtist == 'Solo',
          ),
          isTrue,
        );
        expect(songs[0].durationMs, 60000);
        expect(songs[0].coverId, 's9');
        expect(await s.albumSongs('loose:'), hasLength(1)); // no artist at all
        // a song in an album is not listed twice
        expect(songs.any((e) => e.id == 's1'), isFalse);
      },
    );

    test(
      'loose songs are readable without having listed the albums first',
      () async {
        final songs = await source(library()).albumSongs('loose:Solo');
        expect(songs.map((e) => e.id), ['s9', 's10']);
      },
    );

    test('playlists: songs in order, a repeated song twice, an unreadable one null', () async {
      final log = <http.Request>[];
      final lists = await source(library(log: log)).playlists();
      expect(lists.map((l) => l.name), ['Road', 'Broken']);
      expect(lists[0].songIds, ['s1', 's2', 's1']);
      expect(lists[1].songIds, isNull);
      expect(
        log
            .firstWhere((r) => r.url.path == '/Users/user-1/Items')
            .url
            .queryParameters['IncludeItemTypes'],
        'Playlist',
      );
    });

    test('coverUri has no credentials in it', () {
      final u = source(library()).coverUri('al1', 300);
      expect(u.path, '/Items/al1/Images/Primary');
      expect(u.queryParameters, {'maxWidth': '300', 'quality': '90'});
      expect('$u', isNot(contains('tok-secret')));
    });

    test(
      'cover bytes are fetched with the account headers and the token',
      () async {
        final log = <http.Request>[];
        final inner = library(log: log);
        final c = MockClient((r) async {
          if (r.url.path == '/Items/al1/Images/Primary') {
            log.add(r);
            if (r.headers['X-Proxy-Key'] != 'k1' ||
                !(r.headers['Authorization'] ?? '').contains(
                  'Token="tok-secret-1"',
                )) {
              return http.Response('', 401);
            }
            return http.Response.bytes(
              [1, 2, 3],
              200,
              headers: {'content-type': 'image/jpeg'},
            );
          }
          return inner.send(r).then(http.Response.fromStream);
        });
        // a fresh source whose token only sits in the store (app restart)
        final secrets = FakeSecretStore()
          ..data[JellyfinSource.tokenKey('acc1')] = 'tok-secret-1'
          ..data[JellyfinSource.userIdKey('acc1')] = 'user-1';
        final s = source(c, secrets: secrets, headers: {'X-Proxy-Key': 'k1'});
        expect(await remoteCover(s, 'al1', 300), [1, 2, 3]);
      },
    );

    test('a revoked token is renewed once when fetching a cover', () async {
      var calls = 0;
      final c = MockClient((r) async {
        if (r.url.path == '/Users/AuthenticateByName') return json(_auth);
        calls++;
        return (r.headers['Authorization'] ?? '').contains(
              'Token="tok-secret-1"',
            )
            ? http.Response.bytes(
                [9],
                200,
                headers: {'content-type': 'image/png'},
              )
            : http.Response('', 401);
      });
      final secrets = FakeSecretStore()
        ..data[JellyfinSource.tokenKey('acc1')] = 'old'
        ..data[JellyfinSource.userIdKey('acc1')] = 'user-1';
      expect(await remoteCover(source(c, secrets: secrets), 'x', 64), [9]);
      expect(calls, 2);
    });

    test(
      'the loose-song scan is lean; the loose ones are then fetched by Ids',
      () async {
        final log = <http.Request>[];
        final s = source(library(log: log));
        await s.albums().toList();
        final scan = log.where(
          (r) =>
              r.url.queryParameters['IncludeItemTypes'] == 'Audio' &&
              r.url.queryParameters['ParentId'] != null,
        );
        expect(scan, isNotEmpty);
        for (final r in scan) {
          expect(
            r.url.queryParameters['Fields'] ?? '',
            isNot(contains('MediaSources')),
          );
          expect(
            r.url.queryParameters['Fields'] ?? '',
            isNot(contains('Genres')),
          );
        }
        final byIds = log
            .where((r) => r.url.queryParameters['Ids'] != null)
            .toList();
        expect(byIds, hasLength(1));
        expect(byIds.single.url.queryParameters['Ids']!.split(','), [
          's9',
          's10',
          's11',
        ]);
        expect(
          byIds.single.url.queryParameters['Fields'],
          contains('MediaSources'),
        );
        final songs = await s.albumSongs('loose:Solo');
        expect(
          (songs[0].size, songs[0].suffix, songs[0].durationMs),
          (123, 'mp3', 60000),
        );
      },
    );

    test('many loose songs are fetched by Ids in batches', () async {
      final log = <http.Request>[];
      final c = MockClient((r) async {
        log.add(r);
        final q = r.url.queryParameters;
        if (r.url.path == '/Users/AuthenticateByName') return json(_auth);
        if (r.url.path.endsWith('/Views')) return json(fx('views.json'));
        if (q['Ids'] != null) {
          return json(
            jsonEncode({
              'Items': [
                for (final id in q['Ids']!.split(',')) {'Id': id, 'Name': id},
              ],
              'TotalRecordCount': q['Ids']!.split(',').length,
            }),
          );
        }
        if (q['IncludeItemTypes'] == 'Audio' && q['ParentId'] == 'v-music1') {
          final start = int.parse(q['StartIndex']!);
          final n = (250 - start).clamp(0, int.parse(q['Limit']!));
          return json(
            jsonEncode({
              'Items': [
                for (var i = start; i < start + n; i++)
                  {'Id': 'x$i', 'Name': 'n$i'},
              ],
              'TotalRecordCount': 250,
            }),
          );
        }
        return json('{"Items":[],"TotalRecordCount":0}');
      });
      final albums = (await source(
        c,
      ).albums().toList()).expand((p) => p).toList();
      expect(albums.single.songCount, 250);
      final batches = log
          .where((r) => r.url.queryParameters['Ids'] != null)
          .toList();
      expect(batches.length, greaterThan(1));
      expect(
        batches.every(
          (r) => r.url.queryParameters['Ids']!.split(',').length <= 100,
        ),
        isTrue,
      );
    });

    test('a cover answered 401 signs in again once and succeeds; a second 401 gives up', () async {
      var signIns = 0, gets = 0;
      final c = MockClient((r) async {
        if (r.url.path == '/Users/AuthenticateByName') {
          signIns++;
          return json(_auth);
        }
        gets++;
        return http.Response('', 401);
      });
      final secrets = FakeSecretStore()
        ..data[JellyfinSource.tokenKey('acc1')] = 'old'
        ..data[JellyfinSource.userIdKey('acc1')] = 'user-1';
      await expectLater(
        remoteCover(source(c, secrets: secrets), 'x', 64),
        throwsA(isA<SourceNetworkException>()),
      );
      expect((signIns, gets), (1, 2)); // one re-sign-in, no loop
    });

    test('a missing cover is null', () async {
      final c = MockClient(
        (r) async => r.url.path == '/Users/AuthenticateByName'
            ? json(_auth)
            : http.Response('', 404),
      );
      expect(await remoteCover(source(c), 'x', 64), isNull);
    });

    test('sync: jellyfin:// keys, loose songs stored, playlists, a second sync removes nothing', () async {
      final db = LibraryDb(NativeDatabase.memory());
      addTearDown(db.close);
      final s = source(library(), secrets: FakeSecretStore());
      final r = await LibrarySync(db).run(s);
      expect(r.complete, isTrue);
      expect(r.added, 5); // s1 s2 (al1) + s9 s10 + s11 (loose)
      final t = await db.trackByPath('jellyfin://acc1/s9');
      expect(t!.album, unknownAlbumName);
      expect(t.artist, 'Solo');
      expect((await db.trackByPath('jellyfin://acc1/s1'))!.replayGain, -7.25);
      final r2 = await LibrarySync(db)
          .run(source(library(), secrets: FakeSecretStore()));
      expect((r2.added, r2.updated, r2.removed, r2.complete), (0, 0, 0, true));
    });

    test('R3: a server answering 0 albums deletes nothing', () async {
      final db = LibraryDb(NativeDatabase.memory());
      addTearDown(db.close);
      await LibrarySync(db).run(source(library(), secrets: FakeSecretStore()));
      Future<int> n() async => (await db.select(db.tracks).get()).length;
      final before = await n();
      expect(before, 5);
      // no music view / no album / nothing at all
      for (final c in [
        library(views: false),
        MockClient(
          (r) async => r.url.path == '/Users/AuthenticateByName'
              ? json(_auth)
              : json('{"Items":[],"TotalRecordCount":0}'),
        ),
      ]) {
        final r = await LibrarySync(db)
            .run(source(c, secrets: FakeSecretStore()));
        expect((r.complete, r.removed), (false, 0));
        expect(await n(), before);
      }
    });

    test('an error mid-listing deletes nothing', () async {
      final db = LibraryDb(NativeDatabase.memory());
      addTearDown(db.close);
      await LibrarySync(db).run(source(library(), secrets: FakeSecretStore()));
      final c = MockClient((r) async {
        if (r.url.path == '/Users/AuthenticateByName') return json(_auth);
        if (r.url.path.endsWith('/Views')) return json(fx('views.json'));
        return http.Response('', 503);
      });
      final r = await LibrarySync(db)
          .run(source(c, secrets: FakeSecretStore()));
      expect((r.complete, r.removed), (false, 0));
      expect((await db.select(db.tracks).get()), hasLength(5));
    });
  });
}
