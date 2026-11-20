import 'dart:io';

import 'package:drift/drift.dart' show TableUpdateQuery;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/library/db.dart';
import 'package:lafleurmusic/library/library_view.dart';
import 'package:lafleurmusic/library/models.dart';
import 'package:lafleurmusic/library/playlist_store.dart';
import 'package:lafleurmusic/settings.dart';
import 'package:lafleurmusic/sources/jellyfin.dart';
import 'package:lafleurmusic/sources/plex.dart';
import 'package:lafleurmusic/sources/source.dart';
import 'package:lafleurmusic/sources/subsonic.dart';

import '../sources/fake_playlist_servers.dart';
import '../sources/fake_secret_store.dart';

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

    test('a kept playlist of files put by hand shows as kept (a local song '
        'needs no copy)', () async {
      await db.upsertTracks([_t('/music/a.mp3'), _t('/music/b.mp3')]);
      final ref = await store.create(
        'Mine',
        songs: ['/music/a.mp3', '/music/b.mp3'],
      ) as PhonePlaylistRef;
      expect((await db.watchPlaylists().first).single.kept, isFalse);
      await db.addKeptPlaylist(phonePlaylistAccount, '${ref.id}');
      expect((await db.watchPlaylists().first).single.kept, isTrue);
    });

    test('a kept playlist of files put by hand has no song « missing a copy » '
        '(each sync would try to keep them for nothing)', () async {
      await db.upsertTracks([_t('/music/a.mp3')]);
      final ref = await store.create(
        'Mine',
        songs: ['/music/a.mp3'],
      ) as PhonePlaylistRef;
      await db.addKeptPlaylist(phonePlaylistAccount, '${ref.id}');
      expect(await db.keptPlaylistsMissing(), isEmpty);
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

    test('remove by position with a song twice: only that row goes', () async {
      await db.upsertTracks([
        for (final n in [1, 2]) _t('/m/$n.flac', title: 't$n'),
      ]);
      final ref = await store.create('Road');
      await store.add(ref, [
        '/m/1.flac',
        '/m/2.flac',
        '/m/1.flac',
      ], allowDuplicates: true);
      await store.remove(ref, [2]);
      expect(await keys(ref), ['/m/1.flac', '/m/2.flac']);
    });

    test(
      'reorder: the rows in the order given (a sort), duplicates kept',
      () async {
        await db.upsertTracks([
          for (final n in [1, 2, 3]) _t('/m/$n.flac', title: 't$n'),
        ]);
        final ref = await store.create('Road');
        await store.add(ref, [
          '/m/1.flac',
          '/m/2.flac',
          '/m/3.flac',
          '/m/1.flac',
        ], allowDuplicates: true);
        await store.reorder(ref, [3, 2, 0, 1]);
        expect(await keys(ref), [
          '/m/1.flac',
          '/m/3.flac',
          '/m/1.flac',
          '/m/2.flac',
        ]);
        // not a permutation of the rows: refused, nothing changed
        await expectLater(store.reorder(ref, [0, 1]), throwsArgumentError);
        await expectLater(
          store.reorder(ref, [0, 0, 1, 2]),
          throwsArgumentError,
        );
        expect(await keys(ref), hasLength(4));
      },
    );

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

  test('a phone playlist is named and read like a server one (what the '
      '.m3u8 files use); deleted, it is no longer named', () async {
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

  group('server playlists (task 2)', () {
    late FakeNavidrome nav;
    late SubsonicSource sub;
    late PlaylistStore srv;
    const acc = 'acc1';
    String k(String id) => 'subsonic://$acc/$id';
    final ref = PlaylistRef.server(acc, 'pl1');

    setUp(() async {
      nav = FakeNavidrome();
      sub = SubsonicSource(
        accountId: acc,
        base: Uri.parse('https://music.example.com'),
        user: 'johnny',
        password: 'pw-secret',
        client: nav.client(),
        salt: () => 'abc',
      );
      srv = PlaylistStore(
        db,
        supportDir: () async => support,
        sourceOf: (id) async =>
            id == acc ? sub : throw StateError('no account $id'),
      );
      await db.upsertTracks([
        for (final id in ['s1', 's2', 's3', 's4'])
          _t(k(id), title: 'song $id', account: acc),
      ]);
      // what plan 3's sync stored
      await db.replacePlaylists(acc, [
        (id: 'pl1', name: 'Road', paths: [k('s1'), k('s2'), k('s3')]),
      ]);
    });

    Future<List<String>> stored(String id) => db.playlistPaths(acc, id);

    test(
      'create on the server: stored as the sync would, after the others',
      () async {
        final r = await srv.create(' Soirée ', accountId: acc);
        expect(r, PlaylistRef.server(acc, 'pl10'));
        expect(nav.lists['pl10']!.name, 'Soirée');
        final lists = await db.playlistsOf(acc);
        expect(lists.map((l) => (l.id, l.name)), [
          ('pl1', 'Road'),
          ('pl10', 'Soirée'),
        ]);
        expect(await stored('pl10'), isEmpty);
      },
    );

    test('add: sent to the server, then read back from it (the server has '
        'the last word)', () async {
      // someone else added s3 again on the server meanwhile
      nav.lists['pl1'] = (name: 'Road', songs: ['s1', 's2', 's3', 's3']);
      expect(await srv.add(ref, [k('s4')]), 1);
      expect(nav.lists['pl1']!.songs, ['s1', 's2', 's3', 's3', 's4']);
      expect(await stored('pl1'), [
        k('s1'),
        k('s2'),
        k('s3'),
        k('s3'),
        k('s4'),
      ]);
    });

    test('add: a song already there is skipped unless asked; the same song '
        'on the phone is sent as this server\'s copy; a song the server does '
        'not have is left out', () async {
      await db.upsertTracks([
        _t('/m/s4.flac', title: 'song s4'), // the twin of s4
        _t('/m/other.flac', title: 'only here'),
      ]);
      expect(await srv.duplicatesIn(ref, [k('s2'), k('s4')]), [k('s2')]);
      expect(await srv.add(ref, [k('s2'), '/m/s4.flac', '/m/other.flac']), 1);
      expect(nav.lists['pl1']!.songs, ['s1', 's2', 's3', 's4']);
      expect(await srv.add(ref, [k('s1')], allowDuplicates: true), 1);
      expect(nav.lists['pl1']!.songs, ['s1', 's2', 's3', 's4', 's1']);
      expect((await stored('pl1')).last, k('s1'));
    });

    test('remove, move, rename, delete: the server changes, the stored '
        'playlist follows (and so does a kept .m3u8)', () async {
      await srv.move(ref, 0, 2);
      expect(await stored('pl1'), [k('s2'), k('s3'), k('s1')]);
      await srv.remove(ref, [1, 9]);
      expect(nav.lists['pl1']!.songs, ['s2', 's1']);
      expect(await stored('pl1'), [k('s2'), k('s1')]);
      await srv.rename(ref, 'Route');
      expect(await db.playlistName(acc, 'pl1'), 'Route');
      await expectLater(srv.move(ref, 0, 5), throwsRangeError);
      await srv.delete(ref);
      expect(nav.lists, isEmpty);
      expect(await db.playlistName(acc, 'pl1'), isNull);
      expect(await stored('pl1'), isEmpty);
    });

    test('review focus 2: the server unreachable during an add: a clear '
        'error, nothing added here, and trying again works', () async {
      nav.down = true;
      await expectLater(
        srv.add(ref, [k('s4')]),
        throwsA(
          isA<PlaylistWriteException>()
              .having((e) => e.problem, 'problem', PlaylistProblem.unreachable)
              .having((e) => e.accountId, 'account', acc),
        ),
      );
      expect(await stored('pl1'), [k('s1'), k('s2'), k('s3')]);
      expect(srv.readOnlyAccounts.value, isEmpty);
      nav.down = false;
      expect(await srv.add(ref, [k('s4')]), 1);
      expect(await stored('pl1'), [k('s1'), k('s2'), k('s3'), k('s4')]);
    });

    test('create with songs the server does not have: nothing is created, '
        'a clear error', () async {
      await expectLater(
        srv.create('Soirée', accountId: acc, songs: ['jellyfin://jf/1']),
        throwsA(
          isA<PlaylistWriteException>().having(
            (e) => e.problem,
            'problem',
            PlaylistProblem.notThere,
          ),
        ),
      );
      expect(nav.lists.keys, ['pl1']);
      expect(await db.playlistsOf(acc), hasLength(1));
    });

    test('reorder: a song added while the order waits its turn: « changed », '
        'nothing written, no song lost', () async {
      nav.delay = const Duration(milliseconds: 20);
      final adding = srv.add(ref, [k('s4')]);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final sorting = srv.reorder(ref, [2, 1, 0]); // made from the 3 rows seen
      await adding;
      await expectLater(
        sorting,
        throwsA(
          isA<PlaylistWriteException>().having(
            (e) => e.problem,
            'problem',
            PlaylistProblem.changed,
          ),
        ),
      );
      expect(nav.lists['pl1']!.songs, ['s1', 's2', 's3', 's4']);
    });

    test('reorder (a sort): the server gets the new order, the stored '
        'playlist follows', () async {
      nav.lists['pl1'] = (name: 'Road', songs: ['s1', 's2', 's3', 's4']);
      expect(await srv.checkEditable(ref), isTrue); // read again: 4 rows
      await srv.reorder(ref, [3, 1, 0, 2]);
      expect(nav.lists['pl1']!.songs, ['s4', 's2', 's1', 's3']);
      expect(await stored('pl1'), [k('s4'), k('s2'), k('s1'), k('s3')]);
    });

    test('Subsonic: a sort of 20 songs is one write (the whole order), then '
        'read back', () async {
      final ids = [for (var i = 1; i <= 20; i++) 'z$i'];
      await db.upsertTracks([
        for (final id in ids) _t(k(id), title: id, account: acc),
      ]);
      nav.lists['pl1'] = (name: 'Road', songs: [...ids]);
      expect(await srv.checkEditable(ref), isTrue);
      nav.log.clear();
      final order = [for (var i = 19; i >= 0; i--) i];
      await srv.reorder(ref, order);
      final writes = [
        for (final r in nav.log)
          if (r.url.path.contains('createPlaylist') ||
              r.url.path.contains('updatePlaylist'))
            r,
      ];
      expect(writes, hasLength(1));
      expect(nav.lists['pl1']!.songs, ids.reversed.toList());
      expect(await stored('pl1'), [for (final id in ids.reversed) k(id)]);
    });

    test('Subsonic: a sort too long for the address (no form POST): '
        '« tooLong », nothing changed', () async {
      nav.maxUrl = 100000;
      final ids = [for (var i = 1; i <= 700; i++) 'song-number-$i'];
      await db.upsertTracks([
        for (final id in ids) _t(k(id), title: id, account: acc),
      ]);
      nav.lists['pl1'] = (name: 'Road', songs: [...ids]);
      expect(await srv.checkEditable(ref), isTrue);
      await expectLater(
        srv.reorder(ref, [for (var i = 699; i >= 0; i--) i]),
        throwsA(
          isA<PlaylistWriteException>().having(
            (e) => e.problem,
            'problem',
            PlaylistProblem.tooLong,
          ),
        ),
      );
      expect(nav.lists['pl1']!.songs, ids);
    });

    test('an account whose server refused a creation still edits its own '
        'playlists (writes: true)', () async {
      nav.readOnly = true;
      await expectLater(
        srv.create('New', accountId: acc),
        throwsA(isA<PlaylistWriteException>()),
      );
      nav.readOnly = false;
      expect(await srv.canWrite(acc), isFalse); // not offered to create
      expect(await srv.writes(acc), isTrue);
      expect(await srv.checkEditable(ref), isTrue);
    });

    test('checkEditable writes nothing when the server has the same '
        'playlist', () async {
      expect(await srv.checkEditable(ref), isTrue); // stores the read
      var writes = 0;
      final sub = db
          .tableUpdates(
            TableUpdateQuery.allOf([
              TableUpdateQuery.onTable(db.playlists),
              TableUpdateQuery.onTable(db.playlistItems),
            ]),
          )
          .listen((_) => writes++);
      addTearDown(sub.cancel);
      expect(await srv.checkEditable(ref), isTrue);
      await pumpEventQueue();
      expect(writes, 0);
      nav.lists['pl1'] = (name: 'Road', songs: ['s1']);
      expect(await srv.checkEditable(ref), isTrue);
      await pumpEventQueue();
      expect(writes, greaterThan(0));
      expect(await stored('pl1'), [k('s1')]);
    });

    test('review focus 4: quick reorders go one at a time; the final order '
        'is the right one', () async {
      nav.delay = const Duration(milliseconds: 5);
      // each move reads the list then writes it whole: run together they'd lose moves
      final moves = [
        srv.move(ref, 0, 2), // s2 s3 s1
        srv.move(ref, 2, 0), // s1 s2 s3
        srv.move(ref, 1, 2), // s1 s3 s2
        srv.move(ref, 0, 1), // s3 s1 s2
      ];
      await Future.wait(moves);
      expect(nav.lists['pl1']!.songs, ['s3', 's1', 's2']);
      expect(await stored('pl1'), [k('s3'), k('s1'), k('s2')]);
      expect(nav.maxInFlight, 1);
    });

    test(
      'a failed action does not block the next ones on that playlist',
      () async {
        nav.refuseNext = 1;
        final failed = srv.move(ref, 0, 1);
        final next = srv.move(ref, 0, 2);
        await expectLater(failed, throwsA(isA<PlaylistWriteException>()));
        await next;
        expect(nav.lists['pl1']!.songs, ['s2', 's3', 's1']);
        expect(await stored('pl1'), [k('s2'), k('s3'), k('s1')]);
      },
    );

    test('another user\'s playlist refuses a change (error 50): that '
        'playlist only becomes read-only; the account still offered', () async {
      nav.foreign = {'pl1'};
      expect(await srv.canWrite(acc), isTrue);
      await expectLater(
        srv.add(ref, [k('s4')]),
        throwsA(
          isA<PlaylistWriteException>().having(
            (e) => e.problem,
            'problem',
            PlaylistProblem.refused,
          ),
        ),
      );
      expect(await stored('pl1'), [k('s1'), k('s2'), k('s3')]);
      expect(srv.readOnlyPlaylists.value, {ref});
      expect(srv.canEdit(ref), isFalse);
      expect(srv.readOnlyAccounts.value, isEmpty);
      expect(await srv.canWrite(acc), isTrue);
      final mine = await srv.create('Mine', accountId: acc);
      expect(srv.canEdit(mine), isTrue);
      await srv.add(mine, [k('s4')]);
      expect(nav.lists['pl10']!.songs, ['s4']);
    });

    test('known up front: a playlist the server says is someone else\'s or '
        'readonly is read-only once read', () async {
      nav.readonlyFlag = {'pl1'};
      expect(await srv.checkEditable(ref), isFalse);
      expect(srv.canEdit(ref), isFalse);
      nav.readonlyFlag = {};
      expect(await srv.checkEditable(ref), isTrue);
      expect(srv.canEdit(ref), isTrue);
      nav.foreign = {'pl1'};
      expect(await srv.checkEditable(ref), isFalse);
    });

    test('create refused (error 50): the account is no longer offered to keep '
        'a new playlist, until a creation works', () async {
      nav.readOnly = true;
      await expectLater(
        srv.create('X', accountId: acc),
        throwsA(
          isA<PlaylistWriteException>().having(
            (e) => e.problem,
            'problem',
            PlaylistProblem.refused,
          ),
        ),
      );
      expect((await db.playlistsOf(acc)).map((l) => l.id), ['pl1']);
      expect(srv.readOnlyAccounts.value, {acc});
      expect(await srv.canWrite(acc), isFalse);
      nav.readOnly = false;
      await srv.create('Y', accountId: acc);
      expect(srv.readOnlyAccounts.value, isEmpty);
    });

    test(
      'create with songs, the add after the creation fails: the new playlist '
      'is stored, the error names it, the account stays offered',
      () async {
        nav.refuseUpdate = true;
        Object? err;
        try {
          await srv.create('Mix', accountId: acc, songs: [k('s1'), k('s2')]);
        } on PlaylistWriteException catch (e) {
          err = e;
        }
        expect(err, isA<PlaylistWriteException>());
        final e = err as PlaylistWriteException;
        expect(e.problem, PlaylistProblem.refused);
        expect(e.created, PlaylistRef.server(acc, 'pl10'));
        expect(nav.lists.keys.where((i) => nav.lists[i]!.name == 'Mix'), [
          'pl10',
        ]);
        expect((await db.playlistsOf(acc)).map((l) => l.id), ['pl1', 'pl10']);
        expect(srv.readOnlyAccounts.value, isEmpty);
        expect(await srv.canWrite(acc), isTrue);
      },
    );

    test('a refusal mark on a playlist stays after a re-read that says '
        'editable, until a write on it works', () async {
      nav.refuseNext = 1;
      await expectLater(
        srv.add(ref, [k('s4')]),
        throwsA(isA<PlaylistWriteException>()),
      );
      expect(srv.canEdit(ref), isFalse);
      expect(await srv.checkEditable(ref), isFalse);
      await srv.add(ref, [k('s4')]);
      expect(srv.canEdit(ref), isTrue);
    });

    test('the answer to an add is lost after the server did it: the playlist '
        'is read again, so trying again does not add it twice', () async {
      nav.lostAnswers = 1;
      await expectLater(
        srv.add(ref, [k('s4')]),
        throwsA(
          isA<PlaylistWriteException>().having(
            (e) => e.problem,
            'problem',
            PlaylistProblem.unreachable,
          ),
        ),
      );
      expect(await stored('pl1'), [k('s1'), k('s2'), k('s3'), k('s4')]);
      expect(await srv.add(ref, [k('s4')]), 0);
      expect(nav.lists['pl1']!.songs, ['s1', 's2', 's3', 's4']);
    });

    test('the playlist changed on the server meanwhile: « changed », read '
        'again, nothing moved', () async {
      nav.lists['pl1'] = (name: 'Road', songs: ['s2', 's1', 's3']);
      await expectLater(
        srv.move(ref, 0, 2), // we still see s1 first
        throwsA(
          isA<PlaylistWriteException>().having(
            (e) => e.problem,
            'problem',
            PlaylistProblem.changed,
          ),
        ),
      );
      expect(nav.lists['pl1']!.songs, ['s2', 's1', 's3']);
      expect(await stored('pl1'), [k('s2'), k('s1'), k('s3')]);
      await expectLater(
        srv.remove(ref, [1]),
        completes,
        reason: 'now the same list',
      );
      expect(nav.lists['pl1']!.songs, ['s2', 's3']);
    });

    test('create with songs: on the server at once (this server\'s copies); on '
        'the phone too', () async {
      await db.upsertTrack(_t('/m/s4.flac', title: 'song s4'));
      final r = await srv.create(
        'Mix',
        accountId: acc,
        songs: [k('s2'), '/m/s4.flac'],
      );
      expect(nav.lists[(r as ServerPlaylistRef).remoteId]!.songs, ['s2', 's4']);
      expect(await stored(r.remoteId), [k('s2'), k('s4')]);
      final p = await srv.create('Here', songs: ['/m/s4.flac', k('s2')]);
      expect(await keys(p), ['/m/s4.flac', k('s2')]);
    });

    test('a source that cannot write: refused, never offered', () async {
      final ro = PlaylistStore(db, sourceOf: (_) async => _ReadOnlySource());
      expect(await ro.canWrite(acc), isFalse);
      await expectLater(
        ro.add(ref, [k('s4')]),
        throwsA(
          isA<PlaylistWriteException>().having(
            (e) => e.problem,
            'problem',
            PlaylistProblem.refused,
          ),
        ),
      );
      expect(await ro.canWrite('unknown'), isFalse);
      expect(await store.canWrite(acc), isFalse, reason: 'no sources at all');
    });

    test('Jellyfin: create and add store jellyfin:// keys', () async {
      final jf = FakeJellyfin();
      final src = JellyfinSource(
        accountId: 'jf',
        base: Uri.parse('http://jf.example:8096'),
        user: 'max',
        password: 'pw-secret',
        client: jf.client(),
        secrets: FakeSecretStore(),
      );
      final s = PlaylistStore(db, sourceOf: (_) async => src);
      final r = await s.create('Jazz', accountId: 'jf');
      await s.add(r, ['jellyfin://jf/a1', 'jellyfin://jf/a2']);
      await s.move(r, 1, 0);
      expect(jf.songs('pl10'), ['a2', 'a1']);
      expect(await db.playlistPaths('jf', 'pl10'), [
        'jellyfin://jf/a2',
        'jellyfin://jf/a1',
      ]);
    });

    test('Plex: create and add store plex:// keys', () async {
      PlexSource.resetStateForTests();
      final px = FakePlexPlaylists();
      final s = PlaylistStore(db, sourceOf: (_) async => px.source());
      final r = await s.create(
        'Rock',
        accountId: 'acc1',
        songs: ['plex://acc1/101'],
      );
      await s.add(r, ['plex://acc1/102']);
      await s.remove(r, [1]);
      await s.add(r, ['plex://acc1/101', 'plex://acc1/102']);
      await s.remove(r, [0]);
      expect(px.songs('910'), ['102']);
      expect(await db.playlistPaths('acc1', '910'), ['plex://acc1/102']);
    });

    test('Plex: never an empty creation (a playlist needs a song of that '
        'server), nothing sent', () async {
      PlexSource.resetStateForTests();
      final px = FakePlexPlaylists();
      final before = px.lists.length;
      final s = PlaylistStore(db, sourceOf: (_) async => px.source());
      for (final songs in [
        const <String>[],
        ['subsonic://other/1'],
      ]) {
        await expectLater(
          s.create('Rock', accountId: 'acc1', songs: songs),
          throwsA(
            isA<PlaylistWriteException>().having(
              (e) => e.problem,
              'problem',
              PlaylistProblem.notThere,
            ),
          ),
        );
      }
      expect(px.lists.length, before);
      expect(px.log.where((r) => r.method != 'GET'), isEmpty);
    });
  });
}

/// A source of an account that can't write playlists (no [PlaylistWriter]).
class _ReadOnlySource implements MusicSource {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}
