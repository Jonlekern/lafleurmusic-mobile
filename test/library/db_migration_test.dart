import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/library/db.dart';
import 'package:lafleurmusic/library/merge.dart';
import 'package:lafleurmusic/library/models.dart';
import 'package:lafleurmusic/offline/device.dart';
import 'package:lafleurmusic/offline/downloader.dart';
import 'package:lafleurmusic/player/media_resolver.dart';
import 'package:lafleurmusic/settings.dart';
import 'package:sqlite3/sqlite3.dart';

// Schéma v1 de la 0.1.0 (commit ae39106), table par table.
const _v1 = [
  'CREATE TABLE "tracks" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "path" TEXT NOT NULL UNIQUE, "folder_id" INTEGER NOT NULL DEFAULT 0, "account_id" TEXT NOT NULL DEFAULT \'local\', "remote_id" TEXT NOT NULL DEFAULT \'\', "album_artist" TEXT NOT NULL DEFAULT \'\', "disc" INTEGER NULL, "cover_id" TEXT NULL, "suffix" TEXT NULL, "replay_gain" REAL NULL, "title" TEXT NOT NULL, "artist" TEXT NOT NULL, "album" TEXT NOT NULL, "album_key" TEXT NOT NULL, "genre" TEXT NOT NULL DEFAULT \'\', "track_no" INTEGER NULL, "duration_ms" INTEGER NOT NULL, "has_cover" INTEGER NOT NULL CHECK ("has_cover" IN (0, 1)), "mtime" INTEGER NOT NULL DEFAULT 0, "size" INTEGER NOT NULL, "missing" INTEGER NOT NULL DEFAULT 0 CHECK ("missing" IN (0, 1)), "to_repair" INTEGER NOT NULL DEFAULT 0 CHECK ("to_repair" IN (0, 1)), "search_key" TEXT NOT NULL)',
  'CREATE TABLE "play_counts" ("path" TEXT NOT NULL, "count" INTEGER NOT NULL, "last_played" INTEGER NOT NULL, PRIMARY KEY ("path"))',
  'CREATE TABLE "loudness" ("path" TEXT NOT NULL, "lufs" REAL NULL, "mtime" INTEGER NOT NULL, PRIMARY KEY ("path"))',
  'CREATE TABLE "accounts" ("id" TEXT NOT NULL, "type" TEXT NOT NULL, "name" TEXT NOT NULL, "base" TEXT NOT NULL, "user" TEXT NOT NULL, "position" INTEGER NOT NULL, PRIMARY KEY ("id"))',
];

// Les tables ajoutées par la v2 (copies hors ligne, écoutes en attente).
const _v2 = [
  'CREATE TABLE "offline" ("track_path" TEXT NOT NULL, "file_path" TEXT NULL, "size" INTEGER NOT NULL DEFAULT 0, "added_at" INTEGER NOT NULL, "reason" TEXT NOT NULL, "state" TEXT NOT NULL, "failures" INTEGER NOT NULL DEFAULT 0, PRIMARY KEY ("track_path"))',
  'CREATE TABLE "pending_scrobbles" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "account_id" TEXT NOT NULL, "remote_id" TEXT NOT NULL, "at" INTEGER NOT NULL)',
];

// La table ajoutée par la v3 (morceaux retirés du Top 100), plan 2.
const _v3 = [
  'CREATE TABLE "auto_keep_blocks" ("track_path" TEXT NOT NULL, PRIMARY KEY ("track_path"))',
];

/// Ce que la v4 doit offrir, quelle que soit la version de départ.
Future<void> _expectV4(LibraryDb db) async {
  // clé de fusion recalculée pour les morceaux existants, et indexée
  final rows = await db.select(db.tracks).get();
  for (final r in rows) {
    final t = Track(
      path: r.path,
      title: r.title,
      artist: r.artist,
      albumArtist: r.albumArtist,
      album: r.album,
      trackNo: r.trackNo,
      durationMs: r.durationMs,
      hasCover: r.hasCover,
      size: r.size,
    );
    expect(r.mergeKey, mergeKey(t));
    expect(r.mergeKey, isNotEmpty);
    expect(r.albumMergeKey, albumMergeKey(t));
    expect(r.albumMergeKey, isNotEmpty);
  }
  final idx = await db
      .customSelect(
        "SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = 'tracks'",
      )
      .get();
  expect(
    idx.map((i) => i.read<String>('name')),
    containsAll(['tracks_merge_key', 'tracks_album_merge_key']),
  );
  // les tables nouvelles existent, vides, et servent
  expect(await db.select(db.playlists).get(), isEmpty);
  expect(await db.select(db.playlistItems).get(), isEmpty);
  expect(await db.select(db.keptPlaylists).get(), isEmpty);
  await db
      .into(db.playlists)
      .insert(
        PlaylistsCompanion.insert(
          accountId: 'acc',
          remoteId: 'pl1',
          name: 'Road',
          position: 0,
        ),
      );
  await db
      .into(db.playlistItems)
      .insert(
        PlaylistItemsCompanion.insert(
          accountId: 'acc',
          playlistId: 'pl1',
          index: 0,
          trackPath: 'subsonic://acc/1',
        ),
      );
  await db
      .into(db.keptPlaylists)
      .insert(
        KeptPlaylistsCompanion.insert(
          accountId: 'acc',
          playlistId: 'pl1',
          fileName: 'Road.m3u8',
        ),
      );
  expect((await db.select(db.playlists).getSingle()).name, 'Road');
  expect((await db.select(db.keptPlaylists).getSingle()).fileName, 'Road.m3u8');
}

