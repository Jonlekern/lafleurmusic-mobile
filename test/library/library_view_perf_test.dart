import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/library/db.dart';
import 'package:lafleurmusic/library/library_view.dart';
import 'package:lafleurmusic/library/merge.dart';
import 'package:lafleurmusic/library/models.dart';
import 'package:lafleurmusic/settings.dart';

/// Measured on the Mac (see the task-2 report); the bound leaves room for slower CI machines.
const _bound = Duration(milliseconds: 1500);

void main() {
  test('20 000 tracks on 2 accounts: Home albums, kept albums, an album '
      'screen stay fast', () async {
    final db = LibraryDb(NativeDatabase.memory());
    addTearDown(db.close);
    for (final (i, id) in ['A', 'B'].indexed) {
      await db
          .into(db.accountRows)
          .insert(
            AccountRowsCompanion.insert(
              id: id,
              type: 'subsonic',
              name: id,
              base: 'https://music.example.com',
              user: 'u',
              position: i,
            ),
          );
    }
    // 1000 albums of 10 songs, on A and on B (B's album artist spelled differently)
    for (final acc in ['A', 'B']) {
      await db.upsertTracks([
        for (var a = 0; a < 1000; a++)
          for (var n = 1; n <= 10; n++)
            Track(
              path: 'subsonic://$acc/$a-$n',
              accountId: acc,
              remoteId: '$a-$n',
              title: 'Song $n',
              artist: 'Artist ${a % 300}',
              albumArtist: acc == 'A'
                  ? 'Artist ${a % 300}'
                  : 'artist  ${a % 300}',
              album: 'Album $a',
              genre: 'G${a % 20}',
              trackNo: n,
              durationMs: 1000,
              hasCover: false,
              size: 1,
            ),
      ]);
    }
    final kept = [
      for (var a = 0; a < 50; a++)
        for (var n = 1; n <= 10; n++) 'subsonic://B/$a-$n',
    ];
    await db.queueOffline(kept, OfflineReason.user);
    for (final p in kept) {
      await db.markOfflineDone(p, p, 1);
    }
    // listens: 2000 songs known by both servers (twins), the app played some of them
    await db.raisePlayCounts({
      for (var a = 0; a < 200; a++)
        for (var n = 1; n <= 10; n++) ...{
          'subsonic://A/$a-$n': 1 + (a * n) % 40,
          'subsonic://B/$a-$n': 1 + (a + n) % 40,
        },
    });
    for (var i = 0; i < 100; i++) {
      await db.addPlay('subsonic://B/${i % 200}-${1 + i % 10}', DateTime(2026));
    }
    final v = LibraryView(db, settings: AppSettings());
    addTearDown(v.dispose);
    Future<(T, Duration)> time<T>(Future<T> Function() f) async {
      final w = Stopwatch()..start();
      final r = await f();
      return (r, w.elapsed);
    }

    await v.genres().first; // view ready (accounts read), no list cached
    final (albums, tAlbums) = await time(() => v.albums().first);
    final (keptAlbums, tKept) = await time(() => v.keptAlbums().first);
    final (tracks, tAlbum) = await time(
      () => v.albumTracks(albums[500].key).first,
    );
    final (_, tAll) = await time(() => v.allTracks().first);
    final (top, tTop) = await time(() => v.top(100).first);
    expect(top, hasLength(100));
    expect({for (final r in top) mergeKey(r.$1)}, hasLength(100)); // one rank per song
    final (_, tLeast) = await time(() => db.top100ByLeastPlayed());
    final (_, tArtist) = await time(() => v.artistTracks('Artist 7').first);
    expect(albums, hasLength(1000));
    expect(keptAlbums, hasLength(50));
    expect(tracks, hasLength(10));
    printOnFailure(
      'albums $tAlbums, kept $tKept, album $tAlbum, all $tAll, artist $tArtist, top $tTop, least $tLeast',
    );
    for (final t in [tAlbums, tKept, tAlbum, tArtist, tAll, tTop, tLeast]) {
      expect(t, lessThan(_bound));
    }
  });
}
