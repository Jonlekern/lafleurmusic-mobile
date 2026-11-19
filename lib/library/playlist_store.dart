import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../sources/accounts.dart' show AccountType;
import '../sources/jellyfin.dart' show JellyfinException;
import '../sources/plex_link.dart' show PlexException;
import '../sources/remote_key.dart';
import '../sources/source.dart';
import '../sources/subsonic.dart' show SubsonicException;
import 'db.dart';
import 'models.dart';
import 'sync.dart' show trackKey;

export 'models.dart'
    show
        PlaylistRef,
        PhonePlaylistRef,
        ServerPlaylistRef,
        ServerPlaylist,
        phonePlaylistAccount;

/// Why a server playlist could not be changed ([PlaylistWriteException]).
enum PlaylistProblem {
  /// The server won't let this account write playlists (no rights, too old a server).
  refused,

  /// The server did not answer (no network, timeout): try again later.
  unreachable,

  /// The server refused the account's sign-in: « À reconnecter ».
  relink,

  /// Too many songs for this server to take in one go (a Subsonic server without form POST).
  tooLong,

  /// The playlist changed on the server meanwhile (« La playlist a changé, réessaie. »):
  /// nothing sent; it was read again, so trying again works on what the server has.
  changed,

  /// Anything else (the server answered with an error).
  failed,
}

/// A server playlist could not be changed. The phone shows what the server has: nothing, or
/// (when the answer was lost or the playlist changed) the playlist read again. Never carries
/// an address, a token or a password.
class PlaylistWriteException implements Exception {
  PlaylistWriteException(this.problem, this.accountId);
  final PlaylistProblem problem;
  final String accountId;
  @override
  String toString() => 'PlaylistWriteException(${problem.name}, $accountId)';
}

/// The one place that changes playlists, whatever their kind (plan 9). A phone playlist
/// ([PlaylistRef.phone]) lives in this database only and works with no account at all; its
/// songs are named by their key (`subsonic://…`, `jellyfin://…`, `plex://…` or a local path),
/// in order, a song twice only when asked.
///
/// A server playlist ([PlaylistRef.server]) is changed on its server ([PlaylistWriter]), then
/// read again from it and stored as the sync stores it (`Playlists` / `PlaylistItems`): the
/// server has the last word. Its actions run one at a time per playlist, in the order they
/// were asked. A failure is a [PlaylistWriteException]; when the server may have done the
/// change anyway (no answer, an error), the playlist is read again first, so trying again
/// never adds a song twice.
class PlaylistStore {
  /// [supportDir]: the app support folder (the chosen covers go in it); by default the
  /// system's. [sourceOf]: the account's source (the app's `MediaResolver.source`); without
  /// it, server playlists can't be changed.
  PlaylistStore(
    this.db, {
    Future<Directory> Function()? supportDir,
    this._sourceOf,
  }) : _supportDir = supportDir ?? getApplicationSupportDirectory;

  final LibraryDb db;
  final Future<Directory> Function() _supportDir;
  final Future<MusicSource> Function(String accountId)? _sourceOf;

  /// Accounts whose server refused to create a playlist since the app started (or whose
  /// source can't write): « Où la ranger » no longer offers them. In memory only: after a
  /// restart, or once a creation there works, the account is offered again.
  ValueListenable<Set<String>> get readOnlyAccounts => _readOnly;
  final _readOnly = ValueNotifier<Set<String>>(const {});

  /// Server playlists this account may not change: the server refused a change, or said so
  /// when read (another user's, `readonly`). The edit buttons hide for them. In memory only;
  /// a read saying it is editable again takes it out.
  ValueListenable<Set<PlaylistRef>> get readOnlyPlaylists => _readOnlyLists;
  final _readOnlyLists = ValueNotifier<Set<PlaylistRef>>(const {});

  /// False for a server playlist known not to be changeable ([readOnlyPlaylists]).
  bool canEdit(PlaylistRef ref) => !_readOnlyLists.value.contains(ref);

  /// Reads [ref] from its server (stored as the sync does) and says whether this account may
  /// change it; to call when a server playlist is opened. A phone playlist: true. Unknown
  /// (no answer): what is known so far ([canEdit]).
  Future<bool> checkEditable(PlaylistRef ref) async {
    if (ref is! ServerPlaylistRef) return true;
    try {
      final (s, w) = await _writer(ref.accountId);
      await _serial(ref, () => _reread(ref.accountId, s, w, ref.remoteId));
    } on PlaylistWriteException {
      return false;
    }
    return canEdit(ref);
  }

  /// The last action asked for each server playlist (the next one waits for it).
  final _queues = <PlaylistRef, Future<void>>{};

