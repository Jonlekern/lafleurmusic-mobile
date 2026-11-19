import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/library/db.dart';
import 'package:lafleurmusic/library/library_view.dart';
import 'package:lafleurmusic/library/models.dart';
import 'package:lafleurmusic/library/playlist_store.dart';
import 'package:lafleurmusic/settings.dart';

Track _t(
  String path, {
  String title = 'x',
  String account = 'local',
  String artist = 'a',
}) => Track(
  path: path,
  accountId: account,
  remoteId: account == 'local' ? '' : path.split('/').last,
  title: title,
  artist: artist,
  album: 'A',
  durationMs: 1000,
  hasCover: false,
  mtime: 1,
  size: 1,
);

void main() {
  late LibraryDb db;
  late Directory support;
  late PlaylistStore store;

  setUp(() {
    db = LibraryDb(NativeDatabase.memory());
    support = Directory.systemTemp.createTempSync('pl_store');
    store = PlaylistStore(db, supportDir: () async => support);
  });
  tearDown(() async {
    await db.close();
    support.deleteSync(recursive: true);
  });

  Future<List<String>> keys(PlaylistRef ref) async => [
    for (final (k, _) in await store.items(ref).first) k,
  ];

  group('no account at all', () {
    test('create: a phone playlist, listed with the others', () async {
      final ref = await store.create('  Soirée ');
      expect(ref, isA<PhonePlaylistRef>());
      expect(ref, PlaylistRef.phone((ref as PhonePlaylistRef).id));
      final lists = await db.watchPlaylists().first;
      expect(lists, hasLength(1));
      final p = lists.single;
      expect(
        (p.name, p.songCount, p.onPhone, p.kept),
        ('Soirée', 0, true, false),
      );
      expect(p.ref, ref);
      // the app's view, no account: phone playlists still shown
      final view = LibraryView(db, settings: AppSettings());
      addTearDown(view.dispose);
      expect((await view.playlists().first).map((p) => p.name), ['Soirée']);
    });

    test('create: an empty name is refused', () async {
      await expectLater(store.create('   '), throwsArgumentError);
      expect(await db.watchPlaylists().first, isEmpty);
    });

    test('add keeps the order; a song already there is skipped unless '
        'asked', () async {
      await db.upsertTracks([
        _t('/m/1.flac', title: 'one'),
        _t('/m/2.flac', title: 'two'),
        _t('/m/3.flac', title: 'three'),
      ]);
      final ref = await store.create('Road');
      await store.add(ref, ['/m/2.flac', '/m/1.flac']);
      expect(await keys(ref), ['/m/2.flac', '/m/1.flac']);
      expect(await store.duplicatesIn(ref, ['/m/1.flac', '/m/3.flac']), [
        '/m/1.flac',
      ]);
      await store.add(ref, ['/m/1.flac', '/m/3.flac', '/m/3.flac']);
      expect(await keys(ref), ['/m/2.flac', '/m/1.flac', '/m/3.flac']);
      await store.add(ref, ['/m/1.flac'], allowDuplicates: true);
      expect(await keys(ref), [
        '/m/2.flac',
        '/m/1.flac',
        '/m/3.flac',
        '/m/1.flac',
      ]);
      final items = await store.items(ref).first;
      expect(items.map((i) => i.$2?.title), ['two', 'one', 'three', 'one']);
      expect((await db.watchPlaylists().first).single.songCount, 4);
    });

    test('a twin (same song elsewhere) counts as already there', () async {
      await db.upsertTracks([
        _t('/m/1.flac', title: 'one'),
        _t('subsonic://acc/1', title: 'one', account: 'acc'),
      ]);
      final ref = await store.create('Road');
      await store.add(ref, ['/m/1.flac']);
      expect(await store.duplicatesIn(ref, ['subsonic://acc/1']), [
        'subsonic://acc/1',
      ]);
    });

    test('remove, move, rename', () async {
      await db.upsertTracks([
        for (final n in [1, 2, 3, 4]) _t('/m/$n.flac', title: 't$n'),
      ]);
      final ref = await store.create('Road');
      await store.add(ref, [
        for (final n in [1, 2, 3, 4]) '/m/$n.flac',
      ]);
      await store.remove(ref, [0, 2]);
      expect(await keys(ref), ['/m/2.flac', '/m/4.flac']);
      await store.add(ref, ['/m/1.flac', '/m/3.flac']);
      // 2 4 1 3 → the first goes to the end
      await store.move(ref, 0, 3);
      expect(await keys(ref), [
        '/m/4.flac',
        '/m/1.flac',
        '/m/3.flac',
        '/m/2.flac',
      ]);
      await store.move(ref, 2, 0);
      expect(await keys(ref), [
        '/m/3.flac',
        '/m/4.flac',
        '/m/1.flac',
        '/m/2.flac',
      ]);
      await store.rename(ref, 'Trip');
      expect((await db.watchPlaylists().first).single.name, 'Trip');
      await expectLater(store.rename(ref, ' '), throwsArgumentError);
      await expectLater(store.move(ref, 0, 9), throwsRangeError);
    });

    test('setCover keeps a copy in the app folder; delete takes it all '
        'away', () async {
      final ref = await store.create('Road');
      await db.upsertTrack(_t('/m/1.flac'));
      await store.add(ref, ['/m/1.flac']);
      final picked = File('${support.path}/picked.jpg')
        ..writeAsBytesSync([1, 2, 3]);
      await store.setCover(ref, picked);
      final first = (await store.coverOf(ref))!;
      expect(first.path, startsWith(support.path));
      expect(first.path, isNot(picked.path));
      expect(first.readAsBytesSync(), [1, 2, 3]);
      picked.writeAsBytesSync([4, 5]);
      await store.setCover(ref, picked);
      final second = (await store.coverOf(ref))!;
      expect(second.readAsBytesSync(), [4, 5]);
      expect(first.existsSync(), isFalse, reason: 'the old copy goes');
      await store.delete(ref);
      expect(await db.watchPlaylists().first, isEmpty);
      expect(await store.items(ref).first, isEmpty);
      expect(second.existsSync(), isFalse);
      expect(picked.existsSync(), isTrue, reason: 'the picked photo stays');
    });

    test('phone playlists come after the server ones, by name, whatever '
        'accounts are shown', () async {
      await store.create('zèbre');
      await store.create('Été');
      await store.create('dub');
      final names = [
        for (final p in await db.watchPlaylists(accounts: {}).first) p.name,
      ];
      expect(names, ['dub', 'Été', 'zèbre']);
    });
  });

  group('review focus 3: a server song whose account is removed', () {
    test('the row stays, absent; never deleted', () async {
      await db
          .into(db.accountRows)
          .insert(
            AccountRowsCompanion.insert(
              id: 'acc',
              type: 'subsonic',
              name: 'Maison',
              base: 'http://h',
              user: 'u',
              position: 0,
            ),
          );
      await db.upsertTracks([
        _t('/m/1.flac', title: 'local'),
        _t('subsonic://acc/7', title: 'server', account: 'acc'),
      ]);
      final ref = await store.create('Mix');
      await store.add(ref, ['subsonic://acc/7', '/m/1.flac']);
      // the account goes (no copy kept)
      await db.deleteAccountTracks('acc', root: null);
      await db.deleteAccountPlaylists('acc');
      await (db.delete(db.accountRows)..where((a) => a.id.equals('acc'))).go();
      final items = await store.items(ref).first;
      expect(items.map((i) => i.$1), ['subsonic://acc/7', '/m/1.flac']);
      expect(items.first.$2, isNull, reason: 'shown greyed « Morceau absent »');
      expect(items.last.$2?.title, 'local');
      expect((await db.watchPlaylists().first).single.songCount, 2);
    });

    test('the same song on another account (or the phone) plays in its '
        'place; the stored key stays', () async {
      await db.upsertTracks([
        _t('subsonic://acc/7', title: 'song', account: 'acc'),
      ]);
      final ref = await store.create('Mix');
      await store.add(ref, ['subsonic://acc/7']);
      // the account goes; its kept copy became a local file
      await db.deleteAccountTracks('acc', root: null);
      await db.upsertTrack(_t('/m/song.flac', title: 'song'));
      final items = await store.items(ref).first;
      expect(items.single.$1, 'subsonic://acc/7');
      expect(items.single.$2?.path, '/m/song.flac');
      expect(
        await db.playlistPaths('phone', '${(ref as PhonePlaylistRef).id}'),
        ['/m/song.flac'],
      );
    });
  });

  test('a kept phone playlist reads like a server one (its .m3u8)', () async {
    await db.upsertTrack(_t('/m/1.flac'));
    final ref = await store.create('Road') as PhonePlaylistRef;
    await store.add(ref, ['/m/1.flac']);
    expect(await db.playlistName(phonePlaylistAccount, '${ref.id}'), 'Road');
    expect(await db.playlistPaths(phonePlaylistAccount, '${ref.id}'), [
      '/m/1.flac',
    ]);
    await store.delete(ref);
    // gone: the .m3u8 files drop it like a playlist the server no longer has
    expect(await db.playlistName(phonePlaylistAccount, '${ref.id}'), isNull);
  });
}
