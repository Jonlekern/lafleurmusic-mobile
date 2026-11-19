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
    expect([for (final (t, _) in top) t.path], ['subsonic://B/b3']);
  });

  test('without settings: every account, merged', () async {
    await twoAccounts();
    final v = LibraryView(db);
    views.add(v);
    expect(paths(await v.allTracks().first), hasLength(3));
  });
}
