import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/library/db.dart';
import 'package:lafleurmusic/library/models.dart';

void main() {
  late LibraryDb db;
  setUp(() => db = LibraryDb(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('nextQueued returns the oldest queued row', () async {
    await db.queueOffline(['a'], OfflineReason.user);
    await Future<void>.delayed(const Duration(milliseconds: 3));
    await db.queueOffline(['b'], OfflineReason.user);
    expect((await db.nextQueued())!.trackPath, 'a');
    await db.markOfflineDone('a', 'f/a.mp3', 10);
    expect((await db.nextQueued())!.trackPath, 'b');
    await db.markOfflineDone('b', 'f/b.mp3', 10);
    expect(await db.nextQueued(), isNull);
  });

  test(
    'a row fails at its third failure and is no longer queued next',
    () async {
      await db.queueOffline(['a'], OfflineReason.user);
      await db.markOfflineFailed('a');
      await db.markOfflineFailed('a');
      var r = (await db.offlineOf('a'))!;
      expect((r.failures, r.state), (2, 'queued'));
      expect((await db.nextQueued())!.trackPath, 'a');
      await db.markOfflineFailed('a');
      r = (await db.offlineOf('a'))!;
      expect((r.failures, r.state), (3, 'failed'));
      expect(await db.nextQueued(), isNull);
    },
  );

  test('user is never downgraded to top100, top100 upgrades to user', () async {
    await db.queueOffline(['a'], OfflineReason.user);
    await db.queueOffline(['a'], OfflineReason.top100);
    expect((await db.offlineOf('a'))!.reason, 'user');
    await db.queueOffline(['b'], OfflineReason.top100);
    expect((await db.offlineOf('b'))!.reason, 'top100');
    await db.queueOffline(['b'], OfflineReason.user);
    expect((await db.offlineOf('b'))!.reason, 'user');
  });

  test('queueing again keeps a done copy', () async {
    await db.queueOffline(['a'], OfflineReason.user);
    await db.markOfflineDone('a', 'f/a.mp3', 10);
    await db.queueOffline(['a'], OfflineReason.user);
    final r = (await db.offlineOf('a'))!;
    expect((r.state, r.filePath, r.size), ('done', 'f/a.mp3', 10));
  });

  test('queueing again re-queues a failed row', () async {
    await db.queueOffline(['a'], OfflineReason.user);
    for (var i = 0; i < 3; i++) {
      await db.markOfflineFailed('a');
    }
    await db.queueOffline(['a'], OfflineReason.user);
    final r = (await db.offlineOf('a'))!;
    expect((r.state, r.failures), ('queued', 0));
  });

  test('offlineBytes counts done rows only', () async {
    await db.queueOffline(['a', 'b', 'c'], OfflineReason.user);
    await db.markOfflineDone('a', 'a', 100);
    await db.markOfflineDone('b', 'b', 50);
    expect(await db.offlineBytes(), 150);
    await db.removeOffline(['a']);
    expect(await db.offlineBytes(), 50);
    expect(await db.offlineOf('a'), isNull);
  });

  test('watchOffline emits a map by track path', () async {
    final first = db.watchOffline().first;
    await db.queueOffline(['a'], OfflineReason.top100);
    final later = db.watchOffline().first;
    expect((await later).keys, ['a']);
    await first;
  });

  test('pending scrobbles are per account and deletable', () async {
    await db.addPending('x', '1', DateTime.fromMillisecondsSinceEpoch(5));
    await db.addPending('x', '2', DateTime.fromMillisecondsSinceEpoch(6));
    await db.addPending('y', '3', DateTime.fromMillisecondsSinceEpoch(7));
    final x = await db.pending('x');
    expect(x.map((p) => (p.remoteId, p.at)), [('1', 5), ('2', 6)]);
    await db.deletePending([x.first.id]);
    expect((await db.pending('x')).single.remoteId, '2');
    expect(await db.pending('y'), hasLength(1));
  });
}
