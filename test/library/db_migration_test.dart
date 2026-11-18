import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/library/db.dart';
import 'package:lafleurmusic/library/models.dart';
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

void main() {
  test('a v1 database upgrades to v3 and keeps its data', () async {
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
    expect((await db.select(db.playCounts).get()).single.count, 3);

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
  });

  test('a v2 database upgrades to v3 and keeps its offline rows', () async {
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
  });
}
