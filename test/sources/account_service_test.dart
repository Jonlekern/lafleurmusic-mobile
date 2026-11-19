import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lafleurmusic/library/db.dart';
import 'package:lafleurmusic/library/models.dart';
import 'package:lafleurmusic/library/sync.dart';
import 'package:lafleurmusic/player/media_resolver.dart';
import 'package:lafleurmusic/sources/account_service.dart';
import 'package:lafleurmusic/sources/accounts.dart';
import 'package:lafleurmusic/sources/plex.dart';
import 'package:lafleurmusic/sources/source.dart';
import 'package:lafleurmusic/sources/subsonic.dart';

import '../offline/fake_device.dart';
import 'fake_secret_store.dart';

void main() {
  group('AccountDraft', () {
    AccountDraft d(String address, {String name = '', String pw = 'x'}) =>
        AccountDraft(address: address, user: 'u', name: name, password: pw);

    test('address without scheme gets http://', () {
      expect(
        d('192.168.1.20:4533').base,
        Uri.parse('http://192.168.1.20:4533'),
      );
      expect(
        d(' https://m.example/sub ').base,
        Uri.parse('https://m.example/sub'),
      );
    });

    test('unusable addresses', () {
      expect(d('ftp://m.example').base, isNull);
      expect(d('http://').base, isNull);
      expect(
        d('http://').problem(needsPassword: true),
        DraftProblem.badAddress,
      );
      expect(d('').problem(needsPassword: true), DraftProblem.missing);
    });

    test('password needed only for a new account', () {
      expect(
        d('m.example', pw: '').problem(needsPassword: true),
        DraftProblem.missing,
      );
      expect(d('m.example', pw: '').problem(needsPassword: false), isNull);
    });

    test('home-network addresses (iOS local network permission)', () {
      for (final h in [
        '192.168.1.20:4533',
        'http://10.0.0.5',
        'http://172.16.0.1',
        'http://172.31.255.1',
        'http://169.254.3.4',
        'http://nas.local:4533',
        'http://[fe80::1]:4533',
        'http://[fd12::1]',
      ]) {
        expect(d(h).isLocalNetwork, isTrue, reason: h);
      }
      for (final h in [
        'https://music.example.com',
        'http://172.32.0.1',
        'http://8.8.8.8',
        'http://[2001:db8::1]',
        '',
      ]) {
        expect(d(h).isLocalNetwork, isFalse, reason: h);
      }
    });

    test('empty name falls back to the host', () {
      expect(d('http://192.168.1.20:4533').displayName, '192.168.1.20');
      expect(d('m.example', name: ' Maison ').displayName, 'Maison');
    });
  });

  test('Accounts.password and headers read the stored secrets', () async {
    final db = LibraryDb(NativeDatabase.memory());
    addTearDown(db.close);
    final accounts = Accounts(db, FakeSecretStore());
    final a = await accounts.add(
      type: AccountType.subsonic,
      name: 'N',
      base: Uri.parse('http://h'),
      user: 'u',
      password: 'pw',
      headers: {'X-A': '1'},
    );
    expect(await accounts.password(a.id), 'pw');
    expect(await accounts.headers(a.id), {'X-A': '1'});
    expect(await accounts.headers('nope'), isEmpty);
  });

  group('sync, edits and removal', () {
    late LibraryDb db;
    late Accounts accounts;
    late Account a;
    setUp(() async {
      db = LibraryDb(NativeDatabase.memory());
      accounts = Accounts(db, FakeSecretStore());
      a = await accounts.add(
        type: AccountType.subsonic,
        name: 'N',
        base: Uri.parse('http://h'),
        user: 'u',
        password: 'pw',
      );
    });
    tearDown(() => db.close());

    Future<List<String>> trackAccounts() async => [
      for (final t in await db.watchAllTracks().first) t.accountId,
    ];

    test('a Plex token refused while playing or downloading flips the account to « À reconnecter » at once', () async {
      final service = AccountService(
        accounts,
        db: db,
        sourceOf: (_) async => _CountingSource(a.id),
        wait: (_) => Completer<void>().future,
      );
      var notified = 0;
      service.addListener(() => notified++);
      expect(PlexSource.onTokenRefused, isNotNull);
      PlexSource.onTokenRefused!(a.id);
      expect(service.stateOf(a.id), AccountState.relink);
      expect(service.mayAnswer(a.id), isFalse);
      expect(notified, 1);
      service.dispose();
      expect(PlexSource.onTokenRefused, isNull);
    });

    test(
      'an edit never changes the type: a Subsonic account stays Subsonic',
      () async {
        final service = AccountService(
          accounts,
          db: db,
          sourceOf: (_) async => _CountingSource(a.id),
          wait: (_) => Completer<void>().future,
        );
        final saved = await service.save(
          const AccountDraft(
            type: AccountType.jellyfin,
            name: 'N2',
            address: 'http://h',
            user: 'u',
          ),
          editing: a,
        );
        expect(saved.type, AccountType.subsonic);
        final stored = (await accounts.watch().first).single;
        expect(stored.type, AccountType.subsonic);
        expect(stored.name, 'N2');
        // its keys still work: its source is a Subsonic one, with its password
        final source = await accounts.source(a.id);
        expect(source, isA<SubsonicSource>());
        expect(await accounts.password(a.id), 'pw');
        source.close();
        service.dispose();
      },
    );

    test(
      'removing during a sync leaves no track and no result behind',
      () async {
        final src = GatedSource(a.id, albumCount: 3);
        final service = AccountService(
          accounts,
          db: db,
          sourceOf: (_) async => src,
        );
        final running = service.sync(a.id);
        await src.reached(1); // album 1 stored, album 2 asked
        final removing = service.remove(a.id);
        src.release(); // the server answers album 2 after the removal began
        await removing;
        await running;
        expect(await trackAccounts(), isNot(contains(a.id)));
        expect(service.stateOf(a.id), isNull);
        expect(service.offline, isFalse);
      },
    );

    test('a server that never answers: sync ends incomplete, "Hors ligne", remove not stuck', () async {
      // home Navidrome seen from outside the house: 192.168.x.x hangs
      final hanging = MockClient((_) => Completer<http.Response>().future);
      final service = AccountService(
        accounts,
        db: db,
        sourceOf: (id) async => SubsonicSource(
          accountId: id,
          base: Uri.parse('http://192.168.1.20:4533'),
          user: 'u',
          password: 'pw',
          client: hanging,
          timeout: const Duration(milliseconds: 50),
        ),
      );
      final sw = Stopwatch()..start();
      await service.syncAll(); // pull-to-refresh awaits this
      expect(sw.elapsed, lessThan(const Duration(seconds: 5)));
      expect(service.syncing, isFalse);
      expect(service.stateOf(a.id), AccountState.absent);
      expect(service.offline, isTrue);
      final running = service.sync(a.id);
      await service.remove(a.id).timeout(const Duration(seconds: 5));
      await running;
      expect(await accounts.watch().first, isEmpty);
    });

    group('after a save', () {
      late List<Completer<void>> waits;
      late List<Duration> asked;
      Future<void> fakeWait(Duration d) {
        asked.add(d);
        final c = Completer<void>();
        waits.add(c);
        return c.future;
      }

      setUp(() {
        waits = [];
        asked = [];
      });
      const draft = AccountDraft(address: 'h:1', user: 'u', password: 'pw');

      Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

      test('syncs now and again after 30 s; a complete second one ends it', () async {
        final src = _CountingSource('x');
        final service = AccountService(
          accounts,
          db: db,
          sourceOf: (_) async => src,
          wait: fakeWait,
        );
        final acc = await service.save(draft);
        await settle();
        expect(src.runs, 1);
        expect(asked, [AccountService.followUpDelay]);
        waits[0].complete();
        await settle();
        expect(src.runs, 2);
        await settle();
        expect(waits.length, 1); // complete: no third
        expect(acc.id, isNotEmpty);
      });

      test('an incomplete 2nd sync gets a 3rd, never a 4th', () async {
        final src = _CountingSource('x', failAlbums: true);
        final service = AccountService(
          accounts,
          db: db,
          sourceOf: (_) async => src,
          wait: fakeWait,
        );
        await service.save(draft);
        await settle();
        waits[0].complete();
        await settle();
        expect(waits.length, 2);
        waits[1].complete();
        await settle();
        expect(src.runs, 3);
        await settle();
        expect(waits.length, 2);
      });

      test('a complete 2nd sync (after an incomplete first) ends the chain: no 3rd', () async {
        final src = _CountingSource('x', failAlbums: true);
        final service = AccountService(
          accounts,
          db: db,
          sourceOf: (_) async => src,
          wait: fakeWait,
        );
        await service.save(draft);
        await settle();
        src.failAlbums = false;
        waits[0].complete();
        await settle();
        expect(src.runs, 2);
        expect(waits.length, 1);
      });

      test('never two syncs at once: requests while one runs queue exactly one rerun', () async {
        final src = _CountingSource('x', gated: true);
        final service = AccountService(
          accounts,
          db: db,
          sourceOf: (_) async => src,
          wait: fakeWait,
        );
        await service.save(draft, editing: a);
        await settle();
        final r1 = service.sync(a.id, fresh: true);
        final r2 = service.sync(a.id, fresh: true);
        final r3 = service.sync(a.id, fresh: true);
        await settle();
        expect(src.active, 1);
        src.gate.complete();
        await Future.wait([r1, r2, r3]);
        expect(src.maxActive, 1);
        // save's own sync + one rerun for the three requests
        expect(src.runs, 2);
      });

      test('an edit does the same, and a newer save stops the older chain', () async {
        final src = _CountingSource('x');
        final service = AccountService(
          accounts,
          db: db,
          sourceOf: (_) async => src,
          wait: fakeWait,
        );
        await service.save(draft, editing: a);
        await settle();
        expect(src.runs, 1);
        await service.save(draft, editing: a);
        await settle();
        expect(src.runs, 2);
        expect(waits.length, 2);
        waits[0].complete(); // the older chain: stopped
        await settle();
        expect(src.runs, 2);
        waits[1].complete();
        await settle();
        expect(src.runs, 3);
      });

      test('removing the account ends the chain', () async {
        final src = _CountingSource('x');
        final service = AccountService(
          accounts,
          db: db,
          sourceOf: (_) async => src,
          wait: fakeWait,
        );
        await service.save(draft, editing: a);
        await settle();
        await service.remove(a.id);
        waits[0].complete();
        await settle();
        expect(src.runs, 1);
      });
    });

    group('timers and late answers', () {
      const draft = AccountDraft(address: 'h:1', user: 'u', password: 'pw');
      Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

      test('remove cancels the pending 30 s pause (default timer)', () {
        fakeAsync((fa) {
          final src = _CountingSource('x');
          final service = AccountService(accounts, db: db, sourceOf: (_) async => src);
          service.save(draft, editing: a);
          fa.flushMicrotasks();
          fa.elapse(const Duration(milliseconds: 100));
          expect(src.runs, 1);
          service.remove(a.id);
          fa.elapse(const Duration(seconds: 31));
          fa.flushMicrotasks();
          expect(src.runs, 1); // the pause was cancelled, no 2nd sync
        });
      });

      test('default timer: without a remove the 2nd sync fires after 30 s; dispose cancels it', () {
        fakeAsync((fa) {
          final src = _CountingSource('x');
          final service = AccountService(accounts, db: db, sourceOf: (_) async => src);
          service.save(draft, editing: a);
          fa.elapse(const Duration(seconds: 31));
          expect(src.runs, 2);
          final other = AccountService(accounts, db: db, sourceOf: (_) async => src);
          other.save(draft, editing: a);
          fa.elapse(const Duration(milliseconds: 100));
          other.dispose();
          fa.elapse(const Duration(seconds: 31));
          expect(src.runs, 3); // `other`'s first sync only
        });
      });

      AccountService svc(_CountingSource src, MediaResolver? r, DateTime Function() clock) =>
          AccountService(accounts, db: db, resolver: r, sourceOf: r?.source ?? (_) async => src, clock: clock, wait: (_) => Completer<void>().future);

      test('live server + one bad album: a later ok check does not sync again', () async {
        final src = _CountingSource('x', failAlbums: true);
        var now = DateTime(2026);
        final service = svc(src, null, () => now);
        await service.sync(a.id); // incomplete, but the server answers
        expect(src.runs, 1);
        now = now.add(const Duration(hours: 1));
        await service.checkAll([a.id]);
        await settle();
        expect(src.runs, 1);
      });

      test('unreachable at sync time, then an ok check: fresh source and sync (iOS prompt)', () async {
        final src = _CountingSource('x', failAlbums: true)..answer = TestResult.unreachable;
        var built = 0;
        final resolver = MediaResolver((id) async {
          built++;
          return src;
        });
        var now = DateTime(2026);
        final service = svc(src, resolver, () => now);
        await service.sync(a.id);
        expect(src.runs, 1);
        final before = built;
        src.failAlbums = false;
        src.answer = TestResult.ok;
        now = now.add(const Duration(minutes: 11));
        await service.checkAll([a.id]);
        await settle();
        expect(src.runs, 2);
        expect(built, greaterThan(before));
        await service.checkAll([a.id]);
        await settle();
        expect(src.runs, 2); // complete now
      });

      test('floor: no check-triggered sync within 10 min of the last sync start', () async {
        final src = _CountingSource('x', failAlbums: true)..answer = TestResult.unreachable;
        var now = DateTime(2026);
        final service = svc(src, null, () => now);
        await service.sync(a.id);
        src.answer = TestResult.ok;
        now = now.add(const Duration(minutes: 9));
        await service.checkAll([a.id]);
        await settle();
        expect(src.runs, 1);
        now = now.add(const Duration(minutes: 2));
        await service.checkAll([a.id]);
        await settle();
        expect(src.runs, 2); // the retry was kept for later
      });
    });

    test('remove forgets the account\'s cached covers', () async {
      final forgotten = <String>[];
      final service = AccountService(
        accounts,
        db: db,
        sourceOf: (id) async => GatedSource(id, albumCount: 0),
        forgetCovers: (id) async => forgotten.add(id),
      );
      await service.remove(a.id);
      expect(forgotten, [a.id]);
    });

    test('remove keeps the done copies as local tracks, drops the other rows', () async {
      final tmp = Directory.systemTemp.createTempSync('rm');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final k = 'subsonic://${a.id}/s1', q = 'subsonic://${a.id}/s2';
      for (final p in [k, q]) {
        await db.upsertTrack(Track(
          path: p,
          accountId: a.id,
          remoteId: p.split('/').last,
          title: 'T',
          artist: 'A',
          album: 'B',
          durationMs: 1,
          hasCover: false,
          size: 1,
        ));
      }
      await db.queueOffline([k, q], OfflineReason.user);
      await db.markOfflineDone(k, 'A/B/T.mp3', 1);
      File('${tmp.path}/A/B/T.mp3')
        ..createSync(recursive: true)
        ..writeAsBytesSync([1]);
      final service = AccountService(
        accounts,
        db: db,
        device: FakeDevice(tmp),
      );
      await service.remove(a.id);
      expect(await db.select(db.offline).get(), isEmpty);
      final left = await db.select(db.tracks).get();
      expect([for (final t in left) (t.path, t.accountId)], [('${tmp.path}/A/B/T.mp3', 'local')]);
    });

    group('playableNow', () {
      late Directory tmp;
      late AccountService service;
      late FakeDevice device;
      Track tr(String path, {String acc = 'local'}) => Track(
        path: path,
        accountId: acc,
        title: 'T',
        artist: 'A',
        album: 'B',
        durationMs: 1,
        hasCover: false,
        size: 1,
      );
      setUp(() async {
        tmp = Directory.systemTemp.createTempSync('play');
        service = AccountService(
          accounts,
          db: db,
          device: device = FakeDevice(tmp),
          sourceOf: (id) async => GatedSource(id, albumCount: 0, answer: TestResult.unreachable),
        );
        await service.watchOffline();
      });
      tearDown(() async {
        service.dispose();
        tmp.deleteSync(recursive: true);
      });

      test('local file: playable while the file exists', () {
        File('${tmp.path}/x.mp3').writeAsBytesSync([1]);
        expect(service.playableNow(tr('${tmp.path}/x.mp3')), isTrue);
        expect(service.playableNow(tr('${tmp.path}/nope.mp3')), isFalse);
      });

      test('server track: a done copy with its file, whatever the account says', () async {
        final k = 'subsonic://${a.id}/s1';
        await service.checkAll([a.id]); // unreachable → absent
        expect(service.stateOf(a.id), AccountState.absent);
        expect(service.playableNow(tr(k, acc: a.id)), isFalse);
        await db.queueOffline([k], OfflineReason.user);
        await db.markOfflineDone(k, 'A/s1.mp3', 1);
        await pumpEventQueue();
        expect(service.playableNow(tr(k, acc: a.id)), isFalse, reason: 'file missing');
        File('${tmp.path}/A/s1.mp3')
          ..createSync(recursive: true)
          ..writeAsBytesSync([1]);
        expect(service.playableNow(tr(k, acc: a.id)), isTrue);
      });

      test('the copies\' folder moved: playableNow follows it', () async {
        final k = 'subsonic://${a.id}/s1';
        await db.queueOffline([k], OfflineReason.user);
        await db.markOfflineDone(k, 'A/s1.mp3', 1);
        await service.checkAll([a.id]); // absent: only the copy can make it playable
        final moved = Directory('${tmp.path}/moved');
        File('${moved.path}/A/s1.mp3')
          ..createSync(recursive: true)
          ..writeAsBytesSync([1]);
        await pumpEventQueue();
        expect(service.playableNow(tr(k, acc: a.id)), isFalse, reason: 'old folder');
        device.root = moved;
        await service.refreshRoot();
        expect(service.playableNow(tr(k, acc: a.id)), isTrue);
      });

      test('an iCloud placeholder counts as there (iOS fetches it on open)', () async {
        final k = 'subsonic://${a.id}/s1';
        await service.checkAll([a.id]); // absent
        await db.queueOffline([k], OfflineReason.user);
        await db.markOfflineDone(k, 'A/s1.mp3', 1);
        File('${tmp.path}/A/.s1.mp3.icloud').createSync(recursive: true);
        await pumpEventQueue();
        expect(service.playableNow(tr(k, acc: a.id)), isTrue);
        File('${tmp.path}/.x.mp3.icloud').createSync();
        expect(service.playableNow(tr('${tmp.path}/x.mp3')), isTrue);
      });

      test('the same song on two accounts: playable while one twin is; '
          'both absent and nothing kept: not playable', () async {
        final b = await accounts.add(
          type: AccountType.subsonic,
          name: 'M',
          base: Uri.parse('http://h2'),
          user: 'u',
          password: 'pw',
        );
        Track song(String acc, String id) => Track(
          path: 'subsonic://$acc/$id',
          accountId: acc,
          remoteId: id,
          title: 'Night Swim',
          artist: 'Lafleur Surf',
          albumArtist: 'Lafleur Surf',
          album: 'Summer Mix',
          trackNo: 1,
          durationMs: 1,
          hasCover: false,
          size: 1,
        );
        final ta = song(a.id, 's1'), tb = song(b.id, 't1');
        await db.upsertTracks([ta, tb]);
        await pumpEventQueue();
        await service.checkAll([
          a.id,
        ]); // A absent, B never checked (P8: reachable)
        expect(service.playableNow(ta), isTrue);
        await service.checkAll([b.id]);
        expect(service.playableNow(ta), isFalse);
        expect(service.playableNow(tb), isFalse);
        await db.queueOffline([tb.path], OfflineReason.user);
        await db.markOfflineDone(tb.path, 'L/t1.mp3', 1);
        File('${tmp.path}/L/t1.mp3')
          ..createSync(recursive: true)
          ..writeAsBytesSync([1]);
        await pumpEventQueue();
        expect(service.playableNow(ta), isTrue, reason: 'kept copy of B');
      });

      test('an offline emit does not read the folder again; same rows: no notification', () async {
        final k = 'subsonic://${a.id}/s1';
        await db.queueOffline([k], OfflineReason.user);
        await pumpEventQueue();
        var n = 0;
        service.addListener(() => n++);
        final reads = device.rootReads;
        await db.markOfflineDone(k, 'A/s1.mp3', 1);
        await pumpEventQueue();
        expect(n, 1);
        await db.markOfflineDone(k, 'A/s1.mp3', 1); // same values: an emit, no change
        await pumpEventQueue();
        expect(n, 1);
        expect(device.rootReads, reads);
      });

      test('docs:// local track follows the Documents folder', () async {
        final docs = Directory('${tmp.path}/docs')..createSync();
        device.docs = docs;
        await service.refreshRoot();
        File('${docs.path}/LAFLEURMUSIC/x.mp3')
          ..createSync(recursive: true)
          ..writeAsBytesSync([1]);
        expect(service.playableNow(tr('docs://LAFLEURMUSIC/x.mp3')), isTrue);
        expect(service.playableNow(tr('docs://LAFLEURMUSIC/y.mp3')), isFalse);
      });

      test('server track without copy: playable unless the account is absent', () async {
        final k = tr('subsonic://${a.id}/s9', acc: a.id);
        expect(service.playableNow(k), isTrue, reason: 'not tested yet');
        await service.checkAll([a.id]);
        expect(service.playableNow(k), isFalse);
      });
    });

    test('remove with the folder unreachable keeps the finished copies untouched', () async {
      final tmp = Directory.systemTemp.createTempSync('rm');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final k = 'subsonic://${a.id}/s1';
      await db.upsertTrack(Track(
        path: k,
        accountId: a.id,
        remoteId: 's1',
        title: 'T',
        artist: 'A',
        album: 'B',
        durationMs: 1,
        hasCover: false,
        size: 1,
      ));
      await db.queueOffline([k], OfflineReason.user);
      await db.markOfflineDone(k, 'A/B/T.mp3', 1);
      final service = AccountService(
        accounts,
        db: db,
        device: FakeDevice(tmp)..reachable = false,
      );
      await service.remove(a.id);
      expect((await db.offlineOf(k))!.state, 'done');
      expect(await db.trackByPath(k), isNotNull);
    });

    test('account removed while the folder was unreachable: its copies become local once it answers', () async {
      final tmp = Directory.systemTemp.createTempSync('rm');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final k = 'subsonic://${a.id}/s1', q = 'subsonic://${a.id}/s2';
      for (final p in [k, q]) {
        await db.upsertTrack(Track(
          path: p,
          accountId: a.id,
          remoteId: p.split('/').last,
          title: 'T',
          artist: 'A',
          album: 'B',
          durationMs: 1,
          hasCover: false,
          size: 1,
        ));
      }
      await db.queueOffline([k, q], OfflineReason.user);
      await db.markOfflineDone(k, 'A/B/T.mp3', 1);
      await db.markOfflineDone(q, 'A/B/gone.mp3', 1); // file deleted by hand
      File('${tmp.path}/A/B/T.mp3')
        ..createSync(recursive: true)
        ..writeAsBytesSync([1]);
      await db.addPlay(k, DateTime(2026));
      final device = FakeDevice(tmp)..reachable = false;
      final service = AccountService(accounts, db: db, device: device);
      await service.remove(a.id);
      expect(await db.trackByPath(k), isNotNull); // stuck until the folder answers
      device.reachable = true;
      await service.refreshRoot();
      final abs = '${tmp.path}/A/B/T.mp3';
      expect(await db.trackByPath(k), isNull);
      expect(await db.trackByPath(q), isNull);
      expect((await db.trackByPath(abs))!.accountId, 'local');
      expect([for (final c in await db.select(db.playCounts).get()) c.path], [abs]);
      expect(await db.select(db.offline).get(), isEmpty);
    });

    test('an iCloud placeholder of a removed account\'s copy becomes a local track', () async {
      final tmp = Directory.systemTemp.createTempSync('rm');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final k = 'subsonic://${a.id}/s1';
      await db.upsertTrack(Track(
        path: k,
        accountId: a.id,
        remoteId: 's1',
        title: 'T',
        artist: 'A',
        album: 'B',
        durationMs: 1,
        hasCover: false,
        size: 7,
      ));
      await db.queueOffline([k], OfflineReason.user);
      await db.markOfflineDone(k, 'A/B/T.mp3', 7);
      File('${tmp.path}/A/B/.T.mp3.icloud').createSync(recursive: true);
      await db.addPlay(k, DateTime(2026));
      final service = AccountService(accounts, db: db, device: FakeDevice(tmp));
      await service.remove(a.id);
      final abs = '${tmp.path}/A/B/T.mp3';
      final local = (await db.trackByPath(abs))!;
      expect((local.accountId, local.size), ('local', 7));
      expect([for (final c in await db.select(db.playCounts).get()) c.path], [abs]);
    });

    test('refreshRoot notifies even without a device', () async {
      final service = AccountService(accounts, db: db);
      var n = 0;
      service.addListener(() => n++);
      await service.refreshRoot();
      expect(n, 1);
    });

    test('remove invalidates the player source', () async {
      var built = 0;
      final resolver = MediaResolver((id) async {
        built++;
        return GatedSource(id, albumCount: 0);
      });
      final service = AccountService(accounts, db: db, resolver: resolver);
      await resolver.source(a.id);
      await service.remove(a.id);
      await resolver.source(a.id).catchError((_) => GatedSource('x'));
      expect(built, 2);
    });

    test('a check asked during a sync is not lost: the server cut meanwhile '
        'is seen once the sync ends, even if the sync finished', () async {
      final runs = <Completer<SyncResult>>[];
      final src = _CountingSource(a.id);
      final service = AccountService(
        accounts,
        db: db,
        sourceOf: (_) async => src,
        sync: (_) {
          final c = Completer<SyncResult>();
          runs.add(c);
          return c.future;
        },
      );
      final syncing = service.sync(a.id);
      await pumpEventQueue();
      // the network changes while the sync stores what it already read
      src.answer = TestResult.unreachable;
      await service.checkAccounts();
      expect(service.stateOf(a.id), AccountState.syncing);
      runs.single.complete(
        const SyncResult(added: 0, updated: 0, removed: 0, complete: true),
      );
      await syncing;
      await pumpEventQueue();
      expect(service.stateOf(a.id), AccountState.absent);
      service.dispose();
    });

    test(
      'an edit during a sync runs one more sync with the new settings',
      () async {
        final runs = <Completer<SyncResult>>[];
        final built = <String>[];
        final service = AccountService(
          accounts,
          db: db,
          sourceOf: (id) async {
            built.add((await accounts.watch().first).single.base.toString());
            return GatedSource(id, answer: TestResult.unreachable);
          },
          sync: (_) {
            final c = Completer<SyncResult>();
            runs.add(c);
            return c.future;
          },
        );
        final first = service.sync(a.id);
        await pumpEventQueue();
        expect(runs, hasLength(1));
        await service.save(
          const AccountDraft(address: 'http://new', user: 'u'),
          editing: a,
        );
        // the old run fails (stale): its "unreachable" must not stick
        runs[0].complete(
          const SyncResult(added: 0, updated: 0, removed: 0, complete: false),
        );
        await pumpEventQueue();
        expect(runs, hasLength(2), reason: 'one more run, queued');
        runs[1].complete(
          const SyncResult(added: 0, updated: 0, removed: 0, complete: true),
        );
        await first;
        await pumpEventQueue();
        expect(built.last, 'http://new');
        expect(service.stateOf(a.id), AccountState.connected);
        expect(service.offline, isFalse);
      },
    );
  });

  group('écoutes en attente', () {
    late LibraryDb db;
    late _ScrobbleFake src;
    late AccountService service;
    // recent dates: listens older than 30 days are dropped
    final base = DateTime.now().millisecondsSinceEpoch - 2 * 86400000;
    DateTime at(int h) => DateTime.fromMillisecondsSinceEpoch(base + h * 3600000);
    final d1 = at(0), d2 = at(1), d3 = at(2);

    setUp(() async {
      db = LibraryDb(NativeDatabase.memory());
      src = _ScrobbleFake('acc');
      service = AccountService(
        Accounts(db, FakeSecretStore()),
        db: db,
        sourceOf: (_) async => src,
        sync: (_) async =>
            const SyncResult(added: 0, updated: 0, removed: 0, complete: true),
      );
      // added out of date order on purpose
      await db.addPending('acc', 's2', d2);
      await db.addPending('acc', 's1', d1);
      await db.addPending('acc', 's3', d3);
      await db.addPending('other', 'x', d1);
    });
    tearDown(() async {
      service.dispose();
      await db.close();
    });

    test(
      'server back: sent in date order with the original date, then erased',
      () async {
        await service.checkAll(['acc']);
        expect(src.sent, [('s1', d1), ('s2', d2), ('s3', d3)]);
        expect(await db.pending('acc'), isEmpty);
        expect((await db.pending('other')), hasLength(1)); // not this account
      },
    );

    test('server unreachable: nothing sent, nothing erased', () async {
      src.answer = TestResult.unreachable;
      await service.checkAll(['acc']);
      expect(src.sent, isEmpty);
      expect(await db.pending('acc'), hasLength(3));
    });

    test('an error in the middle: the next ones stay', () async {
      src.failOn = 's2';
      await service.checkAll(['acc']);
      expect(src.sent, [('s1', d1)]);
      expect(
        [for (final p in await db.pending('acc')) p.remoteId],
        ['s2', 's3'],
      );
    });

    test('unknown song (code 70): dropped, the rest goes on', () async {
      src.failOn = 's2';
      src.error = SubsonicException('gone', code: 70);
      await service.checkAll(['acc']);
      expect(src.sent, [('s1', d1), ('s3', d3)]);
      expect(await db.pending('acc'), isEmpty);
    });

    test('two quick returns: no duplicate', () async {
      src.gate = Completer<void>();
      final first = service.checkAll(['acc']);
      await src.reachedSend;
      final second = service.checkAll([
        'acc',
      ]); // answers while the first flush runs
      await Future<void>.delayed(const Duration(milliseconds: 20));
      src.gate!.complete();
      await Future.wait([first, second]);
      expect([for (final s in src.sent) s.$1], ['s1', 's2', 's3']);
    });

    test('listens older than 30 days are dropped, never sent', () async {
      final old = DateTime.now().subtract(const Duration(days: 31));
      await db.addPending('acc', 'ancient', old);
      await service.checkAll(['acc']);
      expect([for (final s in src.sent) s.$1], ['s1', 's2', 's3']);
      expect(await db.pending('acc'), isEmpty);
    });

    test('a finished sync sends them too', () async {
      await service.sync('acc');
      expect([for (final s in src.sent) s.$1], ['s1', 's2', 's3']);
      expect(await db.pending('acc'), isEmpty);
    });
  });
}

