import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/library/db.dart';
import 'package:lafleurmusic/library/models.dart';

Track s(String acc, String id, {String title = 'Song', String album = 'Alb'}) =>
    Track(
      path: 'subsonic://$acc/$id',
      accountId: acc,
      remoteId: id,
      title: title,
      artist: 'Art',
      albumArtist: 'Art',
      album: album,
      trackNo: 1,
      durationMs: 1000,
      hasCover: false,
      size: 1,
    );

void main() {
  late LibraryDb db;
  setUp(() async {
    db = LibraryDb(NativeDatabase.memory());
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
  });
  tearDown(() => db.close());

  Future<List<(String, int)>> top() async => [
    for (final r in await db.top(100)) (r.$1.path, r.$2),
  ];

  test('12 on one server, 7 on the other shows 12; a listen makes 13; a '
      'resync does not bring back 12', () async {
    await db.upsertTracks([s('A', '1'), s('B', '1')]);
    await db.raisePlayCounts({'subsonic://A/1': 12, 'subsonic://B/1': 7});
    expect(await top(), [('subsonic://A/1', 12)]);
    await db.addPlay('subsonic://B/1', DateTime(2026, 1, 1));
    expect(await top(), [('subsonic://A/1', 13)]);
    // the server B scrobble comes back: its count is now 8, A still says 12
    await db.raisePlayCounts({'subsonic://A/1': 12, 'subsonic://B/1': 8});
    expect(await top(), [('subsonic://A/1', 13)]);
    // and the same sync again
    await db.raisePlayCounts({'subsonic://A/1': 12, 'subsonic://B/1': 8});
    expect(await top(), [('subsonic://A/1', 13)]);
  });

  test('listens on both twins add up', () async {
    await db.upsertTracks([s('A', '1'), s('B', '1')]);
    await db.raisePlayCounts({'subsonic://A/1': 5});
    await db.addPlay('subsonic://A/1', DateTime(2026, 1, 1));
    await db.addPlay('subsonic://B/1', DateTime(2026, 1, 2));
    expect(await top(), [('subsonic://A/1', 7)]);
  });

  test(
    'Top 100: one rank for two twins, ordered by the merged value',
    () async {
      await db.upsertTracks([
        s('A', '1'),
        s('B', '1'),
        s('A', '2', title: 'Other'),
      ]);
      await db.raisePlayCounts({
        'subsonic://A/1': 4,
        'subsonic://B/1': 4,
        'subsonic://A/2': 6,
      });
      await db.addPlay('subsonic://B/1', DateTime(2026, 1, 1));
      await db.addPlay('subsonic://B/1', DateTime(2026, 1, 2));
      await db.addPlay('subsonic://B/1', DateTime(2026, 1, 3));
      expect(await top(), [('subsonic://A/1', 7), ('subsonic://A/2', 6)]);
    },
  );

  test('the row shown is the one of the merged view', () async {
    await db.upsertTracks([s('A', '1'), s('B', '1')]);
    await db.raisePlayCounts({'subsonic://B/1': 3});
    await db.queueOffline(['subsonic://B/1'], OfflineReason.user);
    await db.markOfflineDone('subsonic://B/1', 'x.mp3', 1);
    expect(await top(), [('subsonic://B/1', 3)]);
  });

  test(
    'display mode: a hidden account still counts, its row is not shown',
    () async {
      await db.upsertTracks([s('A', '1'), s('B', '1')]);
      await db.raisePlayCounts({'subsonic://A/1': 9, 'subsonic://B/1': 2});
      final onlyB = await db.watchTop(100, accounts: {'B'}).first;
      expect(
        [for (final r in onlyB) (r.$1.path, r.$2)],
        [('subsonic://B/1', 9)],
      );
    },
  );

  test('two rows of one account are not merged away', () async {
    await db.upsertTracks([s('A', '1'), s('A', '2')]);
    await db.raisePlayCounts({'subsonic://A/1': 3, 'subsonic://A/2': 5});
    expect(await top(), [('subsonic://A/2', 5), ('subsonic://A/1', 3)]);
  });

  test('eviction order uses the merged value', () async {
    await db.upsertTracks([
      s('A', '1'),
      s('B', '1'),
      s('A', '2', title: 'Other'),
    ]);
    await db.raisePlayCounts({
      'subsonic://A/1': 1,
      'subsonic://B/1': 10,
      'subsonic://A/2': 5,
    });
    await db.queueOffline([
      'subsonic://A/1',
      'subsonic://A/2',
    ], OfflineReason.top100);
    final order = [for (final r in await db.top100ByLeastPlayed()) r.trackPath];
    expect(order, ['subsonic://A/2', 'subsonic://A/1']); // A/1 is worth 10
  });
}
