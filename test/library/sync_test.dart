import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/library/db.dart';
import 'package:lafleurmusic/library/models.dart';
import 'package:lafleurmusic/library/sync.dart';
import 'package:lafleurmusic/sources/source.dart';

class FakeSource implements MusicSource {
  FakeSource(this.accountId, this.library, {this.failAtPage});
  @override
  final String accountId;
  Map<SourceAlbum, List<SourceSong>> library;
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
    final r2 = await LibrarySync(db).run(FakeSource('acc1', {}));
    expect((r2.removed, r2.complete), (20, true));
    expect(await count('acc2'), 20);
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
}