/// Counts the sync runs (one `albums()` call each) and how many overlap.
class _CountingSource implements MusicSource {
  _CountingSource(this.accountId, {this.failAlbums = false, this.gated = false});
  @override
  final String accountId;
  bool failAlbums;
  TestResult answer = TestResult.ok;
  final bool gated;
  final gate = Completer<void>();
  int runs = 0, active = 0, maxActive = 0;

  @override
  Future<TestResult> test() async => answer;

  @override
  Stream<List<SourceAlbum>> albums({int pageSize = 500}) async* {
    runs++;
    active++;
    if (active > maxActive) maxActive = active;
    try {
      if (gated && runs == 1) await gate.future;
      yield [
        for (var i = 1; i <= 2; i++)
          SourceAlbum(id: 'al$i', name: 'A$i', artist: 'A'),
      ];
    } finally {
      active--;
    }
  }

  @override
  Future<List<SourceSong>> albumSongs(String albumId) async {
    if (failAlbums && albumId == 'al1') throw const SocketException('cut');
    return [
      SourceSong(
        id: 's$albumId',
        title: 'T',
        artist: 'A',
        album: albumId,
        albumArtist: 'A',
      ),
    ];
  }

  @override
  Future<List<SourcePlaylist>> playlists() async => const [];

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// Source whose album songs wait for [release] from album 2 on; [reached] waits for album n to be asked.
class GatedSource implements MusicSource {
  GatedSource(
    this.accountId, {
    this.albumCount = 2,
    this.answer = TestResult.ok,
  });
  @override
  final String accountId;
  final int albumCount;
  final TestResult answer;
  final _gate = Completer<void>();
  final _asked = StreamController<int>.broadcast();
  int asked = 0;

