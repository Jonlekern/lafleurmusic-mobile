import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/library/db.dart';
import 'package:lafleurmusic/library/models.dart';
import 'package:lafleurmusic/library/sync.dart';
import 'package:lafleurmusic/sources/source.dart';

class FakeSource implements MusicSource {
  FakeSource(this.accountId, this.library, {this.failAtPage, this.failSongsOf});
  @override
  final String accountId;
  Map<SourceAlbum, List<SourceSong>> library;
  String? failSongsOf; // album id whose songs fetch throws
  int? failAtPage; // 1-based page whose fetch throws
  int produced = 0, processed = 0, maxAlive = 0;

  @override
  Stream<List<SourceAlbum>> albums({int pageSize = 500}) async* {
    final all = library.keys.toList();
    var page = 0;
    for (var i = 0; i < all.length; i += pageSize) {
      page++;
      if (failAtPage == page) throw const SocketException('cut');
      final chunk = all.skip(i).take(pageSize).toList();
      produced += chunk.length;
      if (produced - processed > maxAlive) maxAlive = produced - processed;
      yield chunk;
    }
  }

  @override
  Future<List<SourceSong>> albumSongs(String albumId) async {
    processed++;
    if (albumId == failSongsOf) throw const SocketException('cut');
    return library.entries.firstWhere((e) => e.key.id == albumId).value;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

SourceAlbum alb(int n) =>
    SourceAlbum(id: 'al$n', name: 'Album $n', artist: 'Art', songCount: 1);
SourceSong song(String id, {String title = 'T', int playCount = 0}) =>
    SourceSong(
      id: id,
      title: title,
      artist: 'Art',
      album: 'Album',
      albumArtist: 'Art',
      coverId: 'c$id',
      suffix: 'mp3',
      replayGainAlbum: -3,
      playCount: playCount,
    );

Map<SourceAlbum, List<SourceSong>> lib3x({
  String? changeTitleOf,
  String? drop,
}) {
  final m = <SourceAlbum, List<SourceSong>>{};
  var n = 0;
  for (var a = 0; a < 3; a++) {
    final songs = <SourceSong>[];
    for (var s = 0; s < (a == 2 ? 6 : 7); s++) {
      final id = 's${n++}';
      if (id == drop) continue;
      songs.add(song(id, title: id == changeTitleOf ? 'New' : 'T'));
    }
    m[alb(a)] = songs;
  }
  return m;
}

void main() {
  late LibraryDb db;
  setUp(() => db = LibraryDb(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<int> count(String acc) async => (await (db.select(
    db.tracks,
  )..where((t) => t.accountId.equals(acc))).get()).length;

  test('first sync stores 20 rows keyed subsonic://acc/id', () async {
    final r = await LibrarySync(db).run(FakeSource('acc1', lib3x()));
    expect((r.added, r.updated, r.removed, r.complete), (20, 0, 0, true));
    final t = await db.trackByPath('subsonic://acc1/s0');
    expect(t!.remoteId, 's0');
    expect(t.accountId, 'acc1');
    expect(t.replayGain, -3); // falls back to album gain
    expect(t.coverId, 'cs0');
    expect(await count('acc1'), 20);
  });

  test('second sync: one gone, one renamed', () async {
    await LibrarySync(db).run(FakeSource('acc1', lib3x()));
    final r = await LibrarySync(db)
        .run(FakeSource('acc1', lib3x(changeTitleOf: 's3', drop: 's9')));
    expect((r.added, r.updated, r.removed, r.complete), (0, 1, 1, true));
    expect(await count('acc1'), 19);
    expect((await db.trackByPath('subsonic://acc1/s3'))!.title, 'New');
  });

  test('server cut at page 2 deletes nothing', () async {
    final big = <SourceAlbum, List<SourceSong>>{
      for (var i = 0; i < 1200; i++) alb(i): [song('x$i')],
    };
    await LibrarySync(db).run(FakeSource('acc1', big));
    expect(await count('acc1'), 1200);
    final r = await LibrarySync(db).run(FakeSource('acc1', big, failAtPage: 2));
    expect(r.complete, isFalse);
    expect(r.removed, 0);
    expect(await count('acc1'), 1200);
  });

  test('a failed run does not delete even tracks it has not seen', () async {
    await LibrarySync(db).run(FakeSource('acc1', lib3x()));
    final r = await LibrarySync(db)
        .run(FakeSource('acc1', lib3x(drop: 's1'), failAtPage: 1));
    expect(r.complete, isFalse);
    expect(await count('acc1'), 20);
  });

  test('1200 albums: at most 500 in memory at once', () async {
    final big = <SourceAlbum, List<SourceSong>>{
      for (var i = 0; i < 1200; i++) alb(i): [song('x$i')],
    };
    final src = FakeSource('acc1', big);
    final r = await LibrarySync(db).run(src);
    expect(r.added, 1200);
    expect(src.maxAlive, lessThanOrEqualTo(500));
  });

  test('other accounts and local tracks are never touched', () async {
    await db.upsertTrack(
      const Track(
        path: '/m/a.flac',
        title: 'l',
        artist: 'l',
        album: 'l',
        durationMs: 1,
        hasCover: false,
        size: 1,
      ),
    );
    await LibrarySync(db).run(FakeSource('acc2', lib3x()));
    final r = await LibrarySync(db).run(FakeSource('acc1', lib3x()));
    expect(r.removed, 0);
    final r2 = await LibrarySync(db).run(
      FakeSource('acc1', {
        alb(0): [song('s0')],
      }),
    );
    expect((r2.removed, r2.complete), (19, true));
    expect(await count('acc2'), 20);
    expect(await count('acc1'), 1);
    expect(await count('local'), 1);
  });

  test('play counts: max of local and server, never decreasing', () async {
    final k = trackKey('acc1', 's0');
    for (var i = 0; i < 3; i++) {
      await db.addPlay(k, DateTime(2026));
    }
    Future<int?> cnt() async => (await (db.select(
      db.playCounts,
    )..where((p) => p.path.equals(k))).getSingleOrNull())?.count;
    Map<SourceAlbum, List<SourceSong>> one(int pc) => {
      alb(0): [song('s0', playCount: pc)],
    };
    await LibrarySync(db).run(FakeSource('acc1', one(12)));
    expect(await cnt(), 12);
    await LibrarySync(db).run(FakeSource('acc1', one(5)));
    expect(await cnt(), 12);
    await LibrarySync(db).run(FakeSource('acc1', one(20)));
    expect(await cnt(), 20);
  });

  test('albumSongs failing on the 3rd album: nothing deleted', () async {
    Map<SourceAlbum, List<SourceSong>> five({String? rename}) => {
      for (var i = 0; i < 5; i++)
        alb(i): [
          song('a$i', title: 'a$i' == rename ? 'New' : 'T'),
          song('b$i'),
        ],
    };
    await LibrarySync(db).run(FakeSource('acc1', five()));
    expect(await count('acc1'), 10);
    // album 0 renamed (before the failure), album 1 song dropped, 3rd fails
    final lib = five(rename: 'a0');
    lib[alb(1)] = [song('a1')];
    final src = FakeSource('acc1', lib, failSongsOf: 'al2');
    final r = await LibrarySync(db).run(src);
    expect((r.complete, r.removed, r.updated), (false, 0, 1));
    expect(await count('acc1'), 10);
    expect((await db.trackByPath('subsonic://acc1/a0'))!.title, 'New');
  });

  test('an empty answer never wipes an account that has tracks', () async {
    await LibrarySync(db).run(FakeSource('acc1', lib3x()));
    await db.addPlay(trackKey('acc1', 's0'), DateTime(2026));
    final r = await LibrarySync(db).run(FakeSource('acc1', {}));
    expect((r.complete, r.removed), (false, 0));
    expect(await count('acc1'), 20);
    expect(await db.select(db.playCounts).get(), hasLength(1));
    // an account with nothing stored yet syncs an empty server normally
    final e = await LibrarySync(db).run(FakeSource('new', {}));
    expect(e.complete, isTrue);
  });

  test('a song listed twice in an album counts once', () async {
    final r = await LibrarySync(db).run(
      FakeSource('acc1', {
        alb(0): [song('s0'), song('s0'), song('s1')],
      }),
    );
    expect(r.added, 2);
  });

  group('kept copies of tracks that leave the server', () {
    late Directory tmp;
    CopyRoot? root; // null: folder unreachable
    setUp(() {
      tmp = Directory.systemTemp.createTempSync('sync');
      root = CopyRoot(tmp.path);
    });
    tearDown(() => tmp.deleteSync(recursive: true));

    LibrarySync syncer() => LibrarySync(db, copyRoot: () async => root);

    Future<void> keep(String id, {String state = 'done', bool file = true}) async {
      final path = trackKey('acc1', id);
      await db.queueOffline([path], OfflineReason.user);
      if (state == 'done') {
        await db.markOfflineDone(path, 'Art/Album/$id.mp3', 3);
        if (file) {
          File('${tmp.path}/Art/Album/$id.mp3')
            ..createSync(recursive: true)
            ..writeAsBytesSync([1, 2, 3]);
        }
      }
    }

    test('a done copy outlives its track: local track, plays follow, row gone', () async {
      await syncer().run(FakeSource('acc1', lib3x()));
      await keep('s3');
      await db.addPlay(trackKey('acc1', 's3'), DateTime(2026));
      final r = await syncer().run(FakeSource('acc1', lib3x(drop: 's3')));
      expect(r.removed, 1);
      expect(await db.trackByPath(trackKey('acc1', 's3')), isNull);
      final abs = '${tmp.path}/Art/Album/s3.mp3';
      final t = (await db.trackByPath(abs))!;
      expect((t.accountId, t.remoteId, t.title, t.album), ('local', '', 'T', 'Album'));
      expect(t.coverId, 'cs3'); // tags and cover fields kept
      expect(t.size, 3);
      expect(await db.offlineOf(trackKey('acc1', 's3')), isNull);
      final plays = await db.select(db.playCounts).get();
      expect([for (final p in plays) p.path], [abs]);
      expect(File(abs).existsSync(), isTrue); // never deleted
    });

    test('queued, failed and file-less rows go with their track', () async {
      await syncer().run(FakeSource('acc1', lib3x()));
      await keep('s1', state: 'queued');
      await keep('s2', state: 'queued');
      await db.markOfflineFailed(trackKey('acc1', 's2'));
      await keep('s4', file: false); // done, but the file was deleted by hand
      await syncer().run(FakeSource('acc1', lib3x(drop: 's1')));
      await syncer().run(FakeSource('acc1', lib3x(drop: 's2')));
      await syncer().run(FakeSource('acc1', lib3x(drop: 's4')));
      expect(await db.select(db.offline).get(), isEmpty);
      expect(await db.select(db.tracks).get().then((l) => l.where((t) => t.accountId == 'local')), isEmpty);
    });

    test('incomplete sync deletes nothing, copies included (R3)', () async {
      await syncer().run(FakeSource('acc1', lib3x()));
      await keep('s3');
      await syncer().run(FakeSource('acc1', {}));
      expect(await db.trackByPath(trackKey('acc1', 's3')), isNotNull);
      expect((await db.offlineOf(trackKey('acc1', 's3')))!.state, 'done');
    });

    test('removing the account: kept copies stay as local tracks', () async {
      await syncer().run(FakeSource('acc1', lib3x()));
      await keep('s3');
      await keep('s5', state: 'queued');
      await db.deleteAccountTracks('acc1', root: CopyRoot(tmp.path));
      expect(await db.trackByPath('${tmp.path}/Art/Album/s3.mp3'), isNotNull);
      expect(await db.select(db.offline).get(), isEmpty);
      expect(
        await db.select(db.tracks).get().then((l) => l.map((t) => t.accountId).toSet()),
        {'local'},
      );
    });

    test('folder unreachable: finished copies, their tracks and plays are left alone', () async {
      await syncer().run(FakeSource('acc1', lib3x()));
      await keep('s3'); // file really exists, but the folder doesn't answer
      await keep('s4', state: 'queued');
      await db.addPlay(trackKey('acc1', 's3'), DateTime(2026));
      root = null;
      await syncer().run(FakeSource('acc1', lib3x(drop: 's3')));
      await syncer().run(FakeSource('acc1', lib3x(drop: 's4')));
      await db.deleteAccountTracks('acc1', root: null);
      expect(await db.trackByPath(trackKey('acc1', 's3')), isNotNull);
      expect((await db.offlineOf(trackKey('acc1', 's3')))!.state, 'done');
      expect(await db.select(db.playCounts).get(), hasLength(1));
      expect(await db.offlineOf(trackKey('acc1', 's4')), isNull); // not done: goes
    });

    test('keyFor names the local track (iPhone: docs://)', () async {
      await syncer().run(FakeSource('acc1', lib3x()));
      await keep('s3');
      root = CopyRoot(tmp.path, (a) async => a.replaceFirst('${tmp.path}/', 'docs://'));
      await syncer().run(FakeSource('acc1', lib3x(drop: 's3')));
      expect((await db.trackByPath('docs://Art/Album/s3.mp3'))!.accountId, 'local');
    });
  });
}
