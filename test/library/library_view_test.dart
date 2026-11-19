import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/library/db.dart';
import 'package:lafleurmusic/library/library_view.dart';
import 'package:lafleurmusic/library/merge.dart';
import 'package:lafleurmusic/library/models.dart';
import 'package:lafleurmusic/settings.dart';

/// A song of [acc] ('local' = a file on the phone).
Track tr(
  String acc,
  String id, {
  String title = 'One',
  int? no = 1,
  String album = 'Summer Mix',
  String albumArtist = 'Lafleur Surf',
  String artist = 'Lafleur Surf',
}) => Track(
  path: acc == 'local' ? '/m/$id.mp3' : 'subsonic://$acc/$id',
  accountId: acc,
  remoteId: acc == 'local' ? '' : id,
  title: title,
  artist: artist,
  albumArtist: albumArtist,
  album: album,
  trackNo: no,
  durationMs: 1000,
  hasCover: false,
  size: 1,
);

void main() {
  late LibraryDb db;
  late List<LibraryView> views;
  setUp(() {
    db = LibraryDb(NativeDatabase.memory());
    views = [];
  });
  tearDown(() async {
    for (final v in views) {
      await v.dispose();
    }
    await db.close();
  });

  Future<void> account(String id, int position) => db
      .into(db.accountRows)
      .insertOnConflictUpdate(
        AccountRowsCompanion.insert(
          id: id,
          type: 'subsonic',
          name: id,
          base: 'https://music.example.com',
          user: 'u',
          position: position,
        ),
      );

  LibraryView view([AppSettings? settings]) {
    final v = LibraryView(db, settings: settings ?? AppSettings());
    views.add(v);
    return v;
  }

  List<String> paths(List<Track> l) => [for (final t in l) t.path];

  /// The same album on A and B; B has one more song.
  Future<void> twoAccounts() async {
    await account('A', 0);
    await account('B', 1);
    await db.upsertTracks([
      tr('A', 'a1'),
      tr('A', 'a2', title: 'Two', no: 2),
      tr('B', 'b1'),
      tr('B', 'b2', title: 'Two', no: 2),
      tr('B', 'b3', title: 'Three', no: 3),
    ]);
  }

  test('same album on A and B: shown once, one row per song, from the first account', () async {
    await twoAccounts();
    final v = view();
    final albums = await v.albums().first;
    expect(albums, hasLength(1));
    expect(albums.single.name, 'Summer Mix');
    expect(albums.single.trackCount, 3);
    expect(albums.single.durationMs, 3000);
    expect(paths(await v.albumTracks(albums.single.key).first), [
      'subsonic://A/a1',
      'subsonic://A/a2',
      'subsonic://B/b3',
    ]);
    expect(paths(await v.allTracks().first), hasLength(3));
    expect(await v.artists().first, [('Lafleur Surf', 3)]);
    expect(paths(await v.search('two')), ['subsonic://A/a2']);
  });

  test('the account order of screen 6 picks the row', () async {
    await twoAccounts();
    await account('A', 1);
    await account('B', 0);
    final v = view();
    final key = (await v.albums().first).single.key;
    expect(paths(await v.albumTracks(key).first), [
      'subsonic://B/b1',
      'subsonic://B/b2',
      'subsonic://B/b3',
    ]);
  });

  test('a kept copy on B is the row shown', () async {
    await twoAccounts();
    await db.queueOffline(['subsonic://B/b1'], OfflineReason.user);
    await db.markOfflineDone('subsonic://B/b1', 'L/S/01 One.mp3', 1);
    final v = view();
    final key = (await v.albums().first).single.key;
    expect(paths(await v.albumTracks(key).first), [
      'subsonic://B/b1',
      'subsonic://A/a2',
      'subsonic://B/b3',
    ]);
  });

  test(
    'mode One account: only A (+ local files); Custom: the checked ones',
    () async {
      await twoAccounts();
      await db.upsertTracks([tr('local', 'x', title: 'Hand placed', no: 9)]);
      final settings = AppSettings(
        displayMode: DisplayMode.one,
        oneAccount: 'A',
      );
      final v = view(settings);
      final seen = <List<String>>[];
      final sub = v.allTracks().listen((l) => seen.add(paths(l)..sort()));
      await pumpEventQueue();
      expect(seen.last, ['/m/x.mp3', 'subsonic://A/a1', 'subsonic://A/a2']);
      expect(v.visibleAccounts, {'A'});

      settings
        ..displayMode = DisplayMode.custom
        ..customAccounts = ['B'];
      v.settingsChanged();
      await pumpEventQueue();
      expect(seen.last, [
        '/m/x.mp3',
        'subsonic://B/b1',
        'subsonic://B/b2',
        'subsonic://B/b3',
      ]);
      expect(v.visibleAccounts, {'B'});

      settings.customAccounts = [];
      v.settingsChanged();
      await pumpEventQueue();
      expect(seen.last, ['/m/x.mp3'], reason: 'local files: always shown');
      await sub.cancel();
    },
  );

  test('two rows of one account with the same tags: both shown, '
      'each paired with one of the other account', () async {
    await account('A', 0);
    await account('B', 1);
    await db.upsertTracks([tr('A', 'a1'), tr('A', 'a2'), tr('B', 'b1')]);
    final v = view();
    expect(paths(await v.allTracks().first)..sort(), [
      'subsonic://A/a1',
      'subsonic://A/a2',
    ]);
    expect(paths(await db.twinsOf('subsonic://A/a2')), [
      'subsonic://A/a2',
      'subsonic://B/b1',
    ]);
  });

  test('a copy kept on a hidden account: the row shown is kept, '
      'its album too', () async {
    await twoAccounts();
    for (final p in ['subsonic://A/a1', 'subsonic://A/a2']) {
      await db.queueOffline([p], OfflineReason.user);
      await db.markOfflineDone(p, 'f$p', 1);
    }
    await db.upsertTracks([tr('A', 'a3', title: 'Three', no: 3)]);
    await db.queueOffline(['subsonic://A/a3'], OfflineReason.user);
    await db.markOfflineDone('subsonic://A/a3', 'fa3', 1);
    final v = view(AppSettings(displayMode: DisplayMode.one, oneAccount: 'B'));
    final album = (await v.albums().first).single;
    expect(paths(await v.albumTracks(album.key).first), [
      'subsonic://B/b1',
      'subsonic://B/b2',
      'subsonic://B/b3',
    ]);
    expect(await v.keptAlbums().first, {album.key});
    final rows = await db.watchOfflineWithTwins().first;
    expect(rows['subsonic://B/b1']?.trackPath, 'subsonic://A/a1');
  });

  test('part of an album placed by hand, the rest on Navidrome: one album, '
      'the files win for their songs (Q5b)', () async {
    await twoAccounts();
    await db.upsertTracks([
      tr('local', 'x', albumArtist: '', title: 'two', no: 2), // song 2
      tr(
        'local',
        'y',
        albumArtist: '',
        title: 'Bonus',
        no: 9,
      ), // not on the server
    ]);
    final v = view();
    final albums = await v.albums().first;
    expect(albums, hasLength(1));
    expect(paths(await v.albumTracks(albums.single.key).first), [
      'subsonic://A/a1',
      '/m/x.mp3',
      'subsonic://B/b3',
      '/m/y.mp3',
    ]);
    // the server album goes: the files are their own album again
    await db.deletePaths([
      for (final p in ['a1', 'a2']) 'subsonic://A/$p',
      for (final p in ['b1', 'b2', 'b3']) 'subsonic://B/$p',
    ]);
    final alone = await v.albums().first;
    expect(alone.single.key, albumMergeKey(tr('local', 'x', albumArtist: '')));
    expect(alone.single.trackCount, 2);
  });

  test(
    'files placed by hand (no disc) sort among the server songs (disc 1)',
    () async {
      await account('A', 0);
      Track s(int no, {String acc = 'A'}) => Track(
        path: acc == 'local' ? '/m/$no.mp3' : 'subsonic://A/$no',
        accountId: acc,
        title: 'S$no',
        artist: 'X',
        albumArtist: acc == 'local' ? '' : 'X',
        album: 'Alb',
        disc: acc == 'local' ? null : 1,
        trackNo: no,
        durationMs: 1,
        hasCover: false,
        size: 1,
      );
      await db.upsertTracks([
        for (final n in [1, 3, 4, 5, 6, 7, 8, 9, 10]) s(n),
        s(2, acc: 'local'), // not on the server
        s(3, acc: 'local'), // stands in for the server's song 3
      ]);
      final v = view();
      final album = (await v.albums().first).single;
      expect(
        [for (final t in await v.albumTracks(album.key).first) t.path],
        [
          'subsonic://A/1',
          '/m/2.mp3',
          '/m/3.mp3',
          for (var n = 4; n <= 10; n++) 'subsonic://A/$n',
        ],
      );
    },
  );

  test('the server album renamed: the files placed by hand leave it', () async {
    await twoAccounts();
    await db.upsertTracks([
      tr('local', 'x', albumArtist: '', title: 'Bonus', no: 9),
      tr('local', 'y', albumArtist: '', title: 'One', no: 1, artist: 'Other'),
    ]);
    expect(await view().albums().first, hasLength(1));
    await db.upsertTracks([
      for (final (acc, id, title, no) in [
        ('A', 'a1', 'One', 1),
        ('A', 'a2', 'Two', 2),
        ('B', 'b1', 'One', 1),
        ('B', 'b2', 'Two', 2),
        ('B', 'b3', 'Three', 3),
      ])
        tr(acc, id, title: title, no: no, album: 'Winter Mix'),
    ]);
    final albums = await view().albums().first;
    expect(albums.map((a) => a.name).toSet(), {'Summer Mix', 'Winter Mix'});
    expect(
      albums.firstWhere((a) => a.name == 'Summer Mix').key,
      albumMergeKey(tr('local', 'x', albumArtist: '')),
    );
  });

  test(
    'a local album of the same name with no common song stays apart',
    () async {
      await twoAccounts();
      await db.upsertTracks([
        tr('local', 'x', albumArtist: '', title: 'Other', no: 5),
      ]);
      expect(await view().albums().first, hasLength(2));
    },
  );

  test('album lists: by disc, then number', () async {
    await account('A', 0);
    Track d(String id, int? disc, int? no) => Track(
      path: 'subsonic://A/$id',
      accountId: 'A',
      title: id,
      artist: 'x',
      albumArtist: 'x',
      album: 'Double',
      disc: disc,
      trackNo: no,
      durationMs: 1,
      hasCover: false,
      size: 1,
    );
    await db.upsertTracks([d('d2t1', 2, 1), d('d1t2', 1, 2), d('d1t1', 1, 1)]);
    final v = view();
    final key = (await v.albums().first).single.key;
    expect(
      [for (final t in await v.albumTracks(key).first) t.title],
      ['d1t1', 'd1t2', 'd2t1'],
    );
    expect(
      [for (final t in await v.artistTracks('x').first) t.title],
      ['d1t1', 'd1t2', 'd2t1'],
    );
  });

  test('mode One with no account chosen: the first account', () async {
    await twoAccounts();
    final v = view(AppSettings(displayMode: DisplayMode.one));
    await v.allTracks().first;
    expect(v.visibleAccounts, {'A'});
  });

  test('a hand-placed file of the same song is the row shown; '
      'two local files are never merged', () async {
    await twoAccounts();
    await db.upsertTracks([
      tr('local', 'x', albumArtist: ''),
      tr('local', 'y', albumArtist: ''),
    ]);
    final v = view();
    final all = paths(await v.allTracks().first)..sort();
    expect(all, ['/m/x.mp3', '/m/y.mp3', 'subsonic://A/a2', 'subsonic://B/b3']);
  });

  test('same album name by two album artists: two albums; '
      'accents, case and spaces: one', () async {
    await account('A', 0);
    await account('B', 1);
    await db.upsertTracks([
      tr('A', 'a1', album: 'Lemonade', albumArtist: 'Beyoncé'),
      tr('B', 'b1', album: 'lemonade', albumArtist: 'Beyonce'),
      tr('B', 'b2', album: 'Lemonade', albumArtist: 'Someone  Else'),
    ]);
    final albums = await view().albums().first;
    expect(albums, hasLength(2));
    expect([for (final a in albums) a.trackCount]..sort(), [1, 1]);
    expect(albums.map((a) => a.key).toSet(), {
      albumMergeKey(tr('A', 'a1', album: 'Lemonade', albumArtist: 'Beyoncé')),
      albumMergeKey(
        tr('B', 'b2', album: 'Lemonade', albumArtist: 'someone else'),
      ),
    });
  });

  test(
    'local files without album artist (compiled albums) stay one album',
    () async {
      await db.upsertTracks([
        tr('local', 'x', albumArtist: '', artist: 'One', album: 'Mix'),
        tr('local', 'y', albumArtist: '', artist: 'Two', album: 'Mix', no: 2),
      ]);
      final albums = await view().albums().first;
      expect(albums.single.trackCount, 2);
    },
  );

  test('kept albums: every server row shown has its copy', () async {
    await twoAccounts();
    final v = view();
    final key = (await v.albums().first).single.key;
    expect(await v.keptAlbums().first, isEmpty);
    for (final p in ['subsonic://B/b1', 'subsonic://B/b2', 'subsonic://B/b3']) {
      await db.queueOffline([p], OfflineReason.user);
      await db.markOfflineDone(p, 'f$p', 1);
    }
    expect(await v.keptAlbums().first, {key});
  });

  test('twinsOf: every row of the song, local first then account order; '
      'not a removed account', () async {
    await twoAccounts();
    await db.upsertTracks([tr('gone', 'g1'), tr('local', 'x')]);
    expect(paths(await db.twinsOf('subsonic://B/b1')), [
      '/m/x.mp3',
      'subsonic://A/a1',
      'subsonic://B/b1',
    ]);
    expect(paths(await db.twinsOf('subsonic://B/b3')), ['subsonic://B/b3']);
  });

  test('Top 100: only the accounts shown (+ local)', () async {
    await twoAccounts();
    await db.addPlay('subsonic://A/a1', DateTime(2026));
    await db.addPlay('subsonic://B/b3', DateTime(2026));
    final v = view(AppSettings(displayMode: DisplayMode.one, oneAccount: 'B'));
    final top = await v.top(100).first;
    // only B's rows are shown; the listen on A counts for b1, A's twin of it
    expect([for (final (t, _) in top) t.path], [
      'subsonic://B/b1',
      'subsonic://B/b3',
    ]);
  });

  test('without settings: every account, merged', () async {
    await twoAccounts();
    final v = LibraryView(db);
    views.add(v);
    expect(paths(await v.allTracks().first), hasLength(3));
  });
}
