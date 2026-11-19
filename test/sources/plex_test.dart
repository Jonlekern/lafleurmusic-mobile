import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/library/db.dart';
import 'package:lafleurmusic/library/sync.dart';
import 'package:lafleurmusic/sources/account_service.dart';
import 'package:lafleurmusic/sources/accounts.dart';
import 'package:lafleurmusic/sources/plex.dart';
import 'package:lafleurmusic/sources/plex_link.dart';
import 'package:lafleurmusic/sources/remote_key.dart';
import 'package:lafleurmusic/sources/source.dart';

import 'fake_plex.dart';
import 'fake_secret_store.dart';

final home = PlexServer.fromResource(resourceJson(homeResource))!;

PlexSource plexSource(
  FakePms pms, {
  FakeSecretStore? secrets,
  String? token = 'server-token-home',
  Map<String, String> headers = const {},
  PlexServer? server,
  FakePlexTv? tv,
  DateTime Function()? now,
}) {
  final s = secrets ?? FakeSecretStore();
  if (token != null) s.data[PlexSource.tokenKey('acc1')] = token;
  return PlexSource(
    accountId: 'acc1',
    server: server ?? home,
    clientId: 'client-abc',
    headers: headers,
    client: tv?.client() ?? pms.client(),
    secrets: s,
    deviceName: 'iPhone',
    platform: 'iOS',
    now: now,
  );
}