void main() {
  test(
    'a v4 database upgrades to v5: added_at backfilled, nothing lost',
    () async {
      final dir = Directory.systemTemp.createTempSync('mig5');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/lib.db');
      // a fresh database, then taken back to what 0.4.0 wrote (no added_at, version 4)
      final first = LibraryDb(NativeDatabase(file));
      await first.customSelect('SELECT 1').get();
      await first.close();
      final raw = sqlite3.open(file.path);
      raw.execute('ALTER TABLE tracks DROP COLUMN added_at');
      raw.execute(
        "INSERT INTO accounts VALUES ('acc', 'subsonic', 'Home', 'http://h', 'u', 0)",
      );
      raw.execute(
        "INSERT INTO tracks (path, account_id, remote_id, title, artist, album, album_key, duration_ms, has_cover, mtime, size, search_key, merge_key, album_merge_key) "
        "VALUES ('subsonic://acc/1', 'acc', '1', 'T', 'a', 'A', 'a', 1000, 1, 0, 5, 'k', 'm1', 'g1')",
      );
      raw.execute(
        "INSERT INTO tracks (path, title, artist, album, album_key, duration_ms, has_cover, mtime, size, search_key, merge_key, album_merge_key) "
        "VALUES ('/m/1.flac', 'L', 'a', 'A', 'a', 1000, 0, 123456, 5, 'k', 'm2', 'g1')",
      );
      raw.execute(
        "INSERT INTO play_counts VALUES ('subsonic://acc/1', 2, 3, 99)",
      );
      raw.execute(
        "INSERT INTO offline VALUES ('subsonic://acc/1', 'A/a.mp3', 5, 1, 'user', 'done', 0)",
      );
      raw.execute(
        "INSERT INTO playlists (account_id, remote_id, name, position) VALUES ('acc', 'pl1', 'Road', 0)",
      );
      raw.execute('PRAGMA user_version = 4');
      raw.close();

      final before = DateTime.now().millisecondsSinceEpoch;
      final db = LibraryDb(NativeDatabase(file));
      addTearDown(db.close);
      final rows = {
        for (final r in await db.select(db.tracks).get()) r.path: r.addedAt,
      };
      expect(rows['/m/1.flac'], 123456); // the file date when known
      expect(
        rows['subsonic://acc/1'],
        greaterThanOrEqualTo(before),
      ); // else the upgrade
      final plays = (await db.select(db.playCounts).get()).single;
      expect((plays.count, plays.imported, plays.lastPlayed), (2, 3, 99));
      expect((await db.offlineOf('subsonic://acc/1'))!.state, 'done');
      expect((await db.select(db.playlists).getSingle()).name, 'Road');
      expect(await db.select(db.accountRows).get(), hasLength(1));
    },
  );

  test('a v1 database upgrades to v5 and keeps its data', () async {
    final raw = sqlite3.openInMemory();
    for (final sql in _v1) {
      raw.execute(sql);
    }
    raw.execute(
      "INSERT INTO accounts VALUES ('acc', 'subsonic', 'Home', 'http://h', 'u', 0)",
    );
    for (final id in ['1', '2']) {
      raw.execute(
        "INSERT INTO tracks (path, account_id, remote_id, title, artist, album, album_key, duration_ms, has_cover, size, search_key) "
        "VALUES ('subsonic://acc/$id', 'acc', '$id', 't$id', 'a', 'A', 'a', 1000, 1, 5, 'k')",
      );
    }
    raw.execute("INSERT INTO play_counts VALUES ('subsonic://acc/1', 3, 7)");
    raw.execute('PRAGMA user_version = 1');

    final db = LibraryDb(NativeDatabase.opened(raw));
    addTearDown(db.close);

    expect((await db.select(db.accountRows).get()).single.id, 'acc');
    expect(await db.select(db.tracks).get(), hasLength(2));
    // les écoutes venues du serveur passent dans `imported`, `count` repart de 0
    final plays = (await db.select(db.playCounts).get()).single;
    expect((plays.imported, plays.count, plays.lastPlayed), (3, 0, 7));

    // les tables v2 existent, vides, et servent
    expect(await db.select(db.offline).get(), isEmpty);
    expect(await db.select(db.pendingScrobbles).get(), isEmpty);
    await db.queueOffline(['subsonic://acc/1'], OfflineReason.user);
    await db.addPending('acc', '1', DateTime.fromMillisecondsSinceEpoch(9));
    expect((await db.offlineOf('subsonic://acc/1'))!.state, 'queued');
    expect((await db.pending('acc')).single.remoteId, '1');

    // la table v3 existe, vide, et sert
    expect(await db.autoKeepBlocked(), isEmpty);
    await db.blockAutoKeep(['subsonic://acc/1']);
    expect(await db.autoKeepBlocked(), {'subsonic://acc/1'});
    await _expectV4(db);
  });

  test('a v2 database upgrades to v5 and keeps its offline rows', () async {
    final raw = sqlite3.openInMemory();
    for (final sql in [..._v1, ..._v2]) {
      raw.execute(sql);
    }
    raw.execute(
      "INSERT INTO offline VALUES ('subsonic://acc/1', 'A/a.mp3', 5, 1, 'top100', 'done', 0)",
    );
    raw.execute("INSERT INTO pending_scrobbles VALUES (1, 'acc', '1', 9)");
    raw.execute('PRAGMA user_version = 2');

    final db = LibraryDb(NativeDatabase.opened(raw));
    addTearDown(db.close);

    expect((await db.offlineOf('subsonic://acc/1'))!.reason, 'top100');
    expect((await db.pending('acc')).single.remoteId, '1');
    expect(await db.autoKeepBlocked(), isEmpty);
    await db.blockAutoKeep(['subsonic://acc/1', 'subsonic://acc/1']);
    expect(await db.autoKeepBlocked(), {'subsonic://acc/1'});
    await db.unblockAutoKeep(['subsonic://acc/1']);
    expect(await db.autoKeepBlocked(), isEmpty);
    await _expectV4(db);
  });

  test('a v3 database (0.2.0) upgrades to v5 and keeps everything', () async {
    final raw = sqlite3.openInMemory();
    for (final sql in [..._v1, ..._v2, ..._v3]) {
      raw.execute(sql);
    }
    raw.execute(
      "INSERT INTO accounts VALUES ('acc', 'subsonic', 'Home', 'http://h', 'u', 0)",
    );
    raw.execute(
      "INSERT INTO tracks (path, account_id, remote_id, album_artist, title, artist, album, album_key, track_no, duration_ms, has_cover, size, search_key) "
      "VALUES ('subsonic://acc/1', 'acc', '1', 'Beyoncé', 'Été', 'a', 'Café', 'cafe', 4, 1000, 1, 5, 'k')",
    );
    raw.execute(
      "INSERT INTO tracks (path, title, artist, album, album_key, duration_ms, has_cover, size, search_key) "
      "VALUES ('/m/1.flac', 'Local', 'a', 'Café', 'cafe', 1000, 0, 5, 'k')",
    );
    raw.execute("INSERT INTO play_counts VALUES ('subsonic://acc/1', 12, 99)");
    raw.execute("INSERT INTO play_counts VALUES ('/m/1.flac', 2, 50)");
    raw.execute(
      "INSERT INTO offline VALUES ('subsonic://acc/1', 'A/a.mp3', 5, 1, 'user', 'done', 0)",
    );
    raw.execute("INSERT INTO pending_scrobbles VALUES (1, 'acc', '1', 9)");
    raw.execute("INSERT INTO auto_keep_blocks VALUES ('subsonic://acc/2')");
    raw.execute('PRAGMA user_version = 3');

    final db = LibraryDb(NativeDatabase.opened(raw));
    addTearDown(db.close);

    final keys = {
      for (final r in await db.select(db.tracks).get()) r.path: r.mergeKey,
    };
    expect(keys['subsonic://acc/1'], 'beyonce\u0000cafe\u0000ete\u00004');
    expect(
      keys['/m/1.flac'],
      'a\u0000cafe\u0000local\u0000',
    ); // no album artist: the artist
    expect(await db.select(db.tracks).get(), hasLength(2));
    final plays = {
      for (final p in await db.select(db.playCounts).get())
        p.path: (p.imported, p.count, p.lastPlayed),
    };
    expect(plays, {'subsonic://acc/1': (12, 0, 99), '/m/1.flac': (2, 0, 50)});
    final kept = (await db.offlineOf('subsonic://acc/1'))!;
    expect(
      (kept.filePath, kept.reason, kept.state),
      ('A/a.mp3', 'user', 'done'),
    );
    expect((await db.pending('acc')).single.remoteId, '1');
    expect(await db.autoKeepBlocked(), {'subsonic://acc/2'});
    // a user copy from 0.2.0: its reason is unknown (an album or the song itself)
    expect(await db.originsOf('subsonic://acc/1'), {KeepOrigin.legacy});
    await _expectV4(db);
  });

  test('a 0.2.0 album kept whole can be removed by album after the upgrade, '
      'unless the song was kept for itself since', () async {
    final raw = sqlite3.openInMemory();
    for (final sql in [..._v1, ..._v2, ..._v3]) {
      raw.execute(sql);
    }
    raw.execute(
      "INSERT INTO accounts VALUES ('acc', 'subsonic', 'Home', 'http://h', 'u', 0)",
    );
    for (final id in ['1', '2', '3']) {
      raw.execute(
        "INSERT INTO tracks (path, account_id, remote_id, album_artist, title, artist, album, album_key, track_no, duration_ms, has_cover, size, search_key) "
        "VALUES ('subsonic://acc/$id', 'acc', '$id', 'Art', 't$id', 'Art', 'Alb', 'alb', $id, 1000, 1, 4, 'k')",
      );
      raw.execute(
        "INSERT INTO offline VALUES ('subsonic://acc/$id', 'Art/Alb/0$id.mp3', 4, $id, 'user', 'done', 0)",
      );
    }
    raw.execute('PRAGMA user_version = 3');
    final tmp = Directory.systemTemp.createTempSync('mig');
    addTearDown(() => tmp.deleteSync(recursive: true));
    for (final id in ['1', '2', '3']) {
      File('${tmp.path}/Art/Alb/0$id.mp3')
        ..createSync(recursive: true)
        ..writeAsBytesSync([1, 2, 3, 4]);
    }

    final db = LibraryDb(NativeDatabase.opened(raw));
    addTearDown(db.close);
    final d = Downloader(
      db: db,
      resolver: MediaResolver((_) async => throw StateError('no network')),
      device: _Device(tmp),
      settings: () async => AppSettings(),
    );
    final t1 = (await db.trackByPath('subsonic://acc/1'))!;
    final album = KeepOrigin.albumOf(t1);
    const paths = ['subsonic://acc/1', 'subsonic://acc/2', 'subsonic://acc/3'];
    // the user kept song 3 for itself after the upgrade: it stays
    await db.addOrigins({'subsonic://acc/3': KeepOrigin.song});
    expect(await d.toForgetFrom(album, paths), [
      'subsonic://acc/1',
      'subsonic://acc/2',
    ]);
    await d.forgetFrom(album, paths);
    expect(await db.offlineOf('subsonic://acc/1'), isNull);
    expect(await db.offlineOf('subsonic://acc/2'), isNull);
    expect(File('${tmp.path}/Art/Alb/01.mp3').existsSync(), isFalse);
    expect((await db.offlineOf('subsonic://acc/3'))!.state, 'done');
    expect(File('${tmp.path}/Art/Alb/03.mp3').existsSync(), isTrue);
  });

  test('a migration cut in the middle leaves the database as it was: the '
      'next launch upgrades it', () async {
    final raw = sqlite3.openInMemory();
    for (final sql in [..._v1, ..._v2, ..._v3]) {
      raw.execute(sql);
    }
    raw.execute(
      "INSERT INTO tracks (path, title, artist, album, album_key, duration_ms, has_cover, size, search_key) "
      "VALUES ('/m/1.flac', 'Local', 'a', 'Café', 'cafe', 1000, 0, 5, 'k')",
    );
    raw.execute("INSERT INTO play_counts VALUES ('/m/1.flac', 2, 50)");
    raw.execute(
      "INSERT INTO offline VALUES ('subsonic://acc/1', 'A/a.mp3', 5, 1, 'user', 'done', 0)",
    );
    // the app is killed after the first columns are added
    raw.execute(
      'CREATE TRIGGER cut BEFORE UPDATE ON play_counts '
      "BEGIN SELECT RAISE(ABORT, 'killed'); END",
    );
    raw.execute('PRAGMA user_version = 3');

    final first = LibraryDb(
      NativeDatabase.opened(raw, closeUnderlyingOnClose: false),
    );
    await expectLater(first.select(first.tracks).get(), throwsA(anything));
    await first.close();
    raw.execute('DROP TRIGGER cut');

    final db = LibraryDb(NativeDatabase.opened(raw));
    addTearDown(db.close);
    final plays = (await db.select(db.playCounts).get()).single;
    expect((plays.imported, plays.count, plays.lastPlayed), (2, 0, 50));
    expect(await db.originsOf('subsonic://acc/1'), {KeepOrigin.legacy});
    await _expectV4(db);
  });
}

class _Device implements Device {
  _Device(this.root);
  final Directory root;
  @override
  Future<Directory> musicRoot() async => root;
  @override
  Future<bool> rootReachable() async => true;
  @override
  Future<void> announce(String path) async {}
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}
