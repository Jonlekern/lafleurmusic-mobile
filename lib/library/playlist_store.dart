import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'db.dart';
import 'models.dart';

export 'models.dart'
    show
        PlaylistRef,
        PhonePlaylistRef,
        ServerPlaylistRef,
        ServerPlaylist,
        phonePlaylistAccount;

/// The one place that changes playlists, whatever their kind (plan 9). A phone playlist
/// ([PlaylistRef.phone]) lives in this database only and works with no account at all; its
/// songs are named by their key (`subsonic://…`, `jellyfin://…`, `plex://…` or a local path),
/// in order, a song twice only when asked. Server playlists: read-only until their writer
/// comes (task 2).
class PlaylistStore {
  /// [supportDir]: the app support folder (the chosen covers go in it); by default the
  /// system's.
  PlaylistStore(this.db, {Future<Directory> Function()? supportDir})
    : _supportDir = supportDir ?? getApplicationSupportDirectory;

  final LibraryDb db;
  final Future<Directory> Function() _supportDir;

  static const coverFolder = 'playlist_covers';

  /// A new empty playlist named [name] (spaces around it dropped; empty: refused). Without
  /// [accountId] (or with [phonePlaylistAccount]): on the phone.
  Future<PlaylistRef> create(String name, {String? accountId}) async {
    final n = _name(name);
    if (accountId != null && accountId != phonePlaylistAccount) {
      throw _readOnly(PlaylistRef.server(accountId, ''));
    }
    final id = await db
        .into(db.phonePlaylists)
        .insert(
          PhonePlaylistsCompanion.insert(
            name: n,
            createdAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
    return PlaylistRef.phone(id);
  }

  /// The songs of [ref] in order: (stored key, the row it plays now or null: absent).
  Stream<List<(String, Track?)>> items(PlaylistRef ref) =>
      db.watchPlaylistItems(ref.accountId, ref.playlistId);

  /// Adds [keys] at the end, in their order. Without [allowDuplicates], a song already in
  /// the playlist (the same key, or the same song on another account or the phone) or listed
  /// twice in [keys] is added once. Returns how many rows were added.
  Future<int> add(
    PlaylistRef ref,
    List<String> keys, {
    bool allowDuplicates = false,
  }) async {
    final id = _phone(ref);
    return db.transaction(() async {
      final old = await _rows(id);
      final merge = await _mergeKeys(keys);
      final seen = _Seen()..addAll(old.map((r) => (r.trackPath, r.mergeKey)));
      final added = <(String, String)>[];
      for (final k in keys) {
        final item = (k, merge[k] ?? '');
        if (!allowDuplicates && seen.has(item)) continue;
        seen.add(item);
        added.add(item);
      }
      await db.batch((b) {
        for (final (i, (key, mk)) in added.indexed) {
          b.insert(
            db.phonePlaylistItems,
            PhonePlaylistItemsCompanion.insert(
              playlistId: id,
              position: old.length + i,
              trackPath: key,
              mergeKey: Value(mk),
            ),
          );
        }
      });
      return added.length;
    });
  }

  /// Those of [keys] the playlist already has (the same key, or the same song elsewhere),
  /// each once, in the order of [keys].
  Future<List<String>> duplicatesIn(PlaylistRef ref, List<String> keys) async {
    final id = _phone(ref);
    final seen = _Seen()
      ..addAll((await _rows(id)).map((r) => (r.trackPath, r.mergeKey)));
    final merge = await _mergeKeys(keys);
    final out = <String>[];
    for (final k in keys) {
      if (seen.has((k, merge[k] ?? '')) && !out.contains(k)) out.add(k);
    }
    return out;
  }

  /// Takes the rows at [positions] (0 = the first) out; the others keep their order.
  /// A position the playlist does not have is ignored.
  Future<void> remove(PlaylistRef ref, List<int> positions) async {
    final id = _phone(ref);
    final gone = positions.toSet();
    await db.transaction(() async {
      final old = await _rows(id);
      await _rewrite(id, [
        for (final (i, r) in old.indexed)
          if (!gone.contains(i)) r,
      ]);
    });
  }

  /// Moves the row at [from] so it ends at [to] (both 0-based, in the playlist's range).
  Future<void> move(PlaylistRef ref, int from, int to) async {
    final id = _phone(ref);
    await db.transaction(() async {
      final rows = [...await _rows(id)];
      RangeError.checkValidIndex(from, rows, 'from');
      RangeError.checkValidIndex(to, rows, 'to');
      if (from == to) return;
      rows.insert(to, rows.removeAt(from));
      await _rewrite(id, rows);
    });
  }

  Future<void> rename(PlaylistRef ref, String name) async {
    final id = _phone(ref);
    final n = _name(name);
    await (db.update(db.phonePlaylists)..where((p) => p.id.equals(id))).write(
      PhonePlaylistsCompanion(name: Value(n)),
    );
  }

  /// The playlist goes, with its chosen cover. Its songs stay in the library; a kept one's
  /// `.m3u8` goes at the next `PlaylistFiles.refresh` (as a playlist a server no longer has).
  Future<void> delete(PlaylistRef ref) async {
    final id = _phone(ref);
    final old = await _coverName(id);
    await db.transaction(() async {
      await (db.delete(
        db.phonePlaylistItems,
      )..where((i) => i.playlistId.equals(id))).go();
      await (db.delete(db.phonePlaylists)..where((p) => p.id.equals(id))).go();
    });
    await _deleteCover(old);
  }

  /// [image] (a photo the user chose) becomes the playlist's cover: a copy goes in the app
  /// folder, the copy it replaces goes away; [image] itself is never touched.
  Future<void> setCover(PlaylistRef ref, File image) async {
    final id = _phone(ref);
    final old = await _coverName(id);
    final dir = Directory(p.join((await _supportDir()).path, coverFolder));
    await dir.create(recursive: true);
    final name =
        'phone-$id-${DateTime.now().microsecondsSinceEpoch}'
        '${p.extension(image.path).toLowerCase()}';
    await image.copy(p.join(dir.path, name));
    final n =
        await (db.update(db.phonePlaylists)..where((p) => p.id.equals(id)))
            .write(PhonePlaylistsCompanion(coverFile: Value(name)));
    // the playlist went in the meantime: its copy goes too
    await _deleteCover(n == 0 ? name : old);
  }

  /// The cover chosen for [ref], null when none (the mosaic of its songs is shown).
  Future<File?> coverOf(PlaylistRef ref) async {
    if (ref is! PhonePlaylistRef) return null;
    final name = await _coverName(ref.id);
    if (name == null) return null;
    return File(p.join((await _supportDir()).path, coverFolder, name));
  }

  // ---- inside

  int _phone(PlaylistRef ref) => switch (ref) {
    PhonePlaylistRef(:final id) => id,
    ServerPlaylistRef() => throw _readOnly(ref),
  };

  static UnsupportedError _readOnly(PlaylistRef ref) =>
      UnsupportedError('server playlists are read-only for now: $ref');

  static String _name(String name) {
    final n = name.trim();
    if (n.isEmpty) throw ArgumentError.value(name, 'name', 'empty');
    return n;
  }

  Future<List<PhonePlaylistItemRow>> _rows(int id) =>
      (db.select(db.phonePlaylistItems)
            ..where((i) => i.playlistId.equals(id))
            ..orderBy([(i) => OrderingTerm.asc(i.position)]))
          .get();

  /// Writes [rows] as the whole playlist, positions 0, 1, 2…
  Future<void> _rewrite(int id, List<PhonePlaylistItemRow> rows) async {
    await (db.delete(
      db.phonePlaylistItems,
    )..where((i) => i.playlistId.equals(id))).go();
    await db.batch((b) {
      for (final (i, r) in rows.indexed) {
        b.insert(db.phonePlaylistItems, r.copyWith(position: i));
      }
    });
  }

  /// The merge key of each of [keys] in the library ('' when unknown).
  Future<Map<String, String>> _mergeKeys(List<String> keys) async {
    final out = <String, String>{};
    final all = keys.toSet().toList();
    for (var i = 0; i < all.length; i += 500) {
      final chunk = all.skip(i).take(500).toList();
      for (final r
          in await (db.selectOnly(db.tracks)
                ..addColumns([db.tracks.path, db.tracks.mergeKey])
                ..where(db.tracks.path.isIn(chunk)))
              .get()) {
        out[r.read(db.tracks.path)!] = r.read(db.tracks.mergeKey)!;
      }
    }
    return out;
  }

  Future<String?> _coverName(int id) async => (await (db.select(
    db.phonePlaylists,
  )..where((p) => p.id.equals(id))).getSingleOrNull())?.coverFile;

  Future<void> _deleteCover(String? name) async {
    if (name == null || name.isEmpty) return;
    try {
      final f = File(p.join((await _supportDir()).path, coverFolder, name));
      if (await f.exists()) await f.delete();
    } catch (_) {} // a copy that does not go stops nothing
  }
}

/// Songs already met: by key, and by merge key (the same song on another row).
class _Seen {
  final _keys = <String>{};
  final _merge = <String>{};

  void add((String, String) item) {
    _keys.add(item.$1);
    if (item.$2.isNotEmpty) _merge.add(item.$2);
  }

  void addAll(Iterable<(String, String)> items) => items.forEach(add);

  bool has((String, String) item) =>
      _keys.contains(item.$1) ||
      (item.$2.isNotEmpty && _merge.contains(item.$2));
}