void main() {
  group('PlexSource.test', () {
    test('ok: the best address answers and the token is accepted', () async {
      final pms = FakePms();
      final s = plexSource(pms, headers: const {'CF-Access-Client-Id': 'abc'});
      expect(await s.test(), TestResult.ok);
      expect(s.base?.host, homeLocal);
      final sections = pms.log.singleWhere(
        (r) => r.url.path == '/library/sections',
      );
      expect(sections.headers['X-Plex-Token'], 'server-token-home');
      expect(sections.headers['X-Plex-Product'], 'LAFLEURMUSIC');
      expect(sections.headers['CF-Access-Client-Id'], 'abc');
      // the token travels in a header only
      for (final r in pms.log) {
        expect(r.url.toString(), isNot(contains('server-token-home')));
      }
    });

    test('Focus 5: token revoked on plex.tv (401) → to reconnect', () async {
      final pms = FakePms()..tokens = {};
      final secrets = FakeSecretStore();
      final s = plexSource(pms, secrets: secrets);
      expect(await s.test(), TestResult.tokenRevoked);
      // nothing erased: the account and its token stay until a new code
      expect(secrets.data[PlexSource.tokenKey('acc1')], 'server-token-home');
    });

    test('no token stored → to reconnect', () async {
      final s = plexSource(FakePms(), token: null);
      expect(await s.test(), TestResult.tokenRevoked);
    });

    test('no address answers → unreachable', () async {
      final pms = FakePms()..down = {homeLocal, homeRemote, homeRelay};
      expect(await plexSource(pms).test(), TestResult.unreachable);
    });

    test('each test picks the address again (home, then away)', () async {
      final pms = FakePms();
      final s = plexSource(pms);
      expect(await s.test(), TestResult.ok);
      expect(s.base?.host, homeLocal);
      pms.down = {homeLocal};
      expect(await s.test(), TestResult.ok);
      expect(s.base?.host, homeRemote);
      pms.down = {};
      expect(await s.test(), TestResult.ok);
      expect(s.base?.host, homeLocal);
    });
  });

  group('stale addresses: the list is read again from plex.tv', () {
    // the list saved before the public IP changed: the old remote address is gone
    const oldRemote = '198-51-100-99.hash.plex.direct';
    final stale = PlexServer.fromResource(
      resourceJson(
        homeResource
            .replaceAll(homeRemote, oldRemote)
            .replaceAll(homeRelay, 'old-relay.plex.direct'),
      ),
    )!;

    setUp(PlexSource.resetRefreshCooldowns);

    int resourceReads(FakePlexTv tv) =>
        tv.log.where((r) => r.url.path == '/api/v2/resources').length;

    FakeSecretStore withAccountToken() =>
        FakeSecretStore()
          ..data[PlexSource.accountTokenKey('acc1')] = 'user-token-1';

    test(
      'away, old remote silent: the refreshed list works and is saved',
      () async {
        final tv = FakePlexTv();
        tv.pms.down = {homeLocal};
        final secrets = withAccountToken();
        final s = plexSource(tv.pms, secrets: secrets, server: stale, tv: tv);
        // this check stays short: the refresh runs in the background
        expect(await s.test(), TestResult.unreachable);
        await s.refreshing;
        expect(s.base?.host, homeRemote);
        expect(await s.test(), TestResult.ok);
        expect(s.base?.host, homeRemote);
        final saved = PlexServer.fromJson(
          jsonDecode(secrets.data[PlexSource.serverKey('acc1')]!),
        );
        expect([
          for (final c in saved.connections) c.uri.host,
        ], contains(homeRemote));
        expect(saved.machineId, 'mach-home');
        expect(jsonEncode(saved.toJson()), isNot(contains('token')));
        // the plex.tv token goes to plex.tv only, never to the media server
        for (final r in tv.pms.log) {
          expect(r.headers.values, isNot(contains('user-token-1')));
        }
        expect(
          tv.log.where((r) => r.url.path == '/api/v2/resources'),
          hasLength(1),
        );
        // next check: the new list straight away, plex.tv not asked again
        expect(await s.test(), TestResult.ok);
        expect(
          tv.log.where((r) => r.url.path == '/api/v2/resources'),
          hasLength(1),
        );
      },
    );

    test(
      'plex.tv unreachable: stays unreachable, no crash, nothing saved',
      () async {
        final tv = FakePlexTv()..down = true;
        tv.pms.down = {homeLocal};
        final secrets = withAccountToken();
        final s = plexSource(tv.pms, secrets: secrets, server: stale, tv: tv);
        expect(await s.test(), TestResult.unreachable);
        await s.refreshing;
        expect(secrets.data.containsKey(PlexSource.serverKey('acc1')), isFalse);
        await expectLater(s.prepare(), throwsA(isA<PlexException>()));
        await s.refreshing;
      },
    );

    test('an address that answers: plex.tv is not asked', () async {
      final tv = FakePlexTv();
      final s = plexSource(
        tv.pms,
        secrets: withAccountToken(),
        server: stale,
        tv: tv,
      );
      expect(await s.test(), TestResult.ok);
      expect(tv.log, isEmpty);
    });

    test('same list from plex.tv (server off): nothing rewritten', () async {
      final tv = FakePlexTv();
      tv.pms.down = {homeLocal, homeRemote, homeRelay};
      final secrets = withAccountToken();
      final s = plexSource(tv.pms, secrets: secrets, tv: tv);
      expect(await s.test(), TestResult.unreachable);
      await s.refreshing;
      expect(resourceReads(tv), 1);
      expect(secrets.data.containsKey(PlexSource.serverKey('acc1')), isFalse);
    });

    test(
      'cooldown: five prepare() with the server down → one plex.tv read',
      () async {
        final tv = FakePlexTv();
        tv.pms.down = {homeLocal, homeRemote, homeRelay};
        final secrets = withAccountToken();
        var clock = DateTime.utc(2026, 11, 19, 10);
        PlexSource build() =>
            plexSource(tv.pms, secrets: secrets, tv: tv, now: () => clock);
        final s = build();
        for (var i = 0; i < 5; i++) {
          await expectLater(s.prepare(), throwsA(isA<PlexException>()));
          await s.refreshing;
        }
        expect(resourceReads(tv), 1);
        // the source is rebuilt (resolver, sync): still cooling down
        final again = build();
        expect(await again.test(), TestResult.unreachable);
        await again.refreshing;
        expect(resourceReads(tv), 1);
        // 10 minutes later: plex.tv is asked again
        clock = clock.add(const Duration(minutes: 10, seconds: 1));
        expect(await again.test(), TestResult.unreachable);
        await again.refreshing;
        expect(resourceReads(tv), 2);
        // the network changed (home/away): asked again at once
        PlexSource.resetRefreshCooldowns();
        expect(await again.test(), TestResult.unreachable);
        await again.refreshing;
        expect(resourceReads(tv), 3);
      },
    );

    test('the cooldown is per account', () async {
      final tv = FakePlexTv();
      tv.pms.down = {homeLocal, homeRemote, homeRelay};
      final s = plexSource(tv.pms, secrets: withAccountToken(), tv: tv);
      await s.test();
      await s.refreshing;
      final other = PlexSource(
        accountId: 'acc2',
        server: home,
        clientId: 'client-abc',
        client: tv.client(),
        secrets: FakeSecretStore()
          ..data[PlexSource.tokenKey('acc2')] = 't'
          ..data[PlexSource.accountTokenKey('acc2')] = 'user-token-1',
      );
      await other.test();
      await other.refreshing;
      expect(resourceReads(tv), 2);
    });

    test(
      'worst case: every address and plex.tv hang, test() ends within 10 s',
      () {
        fakeAsync((fa) {
          final tv = FakePlexTv()..hang = true;
          tv.pms.hang = {homeLocal, homeRemote, homeRelay};
          final s = plexSource(tv.pms, secrets: withAccountToken(), tv: tv);
          TestResult? r;
          s.test().then((v) => r = v);
          fa.elapse(const Duration(seconds: 8, milliseconds: 100));
          expect(r, TestResult.unreachable);
          expect(resourceReads(tv), 1); // the refresh went on in the background
          // the background refresh ends too (its own time limits), nothing left behind
          fa.elapse(const Duration(minutes: 1));
          expect(fa.pendingTimers, isEmpty);
        });
      },
    );

    test('no plex.tv token kept: no refresh, unreachable', () async {
      final tv = FakePlexTv();
      tv.pms.down = {homeLocal};
      final s = plexSource(tv.pms, server: stale, tv: tv);
      expect(await s.test(), TestResult.unreachable);
      expect(tv.log, isEmpty);
    });
  });

  group('PlexSource auth', () {
    test(
      'prepare loads the token and picks an address; headers carry it',
      () async {
        final s = plexSource(FakePms());
        expect(s.headers.containsKey('X-Plex-Token'), isFalse);
        await s.prepare();
        expect(s.headers['X-Plex-Token'], 'server-token-home');
        expect(s.base?.host, homeLocal);
        for (final v in s.headers.values) {
          expect(v, isNot(contains(',')));
        }
      },
    );

    test(
      'prepare with no token: a PlexException asking for a new code',
      () async {
        final s = plexSource(FakePms(), token: null);
        final e = await s.prepare().then<Object?>(
          (_) => null,
          onError: (Object e) => e,
        );
        expect(e, isA<PlexException>());
        expect((e as PlexException).tokenRefused, isTrue);
      },
    );

    test(
      'renewAuth cannot renew a Plex token: refused, token not in the text',
      () async {
        final s = plexSource(FakePms());
        await s.prepare();
        final e = await s.renewAuth().then<Object?>(
          (_) => null,
          onError: (Object e) => e,
        );
        expect(e, isA<PlexException>());
        expect((e as PlexException).tokenRefused, isTrue);
        expect('$e', isNot(contains('server-token-home')));
      },
    );

    test('library and playback come in the next tasks', () {
      final s = plexSource(FakePms());
      expect(() => s.albums(), throwsUnimplementedError);
      expect(() => s.albumSongs('1'), throwsUnimplementedError);
      expect(() => s.streamUri('1'), throwsUnimplementedError);
      expect(s.accountType, AccountType.plex);
    });
  });

  test('plex:// keys', () {
    expect(remoteKey(AccountType.plex, 'acc1', '42'), 'plex://acc1/42');
    expect(parseRemoteKey('plex://acc1/42'), ('acc1', '42'));
    expect(isRemotePath('plex://acc1/42'), isTrue);
  });

  group('Accounts (Plex)', () {
    late LibraryDb db;
    late FakeSecretStore secrets;
    late Accounts accounts;
    setUp(() {
      db = LibraryDb(NativeDatabase.memory());
      secrets = FakeSecretStore();
      accounts = Accounts(db, secrets);
    });
    tearDown(() => db.close());

    test('the client identifier is made once and kept', () async {
      final a = await accounts.plexClientId();
      expect(a, hasLength(32));
      expect(await accounts.plexClientId(), a);
      expect(await Accounts(db, secrets).plexClientId(), a);
    });

    test(
      'addPlex keeps the token and the addresses in the store, not in the row',
      () async {
        final a = await accounts.addPlex(
          name: 'Plex maison',
          server: home,
          token: 'server-token-home',
          base: Uri.parse('https://$homeLocal:32400'),
          accountToken: 'user-token-1',
          plexUser: 'user-uuid-1',
        );
        expect(secrets.data[PlexSource.accountTokenKey(a.id)], 'user-token-1');
        expect(await accounts.plexUser(a.id), 'user-uuid-1');
        expect(a.type, AccountType.plex);
        expect(a.base.host, homeLocal);
        expect(secrets.data[PlexSource.tokenKey(a.id)], 'server-token-home');
        final stored = PlexServer.fromJson(
          jsonDecode(secrets.data[PlexSource.serverKey(a.id)]!),
        );
        expect(stored.machineId, 'mach-home');
        expect(stored.connections, hasLength(3));
        final row = await db.select(db.accountRows).getSingle();
        expect('${row.base}${row.user}${row.name}', isNot(contains('token')));
        final s = await accounts.source(a.id, client: FakePms().client());
        expect(s, isA<PlexSource>());
        expect(await s.test(), TestResult.ok);
      },
    );

    test('relinkPlex replaces the token in place: same id', () async {
      final a = await accounts.addPlex(
        name: 'Plex maison',
        server: home,
        token: 'old-token',
        base: Uri.parse('https://$homeLocal:32400'),
      );
      await accounts.relinkPlex(
        a.id,
        server: home,
        token: 'server-token-home',
        base: Uri.parse('https://$homeRemote:32400'),
        accountToken: 'user-token-2',
      );
      expect(secrets.data[PlexSource.accountTokenKey(a.id)], 'user-token-2');
      final list = await accounts.watch().first;
      expect(list.single.id, a.id);
      expect(list.single.name, 'Plex maison');
      expect(list.single.base.host, homeRemote);
      expect(secrets.data[PlexSource.tokenKey(a.id)], 'server-token-home');
    });

    test('remove erases the Plex secrets, not the client identifier', () async {
      final id = await accounts.plexClientId();
      final a = await accounts.addPlex(
        name: 'P',
        server: home,
        token: 't',
        base: Uri.parse('https://$homeLocal:32400'),
      );
      await accounts.remove(a.id, root: null);
      expect(secrets.data.keys.where((k) => k.contains(a.id)), isEmpty);
      expect(await accounts.plexClientId(), id);
    });

    test('renaming a Plex account keeps its token', () async {
      final a = await accounts.addPlex(
        name: 'P',
        server: home,
        token: 't',
        base: Uri.parse('https://$homeLocal:32400'),
      );
      await accounts.update(
        Account(
          id: a.id,
          type: a.type,
          name: 'Plex maison',
          base: a.base,
          user: a.user,
          order: a.order,
        ),
      );
      expect(secrets.data[PlexSource.tokenKey(a.id)], 't');
    });
  });

  group('AccountService (Plex)', () {
    late LibraryDb db;
    late FakeSecretStore secrets;
    late Accounts accounts;
    setUp(() {
      db = LibraryDb(NativeDatabase.memory());
      secrets = FakeSecretStore();
      accounts = Accounts(db, secrets);
    });
    tearDown(() => db.close());

    test('Focus 5: a revoked token marks « à reconnecter »; a new code fixes it in place', () async {
      final pms = FakePms()..tokens = {'server-token-new'};
      final synced = <String>[];
      final service = AccountService(
        accounts,
        db: db,
        sourceOf: (id) => accounts.source(id, client: pms.client()),
        sync: (s) async {
          synced.add(s.accountId);
          return const SyncResult(
            added: 0,
            updated: 0,
            removed: 0,
            complete: true,
          );
        },
        wait: (_) => Completer<void>().future,
      );
      final a = await service.addPlex(
        name: 'Plex maison',
        server: home,
        token: 'server-token-home',
        base: Uri.parse('https://$homeLocal:32400'),
      );
      await Future<void>.delayed(Duration.zero);
      synced.clear();
      await service.checkAll([a.id]);
      expect(service.stateOf(a.id), AccountState.relink);
      expect(service.mayAnswer(a.id), isFalse);
      expect(service.absentIds, contains(a.id));

      await service.relinkPlex(
        a.id,
        server: home,
        token: 'server-token-new',
        base: Uri.parse('https://$homeLocal:32400'),
      );
      expect(service.stateOf(a.id), isNot(AccountState.relink));
      expect((await accounts.watch().first).single.id, a.id);
      expect(secrets.data[PlexSource.tokenKey(a.id)], 'server-token-new');
      await Future<void>.delayed(Duration.zero);
      expect(synced, [a.id]);
      await service.checkAll([a.id]);
      expect(service.stateOf(a.id), AccountState.connected);
      service.dispose();
    });
  });
}
