import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lafleurmusic/library/db.dart';
import 'package:lafleurmusic/library/models.dart';
import 'package:lafleurmusic/offline/downloader.dart';
import 'package:lafleurmusic/offline/top_keeper.dart';
import 'package:lafleurmusic/player/media_resolver.dart';
import 'package:lafleurmusic/settings.dart';

import 'fake_device.dart';

const _mb = 1024 * 1024;

class _Dev extends FakeDevice {
  _Dev(super.root);
  @override
  Future<int> freeBytes(String path) async => 100 * 1024 * _mb;
  @override
  Future<bool> ensureAccess({bool readOthers = false}) async => true;
}

Track _t(String id, {int size = _mb, String? path}) => Track(
  path: path ?? 'subsonic://acc/$id',
  accountId: 'acc',
  remoteId: id,
  title: 'Song $id',
  artist: 'Art',
  albumArtist: 'Art',
  album: 'Alb',
  trackNo: 1,
  disc: 1,
  suffix: 'mp3',
  durationMs: 1000,
  hasCover: false,
  size: size,
);

void main() {
  late Directory tmp;
  late LibraryDb db;
  late AppSettings settings;
  late bool home;
  late Downloader dl;
  late TopKeeper keeper;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('top');
    db = LibraryDb(NativeDatabase.memory());
    settings = AppSettings();
    home = true;
    dl = Downloader(
      db: db,
      resolver: MediaResolver((_) async => throw StateError('no network')),
      device: _Dev(Directory('${tmp.path}/LAFLEURMUSIC')),
      settings: () async => settings,
      mayAutoDownload: () => home,
      client: () => http.Client(),
    );
    dl.pause(); // these tests look at the queue, not at the downloads
    keeper = TopKeeper(
      db: db,
      downloader: dl,
      atHome: () => home,
      debounce: const Duration(milliseconds: 20),
    );
  });
  tearDown(() async {
    keeper.dispose();
    await dl.whenIdle();
    await db.close();
    tmp.deleteSync(recursive: true);
  });

  Future<void> play(String id, int times) async {
    await db.upsertTrack(_t(id));
    for (var i = 0; i < times; i++) {
      await db.addPlay('subsonic://acc/$id', DateTime(2026, 1, 1, 0, 0, i));
    }
  }

  Future<Map<String, String>> reasons() async => {
    for (final r in (await db.watchOffline().first).values)
      r.trackPath: r.reason,
  };

  test('mobile data: nothing happens', () async {
    await play('1', 3);
    home = false;
    await keeper.refresh();
    expect(await reasons(), isEmpty);
  });

  test('at home: the top tracks are queued as top100', () async {
    await play('1', 5);
    await play('2', 4);
    await play('3', 3);
    await keeper.refresh();
    expect(await reasons(), {
      'subsonic://acc/1': 'top100',
      'subsonic://acc/2': 'top100',
      'subsonic://acc/3': 'top100',
    });
  });

  test('stops at the limit, in rank order, without error', () async {
    settings.storageLimitBytes = 2 * _mb + 1;
    await play('1', 5);
    await play('2', 4);
    await play('3', 3);
    await keeper.refresh();
    expect((await reasons()).keys, ['subsonic://acc/1', 'subsonic://acc/2']);
  });

  test('a local track is left alone', () async {
    await db.upsertTrack(_t('x', path: '/music/x.mp3'));
    await db.addPlay('/music/x.mp3', DateTime(2026));
    await keeper.refresh();
    expect(await reasons(), isEmpty);
  });

  test('left the top: top100 copy is forgotten, user copy stays', () async {
    await play('1', 5);
    await play('2', 4);
    await db.queueOffline(['subsonic://acc/1'], OfflineReason.top100);
    await db.queueOffline(['subsonic://acc/2'], OfflineReason.user);
    await db.upsertTrack(_t('9')); // never played: not in the top
    await db.queueOffline(['subsonic://acc/9'], OfflineReason.top100);
    await keeper.refresh();
    final r = await reasons();
    expect(r.containsKey('subsonic://acc/9'), isFalse);
    expect(r['subsonic://acc/1'], 'top100');
    expect(r['subsonic://acc/2'], 'user');
  });

  test('a burst of plays ends in one tour that sees them all', () async {
    await play('1', 1);
    keeper.schedule();
    keeper.schedule();
    await play('2', 1);
    keeper.schedule();
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect((await reasons()).keys.toSet(), {
      'subsonic://acc/1',
      'subsonic://acc/2',
    });
  });

  test(
    'a done top100 copy the user keeps stays when it leaves the top',
    () async {
      await play('1', 5);
      await db.queueOffline(['subsonic://acc/1'], OfflineReason.top100);
      await db.markOfflineDone('subsonic://acc/1', 'Art/Alb/01 Song 1.mp3', 4);
      await dl.keep([_t('1')]); // the user keeps it too
      expect((await db.offlineOf('subsonic://acc/1'))!.reason, 'user');
      expect((await db.offlineOf('subsonic://acc/1'))!.state, 'done');
      await db.customStatement(
        'DELETE FROM play_counts',
      ); // it falls out of the top
      await keeper.refresh();
      expect(await db.offlineOf('subsonic://acc/1'), isNotNull);
    },
  );

  test('reason is re-read at deletion: a user keep wins the race', () async {
    await play('1', 5);
    await db.queueOffline(['subsonic://acc/1'], OfflineReason.user);
    await dl.forget(['subsonic://acc/1'], only: OfflineReason.top100);
    expect(await db.offlineOf('subsonic://acc/1'), isNotNull);
  });

  test('a track the user removes is not kept again by the Top 100', () async {
    await play('1', 5);
    await play('2', 4);
    await keeper.refresh();
    expect((await reasons()).keys, hasLength(2));
    await dl.forget(['subsonic://acc/1'], byUser: true);
    await keeper.refresh();
    expect((await reasons()).keys, ['subsonic://acc/2']);
    await keeper.refresh(); // and it stays so
    expect((await reasons()).keys, ['subsonic://acc/2']);
  });

  test('a user keep lifts the block and the copy is the user\'s', () async {
    await play('1', 5);
    await keeper.refresh();
    await dl.forget(['subsonic://acc/1'], byUser: true);
    expect(await db.autoKeepBlocked(), {'subsonic://acc/1'});
    final r = await dl.keep([_t('1')]);
    expect(r.ok, isTrue);
    expect(await db.autoKeepBlocked(), isEmpty);
    expect((await db.offlineOf('subsonic://acc/1'))!.reason, 'user');
    // removed again by the user, then the Top 100 stays away again
    await dl.forget(['subsonic://acc/1'], byUser: true);
    await keeper.refresh();
    expect(await reasons(), isEmpty);
  });

  test('a refused user keep does not lift the block', () async {
    await play('1', 5);
    await dl.forget(['subsonic://acc/1'], byUser: true);
    settings.storageLimitBytes = 1;
    expect((await dl.keep([_t('1')])).ok, isFalse);
    expect(await db.autoKeepBlocked(), {'subsonic://acc/1'});
  });

  test('the Top 100 own drop-out and plain forgets create no block', () async {
    await play('1', 5);
    await keeper.refresh();
    await db.customStatement('DELETE FROM play_counts'); // out of the top
    await keeper.refresh();
    expect(await reasons(), isEmpty);
    expect(await db.autoKeepBlocked(), isEmpty);
    await db.addPlay('subsonic://acc/1', DateTime(2026, 2, 1)); // back in
    await keeper.refresh();
    expect((await reasons()).keys, ['subsonic://acc/1']);
    await dl.forget(['subsonic://acc/1']); // not by the user
    expect(await db.autoKeepBlocked(), isEmpty);
  });
}