  /// Whether a new playlist may be kept on [accountId]: its source writes playlists and its
  /// server has not refused it ([readOnlyAccounts]). Asks nothing of the server.
  Future<bool> canWrite(String accountId) async {
    if (_readOnly.value.contains(accountId)) return false;
    final of = _sourceOf;
    if (of == null) return false;
    try {
      return await of(accountId) is PlaylistWriter;
    } on Object {
      return false;
    }
  }

  static const coverFolder = 'playlist_covers';

  /// A new playlist named [name] (spaces around it dropped; empty: refused) holding
  /// [songs] (keys, as [add] takes them, duplicates dropped). Without [accountId] (or with
  /// [phonePlaylistAccount]): on the phone; with a server account: made on that server with
  /// its songs at once (Plex: never an empty creation when there are songs), then stored as
  /// the sync stores it.
  Future<PlaylistRef> create(
    String name, {
    String? accountId,
    List<String> songs = const [],
  }) async {
    final n = _name(name);
    if (accountId != null && accountId != phonePlaylistAccount) {
      return _createOnServer(accountId, n, songs);
    }
    if (songs.isNotEmpty) {
      final ref = await create(n);
      await add(ref, songs);
      return ref;
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
    if (ref is ServerPlaylistRef) {
      return _addOnServer(ref, keys, allowDuplicates);
    }
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
    final seen = _Seen()..addAll(await _itemsWithMergeKeys(ref));
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
    if (ref is ServerPlaylistRef) {
      return _serial(ref, () async {
        final count = (await _serverPaths(ref)).length;
        final ok = [
          for (final p in positions.toSet())
            if (p >= 0 && p < count) p,
        ];
        if (ok.isEmpty) return;
        final seen = await _serverPaths(ref);
        await _onServer(
          ref,
          (w) => w.removeFromPlaylist(
            ref.remoteId,
            ok,
            expected: [for (final p in ok) _songIdOf(seen[p])],
          ),
        );
      });
    }
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
    if (ref is ServerPlaylistRef) {
      return _serial(ref, () async {
        final rows = await _serverPaths(ref);
        RangeError.checkValidIndex(from, rows, 'from');
        RangeError.checkValidIndex(to, rows, 'to');
        if (from == to) return;
        await _onServer(
          ref,
          (w) => w.movePlaylistItem(
            ref.remoteId,
            from,
            to,
            expected: _songIdOf(rows[from]),
          ),
        );
      });
    }
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
    final n = _name(name);
    if (ref is ServerPlaylistRef) {
      return _serial(
        ref,
        () => _onServer(ref, (w) => w.renamePlaylist(ref.remoteId, n)),
      );
    }
    final id = _phone(ref);
    await (db.update(db.phonePlaylists)..where((p) => p.id.equals(id))).write(
      PhonePlaylistsCompanion(name: Value(n)),
    );
  }

  /// The playlist goes, with its chosen cover. Its songs stay in the library; a kept one's
  /// `.m3u8` goes at the next `PlaylistFiles.refresh` (as a playlist a server no longer has).
  Future<void> delete(PlaylistRef ref) async {
    if (ref is ServerPlaylistRef) {
      return _serial(ref, () async {
        await _onServer(
          ref,
          (w) => w.deletePlaylist(ref.remoteId),
          reread: false,
        );
        await db.transaction(() async {
          await (db.delete(db.playlistItems)..where(
                (i) =>
                    i.accountId.equals(ref.accountId) &
                    i.playlistId.equals(ref.remoteId),
              ))
              .go();
          await (db.delete(db.playlists)..where(
                (p) =>
                    p.accountId.equals(ref.accountId) &
                    p.remoteId.equals(ref.remoteId),
              ))
              .go();
        });
        _markList(ref, readOnly: false);
      });
    }
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
  /// folder, the copy it replaces goes away; [image] itself is never touched. Phone
  /// playlists only (no server's cover is written: the choice is hidden for them).
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
    ServerPlaylistRef() => throw _noCover(ref),
  };

  static UnsupportedError _noCover(PlaylistRef ref) =>
      UnsupportedError('no chosen cover for a server playlist: $ref');

  // ---- server playlists

  /// Runs [op] after the actions already asked for [ref], one at a time; a failed one does
  /// not stop the next.
  Future<T> _serial<T>(PlaylistRef ref, Future<T> Function() op) {
    final before = _queues[ref] ?? Future<void>.value();
    final run = before.then((_) => op());
    final done = run.then<void>((_) {}, onError: (Object _) {});
    _queues[ref] = done;
    unawaited(
      done.whenComplete(() {
        if (identical(_queues[ref], done)) _queues.remove(ref);
      }),
    );
    return run;
  }

  /// The writer of [accountId], or a [PlaylistWriteException].
  Future<(MusicSource, PlaylistWriter)> _writer(String accountId) async {
    final of = _sourceOf;
    if (of == null) throw UnsupportedError('no sources: $accountId');
    final MusicSource s;
    try {
      s = await of(accountId);
    } on Exception {
      throw PlaylistWriteException(PlaylistProblem.failed, accountId);
    }
    if (s is! PlaylistWriter) {
      _markReadOnly(accountId, true);
      throw PlaylistWriteException(PlaylistProblem.refused, accountId);
    }
    return (s, s as PlaylistWriter);
  }

  /// Runs [write] on [accountId]'s server; a failure becomes a [PlaylistWriteException].
  /// A refusal marks [ref] read-only, or the account when creating ([ref] null); success
  /// clears that mark. When the server may have done the change anyway (no answer, an
  /// error, the playlist changed), [ref] is read again and stored before the error.
  Future<T> _write<T>(
    String accountId,
    ServerPlaylistRef? ref,
    Future<T> Function(MusicSource s, PlaylistWriter w) write,
  ) async {
    final (s, w) = await _writer(accountId);
    final T r;
    try {
      r = await write(s, w);
    } on Exception catch (e) {
      final problem = _problemOf(e);
      if (problem == PlaylistProblem.refused) {
        ref == null
            ? _markReadOnly(accountId, true)
            : _markList(ref, readOnly: true);
      } else if (ref != null &&
          (problem == PlaylistProblem.unreachable ||
              problem == PlaylistProblem.failed ||
              problem == PlaylistProblem.changed)) {
        await _reread(accountId, s, w, ref.remoteId);
      }
      throw PlaylistWriteException(problem, accountId);
    }
    if (ref == null) _markReadOnly(accountId, false);
    return r;
  }

  /// [write] on [ref]'s server, then the playlist read again and stored ([reread]).
  Future<void> _onServer(
    ServerPlaylistRef ref,
    Future<void> Function(PlaylistWriter w) write, {
    bool reread = true,
  }) => _write(ref.accountId, ref, (s, w) async {
    await write(w);
    if (reread) await _reread(ref.accountId, s, w, ref.remoteId);
  });

  /// The song id in a stored server key (`<scheme>://acc/id`).
  static String _songIdOf(String key) => parseRemoteKey(key)?.$2 ?? key;

  /// Reads playlist [id] from the server and stores it. The change is done: a failure here
  /// only leaves the old rows until the next action or sync. Returns false then.
  Future<bool> _reread(
    String accountId,
    MusicSource s,
    PlaylistWriter w,
    String id,
  ) async {
    final SourcePlaylist p;
    try {
      p = await w.readPlaylist(id);
    } on Exception {
      return false;
    }
    await _storeServer(accountId, _typeOf(s), p);
    _markList(PlaylistRef.server(accountId, id), readOnly: !p.editable);
    return true;
  }

  static PlaylistProblem _problemOf(Exception e) => switch (e) {
    PlaylistWriteRefused() => PlaylistProblem.refused,
    PlaylistTooLong() => PlaylistProblem.tooLong,
    PlaylistChanged() => PlaylistProblem.changed,
    SourceNetworkException() ||
    TimeoutException() => PlaylistProblem.unreachable,
    SubsonicException(code: 40 || 41) => PlaylistProblem.relink,
    SubsonicException(:final httpStatus?) when httpStatus >= 500 =>
      PlaylistProblem.unreachable,
    JellyfinException(wrongPassword: true) => PlaylistProblem.relink,
    JellyfinException(:final statusCode?) when statusCode >= 500 =>
      PlaylistProblem.unreachable,
    PlexException(tokenRefused: true) => PlaylistProblem.relink,
    PlexException(:final statusCode?) when statusCode >= 500 =>
      PlaylistProblem.unreachable,
    _ => PlaylistProblem.failed,
  };

  void _markReadOnly(String accountId, bool readOnly) {
    final now = _readOnly.value;
    if (now.contains(accountId) == readOnly) return;
    _readOnly.value = Set.unmodifiable(
      readOnly ? {...now, accountId} : ({...now}..remove(accountId)),
    );
  }

  void _markList(PlaylistRef ref, {required bool readOnly}) {
    final now = _readOnlyLists.value;
    if (now.contains(ref) == readOnly) return;
    _readOnlyLists.value = Set.unmodifiable(
      readOnly ? {...now, ref} : ({...now}..remove(ref)),
    );
  }

  static AccountType _typeOf(MusicSource s) =>
      s is TypedSource ? (s as TypedSource).accountType : AccountType.subsonic;

  Future<PlaylistRef> _createOnServer(
    String accountId,
    String name,
    List<String> songs,
  ) async {
    final ids = await _songIdsFor(accountId, const [], songs, false);
    return _write(accountId, null, (s, w) async {
      final id = await w.createPlaylist(name, songIds: ids);
      // not read back: shown empty under its name until the next action or sync
      if (!await _reread(accountId, s, w, id)) {
        await _storeServer(
          accountId,
          _typeOf(s),
          SourcePlaylist(id: id, name: name, songIds: const []),
        );
      }
      return PlaylistRef.server(accountId, id);
    });
  }

  /// The song ids on [accountId] for [keys] (see [add]): this server's copy of each, those
  /// it does not have left out; without [allowDuplicates], those of [old] and repeats too.
  Future<List<String>> _songIdsFor(
    String accountId,
    List<(String, String)> old,
    List<String> keys,
    bool allowDuplicates,
  ) async {
    final seen = _Seen()..addAll(old);
    final merge = await _mergeKeys(keys);
    final ids = <String>[];
    for (final k in keys) {
      final item = (k, merge[k] ?? '');
      if (!allowDuplicates && seen.has(item)) continue;
      final id = await _songIdOn(accountId, k, item.$2);
      if (id == null) continue; // this server does not have that song
      seen.add(item);
      ids.add(id);
    }
    return ids;
  }

  Future<int> _addOnServer(
    ServerPlaylistRef ref,
    List<String> keys,
    bool allowDuplicates,
  ) => _serial(ref, () async {
    final ids = await _songIdsFor(
      ref.accountId,
      await _itemsWithMergeKeys(ref),
      keys,
      allowDuplicates,
    );
    if (ids.isEmpty) return 0;
    await _onServer(ref, (w) => w.addToPlaylist(ref.remoteId, ids));
    return ids.length;
  });

  /// [key]'s song id on [accountId]: its own when the key is that account's, else the same
  /// song there (by [mergeKey]), else null.
  Future<String?> _songIdOn(
    String accountId,
    String key,
    String mergeKey,
  ) async {
    final own = parseRemoteKey(key);
    if (own != null && own.$1 == accountId) return own.$2;
    if (mergeKey.isEmpty) return null;
    final twin =
        await (db.selectOnly(db.tracks)
              ..addColumns([db.tracks.remoteId])
              ..where(
                db.tracks.accountId.equals(accountId) &
                    db.tracks.mergeKey.equals(mergeKey),
              )
              ..orderBy([OrderingTerm.asc(db.tracks.path)])
              ..limit(1))
            .getSingleOrNull();
    final id = twin?.read(db.tracks.remoteId);
    return id == null || id.isEmpty ? null : id;
  }

  Future<List<String>> _serverPaths(ServerPlaylistRef ref) =>
      db.playlistPaths(ref.accountId, ref.remoteId);

  /// The rows of [ref] as (key, merge key) (duplicates are found with both).
  Future<List<(String, String)>> _itemsWithMergeKeys(PlaylistRef ref) async {
    switch (ref) {
      case PhonePlaylistRef(:final id):
        return [for (final r in await _rows(id)) (r.trackPath, r.mergeKey)];
      case ServerPlaylistRef():
        final paths = await _serverPaths(ref);
        final merge = await _mergeKeys(paths);
        return [for (final p in paths) (p, merge[p] ?? '')];
    }
  }

  /// Stores [p] as the sync stores a playlist of [accountId] (a new one after the others).
  Future<void> _storeServer(
    String accountId,
    AccountType type,
    SourcePlaylist p,
  ) => db.transaction(() async {
    final mine = await (db.select(
      db.playlists,
    )..where((l) => l.accountId.equals(accountId))).get();
    final old = mine.where((l) => l.remoteId == p.id).firstOrNull;
    final position =
        old?.position ??
        mine.fold<int>(-1, (m, l) => l.position > m ? l.position : m) + 1;
    await db
        .into(db.playlists)
        .insertOnConflictUpdate(
          PlaylistsCompanion.insert(
            accountId: accountId,
            remoteId: p.id,
            name: p.name,
            position: position,
          ),
        );
    final songs = p.songIds;
    if (songs == null) return; // unread: its old songs stay
    await (db.delete(db.playlistItems)..where(
          (i) => i.accountId.equals(accountId) & i.playlistId.equals(p.id),
        ))
        .go();
    await db.batch((b) {
      for (final (i, id) in songs.indexed) {
        b.insert(
          db.playlistItems,
          PlaylistItemsCompanion.insert(
            accountId: accountId,
            playlistId: p.id,
            index: i,
            trackPath: trackKey(accountId, id, type),
          ),
        );
      }
    });
  });

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
