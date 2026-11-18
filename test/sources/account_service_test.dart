import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lafleurmusic/library/db.dart';
import 'package:lafleurmusic/library/models.dart';
import 'package:lafleurmusic/library/sync.dart';
import 'package:lafleurmusic/player/media_resolver.dart';
import 'package:lafleurmusic/sources/account_service.dart';
import 'package:lafleurmusic/sources/accounts.dart';
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
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}
