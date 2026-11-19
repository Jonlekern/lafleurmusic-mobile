import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lafleurmusic/app_version.dart';
import 'package:lafleurmusic/library/db.dart';
import 'package:lafleurmusic/library/sync.dart';
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
