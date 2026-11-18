import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/library/db.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('base du plan 1 (sans genre) : mise à niveau sans perte', () async {
    final dir = Directory.systemTemp.createTempSync('mig');
    final f = File('${dir.path}/library.sqlite');
    final raw = sqlite3.open(f.path);
    raw.execute(
      '''CREATE TABLE tracks (id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, path TEXT NOT NULL UNIQUE,
      folder_id INTEGER NOT NULL, title TEXT NOT NULL, artist TEXT NOT NULL, album TEXT NOT NULL, album_key TEXT NOT NULL,
      track_no INTEGER NULL, duration_ms INTEGER NOT NULL, has_cover INTEGER NOT NULL, mtime INTEGER NOT NULL,
      size INTEGER NOT NULL, missing INTEGER NOT NULL DEFAULT 0, to_repair INTEGER NOT NULL DEFAULT 0, search_key TEXT NOT NULL)''',
    );
    raw.execute(
      "INSERT INTO tracks (path, folder_id, title, artist, album, album_key, duration_ms, has_cover, mtime, size, search_key) "
      "VALUES ('/m/a.flac', 1, 'Ocean Drive', 'Johnny', 'Studio', 'studio', 1, 1, 1, 1, 'ocean')",
    );
    raw.execute('PRAGMA user_version = 1');
    raw.close();
    final db = LibraryDb(NativeDatabase(f));
    final tracks = await db.watchAlbumTracks('Studio').first;
    expect(tracks.single.title, 'Ocean Drive');
    expect(tracks.single.genre, '');
    // date remise à zéro : le prochain scan relit chaque fichier et remplit les genres
    expect((await db.trackByPath('/m/a.flac'))!.mtime, 0);
    await db.close();
    dir.deleteSync(recursive: true);
  });

  test(
    'base du plan 2 (schéma 2) : écoutes et mesures ajoutées sans perte',
    () async {
      final dir = Directory.systemTemp.createTempSync('mig3');
      final f = File('${dir.path}/library.sqlite');
      final raw = sqlite3.open(f.path);
      raw.execute('''CREATE TABLE tracks (id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, path TEXT NOT NULL UNIQUE,
      folder_id INTEGER NOT NULL, title TEXT NOT NULL, artist TEXT NOT NULL, album TEXT NOT NULL, album_key TEXT NOT NULL,
      genre TEXT NOT NULL DEFAULT '', track_no INTEGER NULL, duration_ms INTEGER NOT NULL, has_cover INTEGER NOT NULL,
      mtime INTEGER NOT NULL, size INTEGER NOT NULL, missing INTEGER NOT NULL DEFAULT 0, to_repair INTEGER NOT NULL DEFAULT 0,
      search_key TEXT NOT NULL)''');
      raw.execute(
        "INSERT INTO tracks (path, folder_id, title, artist, album, album_key, genre, duration_ms, has_cover, mtime, size, search_key) "
        "VALUES ('/m/a.flac', 1, 'Ocean Drive', 'Johnny', 'Studio', 'studio', 'Rock', 1, 1, 7, 1, 'ocean')",
      );
      raw.execute('PRAGMA user_version = 2');
      raw.close();
      final db = LibraryDb(NativeDatabase(f));
      final tr = await db.trackByPath('/m/a.flac');
      expect(tr!.genre, 'Rock');
      expect(tr.mtime, 7); // pas de rescan forcé
      expect(await db.watchTop(10).first, isEmpty);
      await db.addPlay('/m/a.flac', DateTime(2026));
      expect((await db.watchTop(10).first).single.$2, 1);
      await db.close();
      dir.deleteSync(recursive: true);
    },
  );
}