  void release() => _gate.complete();
  Future<void> reached(int n) async {
    if (asked > n) return;
    await _asked.stream.firstWhere((i) => i > n);
  }

  @override
  Future<TestResult> test() async => answer;

  @override
  Stream<List<SourceAlbum>> albums({int pageSize = 500}) async* {
    yield [
      for (var i = 1; i <= albumCount; i++)
        SourceAlbum(id: 'al$i', name: 'Album $i', artist: 'A'),
    ];
  }

  @override
  Future<List<SourceSong>> albumSongs(String albumId) async {
    asked++;
    _asked.add(asked);
    if (asked > 1) await _gate.future;
    return [
      SourceSong(
        id: 's$albumId',
        title: 'T',
        artist: 'A',
        album: 'Album $albumId',
        albumArtist: 'A',
      ),
    ];
  }

  @override
  Future<List<SourcePlaylist>> playlists() async => const [];

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// Answers [test] with [answer]; records scrobbles. [failOn] makes that song fail with [error];
/// [gate] holds the first scrobble until completed.
class _ScrobbleFake implements MusicSource {
  _ScrobbleFake(this.accountId);
  @override
  final String accountId;
  TestResult answer = TestResult.ok;
  String? failOn;
  Object error = SourceNetworkException(Exception('offline'));
  Completer<void>? gate;
  final sent = <(String, DateTime)>[];
  final _reached = Completer<void>();
  Future<void> get reachedSend => _reached.future;

  @override
  Future<TestResult> test() async => answer;

  @override
  Future<void> scrobble(String songId, DateTime at) async {
    if (!_reached.isCompleted) _reached.complete();
    await gate?.future;
    if (songId == failOn) throw error;
    sent.add((songId, at));
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}
