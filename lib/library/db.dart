import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import '../offline/paths.dart';
import 'merge.dart';
import 'models.dart';

part 'db.g.dart';

@DataClassName('TrackRow')
@TableIndex(name: 'tracks_merge_key', columns: {#mergeKey})
@TableIndex(name: 'tracks_album_merge_key', columns: {#albumMergeKey})
class Tracks extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get path => text().unique()();
  IntColumn get folderId => integer().withDefault(const Constant(0))();
  TextColumn get accountId => text().withDefault(const Constant('local'))();
  TextColumn get remoteId => text().withDefault(const Constant(''))();
  TextColumn get albumArtist => text().withDefault(const Constant(''))();
  IntColumn get disc => integer().nullable()();
  TextColumn get coverId => text().nullable()();
  TextColumn get suffix => text().nullable()();
  RealColumn get replayGain => real().nullable()();
  TextColumn get title => text()();
  TextColumn get artist => text()();
  TextColumn get album => text()();
  TextColumn get albumKey => text()();
  TextColumn get genre => text().withDefault(const Constant(''))();
  IntColumn get trackNo => integer().nullable()();
  IntColumn get durationMs => integer()();
  BoolColumn get hasCover => boolean()();
  IntColumn get mtime => integer().withDefault(const Constant(0))();
  IntColumn get size => integer()();
  BoolColumn get missing => boolean().withDefault(const Constant(false))();
  BoolColumn get toRepair => boolean().withDefault(const Constant(false))();
  TextColumn get searchKey => text()();
  // même morceau sur plusieurs comptes = même clé (voir merge.dart)
  TextColumn get mergeKey => text().withDefault(const Constant(''))();
  // même album sur plusieurs comptes = même clé (voir merge.dart)
  TextColumn get albumMergeKey => text().withDefault(const Constant(''))();
}

/// Écoutes (Top 100) : une ligne par fichier écouté.
class PlayCounts extends Table {
  TextColumn get path => text()();
  IntColumn get count => integer()(); // écoutes faites dans l'appli
  IntColumn get imported =>
      integer().withDefault(const Constant(0))(); // écoutes lues sur le serveur
  IntColumn get lastPlayed => integer()(); // millisecondes depuis 1970
  @override
  Set<Column> get primaryKey => {path};
}

/// Volume perçu mesuré (Volume égal) ; lufs null = non mesurable. Remesuré si le fichier change (mtime).
class Loudness extends Table {
  TextColumn get path => text()();
  RealColumn get lufs => real().nullable()();
  IntColumn get mtime => integer()();
  @override
  Set<Column> get primaryKey => {path};
}

/// Comptes serveur. Ni mot de passe ni en-têtes ici : ils vivent dans le stockage sécurisé.
@DataClassName('AccountRow')
class AccountRows extends Table {
  @override
  String get tableName => 'accounts';

  TextColumn get id => text()();
  TextColumn get type => text()(); // AccountType.name
  TextColumn get name => text()();
  TextColumn get base => text()();
  TextColumn get user => text()();
  IntColumn get position => integer()();
  @override
  Set<Column> get primaryKey => {id};
}

/// Copies gardées hors ligne : une ligne par morceau de serveur (clé = Tracks.path).
@DataClassName('OfflineRow')
class Offline extends Table {
  TextColumn get trackPath => text()();
  TextColumn get filePath =>
      text().nullable()(); // relatif à la racine LAFLEURMUSIC
  IntColumn get size => integer().withDefault(const Constant(0))();
  IntColumn get addedAt => integer()(); // ms
  TextColumn get reason => text()(); // OfflineReason.name
  TextColumn get state => text()(); // OfflineState.name
  IntColumn get failures => integer().withDefault(const Constant(0))();
  @override
  Set<Column> get primaryKey => {trackPath};
}

/// Morceaux que l'utilisateur a retirés du téléphone : le Top 100 ne les regarde plus
/// tant qu'un « Garder » de l'utilisateur ne lève pas le blocage. Table à part : la
/// ligne `Offline` disparaît avec la copie.
class AutoKeepBlocks extends Table {
  TextColumn get trackPath => text()();
  @override
  Set<Column> get primaryKey => {trackPath};
}

/// Écoutes faites hors ligne, à envoyer au serveur (scrobble) au retour du réseau.
@DataClassName('PendingScrobble')
class PendingScrobbles extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get accountId => text()();
  TextColumn get remoteId => text()();
  IntColumn get at => integer()(); // ms
}

/// Playlists des serveurs (une par compte et par identifiant distant).
@DataClassName('PlaylistRow')
class Playlists extends Table {
  TextColumn get accountId => text()();
  TextColumn get remoteId => text()();
  TextColumn get name => text()();
  IntColumn get position => integer()();
  @override
  Set<Column> get primaryKey => {accountId, remoteId};
}

/// Les morceaux d'une playlist, dans l'ordre (`index`).
@DataClassName('PlaylistItemRow')
class PlaylistItems extends Table {
  TextColumn get accountId => text()();
  TextColumn get playlistId => text()();
  IntColumn get index => integer()();
  TextColumn get trackPath => text()();
  @override
  Set<Column> get primaryKey => {accountId, playlistId, index};
}

/// Les `.m3u8` écrits par l'appli sous `<racine>/Playlists/` : seuls fichiers qu'elle supprime.
@DataClassName('KeptPlaylistRow')
class KeptPlaylists extends Table {
  TextColumn get accountId => text()();
  TextColumn get playlistId => text()();
  TextColumn get fileName => text()();
  @override
  Set<Column> get primaryKey => {accountId, playlistId};
}

/// Where the kept copies live (a reachable folder) and how a copy found there is named
/// once it is a local track ([keyFor]: absolute path → library path; null = the path itself).
class CopyRoot {
  const CopyRoot(this.path, [this.keyFor]);
  final String path;
  final Future<String> Function(String absolutePath)? keyFor;
}

@DriftDatabase(
  tables: [
    Tracks,
    PlayCounts,
    Loudness,
    AccountRows,
    Offline,
    PendingScrobbles,
    AutoKeepBlocks,
    Playlists,
    PlaylistItems,
    KeptPlaylists,
  ],
)
class LibraryDb extends _$LibraryDb {
  LibraryDb(super.e);

  // v2 : copies hors ligne et écoutes en attente. v3 : morceaux retirés du Top 100 par l'utilisateur.
  // v4 : clé de fusion, écoutes importées, playlists des serveurs.
  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(offline);
        await m.createTable(pendingScrobbles);
      }
      if (from < 3) await m.createTable(autoKeepBlocks);
      if (from < 4) {
        await m.addColumn(tracks, tracks.mergeKey);
        await m.createIndex(tracksMergeKey);
        await m.addColumn(tracks, tracks.albumMergeKey);
        await m.createIndex(tracksAlbumMergeKey);
        await m.createTable(playlists);
        await m.createTable(playlistItems);
        await m.createTable(keptPlaylists);
        await m.addColumn(playCounts, playCounts.imported);
        // la sync du plan 1 écrivait les écoutes du serveur dans `count` (raisePlayCounts)
        await customStatement(
          'UPDATE play_counts SET imported = count, count = 0',
        );
        final rows = await select(tracks).get();
        await batch((b) {
          for (final r in rows) {
            final t = _fromRow(r);
            b.update(
              tracks,
              TracksCompanion(
                mergeKey: Value(mergeKey(t)),
                albumMergeKey: Value(albumMergeKey(t)),
              ),
              where: (t) => t.id.equals(r.id),
            );
          }
        });
      }
    },
  );

  /// Met en file les morceaux [trackPaths] ; ne rétrograde jamais `user` en `top100`.
  /// Une copie déjà faite reste ; une copie abandonnée repart à zéro.
  Future<void> queueOffline(List<String> trackPaths, OfflineReason reason) =>
      transaction(() async {
        final now = DateTime.now().millisecondsSinceEpoch;
        // retirés par l'utilisateur : le Top 100 ne les remet pas en file (relu ici, dans la transaction)
        final blocked = reason == OfflineReason.top100
            ? await autoKeepBlocked()
            : const <String>{};
        for (final (i, p) in trackPaths.indexed) {
          if (blocked.contains(p)) continue;
          final old = await offlineOf(p);
          if (old == null) {
            await into(offline).insert(
              OfflineCompanion.insert(
                trackPath: p,
                addedAt: now + i, // l'ordre donné = l'ordre de téléchargement
                reason: reason.name,
                state: OfflineState.queued.name,
              ),
            );
            continue;
          }
          final keepUser = old.reason == OfflineReason.user.name;
          final failed = old.state == OfflineState.failed.name;
          await (update(offline)..where((o) => o.trackPath.equals(p))).write(
            OfflineCompanion(
              reason: Value(keepUser ? old.reason : reason.name),
              state: failed
                  ? Value(OfflineState.queued.name)
                  : const Value.absent(),
              failures: failed ? const Value(0) : const Value.absent(),
            ),
          );
        }
      });

  /// Le plus ancien morceau en attente (moins de 3 échecs).
  /// Sans [top100], les copies du Top 100 sont laissées en file ; les comptes de
  /// [skipAccounts] aussi (leur serveur a refusé un morceau pendant ce tour).
  Future<OfflineRow?> nextQueued({
    bool top100 = true,
    Set<String> skipAccounts = const {},
  }) =>
      (select(offline)
            ..where((o) {
              Expression<bool> w =
                  o.state.equals(OfflineState.queued.name) &
                  o.failures.isSmallerThanValue(3) &
                  (top100
                      ? const Constant(true)
                      : o.reason.equals(OfflineReason.top100.name).not());
              for (final acc in skipAccounts) {
                final prefix = 'subsonic://$acc/';
                w =
                    w &
                    o.trackPath.substr(1, prefix.length).equals(prefix).not();
              }
              return w;
            })
            ..orderBy([
              (o) => OrderingTerm.asc(o.addedAt),
              (o) => OrderingTerm.asc(o.trackPath),
            ])
            ..limit(1))
          .getSingleOrNull();

  Future<void> markOfflineDone(String trackPath, String filePath, int size) =>
      (update(offline)..where((o) => o.trackPath.equals(trackPath))).write(
        OfflineCompanion(
          filePath: Value(filePath),
          size: Value(size),
          state: Value(OfflineState.done.name),
        ),
      );

  /// Un échec de plus ; au 3e le morceau passe en `failed`.
  Future<void> markOfflineFailed(String trackPath) => customUpdate(
    'UPDATE offline SET failures = failures + 1, '
    "state = CASE WHEN failures + 1 >= 3 THEN 'failed' ELSE state END "
    'WHERE track_path = ?',
    variables: [Variable(trackPath)],
    updates: {offline},
  );

  /// Après un déplacement de dossier, en une transaction : les nouveaux chemins relatifs,
  /// et les copies introuvables passent en échec sans chemin (jamais un chemin périmé).
  Future<void> applyOfflineMove(
    Map<String, String> newRel,
    List<String> lost,
  ) => transaction(() async {
    for (final e in newRel.entries) {
      await (update(offline)..where((o) => o.trackPath.equals(e.key))).write(
        OfflineCompanion(filePath: Value(e.value)),
      );
    }
    for (final t in lost) {
      await (update(offline)..where((o) => o.trackPath.equals(t))).write(
        OfflineCompanion(
          filePath: const Value(null),
          size: const Value(0),
          state: Value(OfflineState.failed.name),
        ),
      );
    }
  });

  /// Le dossier des copies est perdu (on en adopte un autre) : chaque copie finie passe
  /// en échec, sans chemin ni taille, à refaire depuis « À réessayer ».
  Future<void> failDoneCopies() =>
      (update(
        offline,
      )..where((o) => o.state.equals(OfflineState.done.name))).write(
        OfflineCompanion(
          filePath: const Value(null),
          size: const Value(0),
          state: Value(OfflineState.failed.name),
        ),
      );

  /// Octets promis par la file d'attente : la taille connue de chaque morceau,
  /// [unknownSize] pour un morceau sans taille ou disparu.
  Future<int> queuedBytes(int unknownSize) async {
    final r = await customSelect(
      'SELECT COALESCE(SUM(CASE WHEN t.size > 0 THEN t.size ELSE ? END), 0) AS b '
      'FROM offline o LEFT JOIN tracks t ON t.path = o.track_path '
      'WHERE o.state = ?',
      variables: [Variable(unknownSize), Variable(OfflineState.queued.name)],
      readsFrom: {offline, tracks},
    ).getSingle();
    return r.read<int>('b');
  }

  /// Après un refus du serveur : le morceau passe derrière les autres de la file.
  Future<void> sendOfflineToBack(String trackPath) => customUpdate(
    'UPDATE offline SET added_at = '
    '(SELECT MAX(added_at) FROM offline) + 1 WHERE track_path = ?',
    variables: [Variable(trackPath)],
    updates: {offline},
  );

  Future<void> removeOffline(List<String> trackPaths) => transaction(() async {
    for (var i = 0; i < trackPaths.length; i += 500) {
      final chunk = trackPaths.skip(i).take(500).toList();
      await (delete(offline)..where((o) => o.trackPath.isIn(chunk))).go();
    }
  });

  Stream<Map<String, OfflineRow>> watchOffline() =>
      select(offline)
          .watch()
          .map((rows) => {for (final r in rows) r.trackPath: r});

  Future<OfflineRow?> offlineOf(String trackPath) => (select(
    offline,
  )..where((o) => o.trackPath.equals(trackPath))).getSingleOrNull();

  /// Octets des copies terminées.
  Future<int> offlineBytes() async {
    final total = offline.size.sum();
    final r =
        await (selectOnly(offline)
              ..addColumns([total])
              ..where(offline.state.equals(OfflineState.done.name)))
            .getSingle();
    return r.read(total) ?? 0;
  }

  Future<void> addPending(String accountId, String remoteId, DateTime at) =>
      into(pendingScrobbles).insert(
        PendingScrobblesCompanion.insert(
          accountId: accountId,
          remoteId: remoteId,
          at: at.millisecondsSinceEpoch,
        ),
      );

  Future<List<PendingScrobble>> pending(String accountId) =>
      (select(pendingScrobbles)
            ..where((p) => p.accountId.equals(accountId))
            ..orderBy([(p) => OrderingTerm.asc(p.id)]))
          .get();

  /// Les écoutes en attente de [accountId] plus anciennes que [before] : trop vieilles
  /// pour un scrobble utile.
  Future<void> dropPendingBefore(String accountId, DateTime before) =>
      (delete(pendingScrobbles)..where(
            (p) =>
                p.accountId.equals(accountId) &
                p.at.isSmallerThanValue(before.millisecondsSinceEpoch),
          ))
          .go();

  Future<void> deletePending(List<int> ids) async {
    for (var i = 0; i < ids.length; i += 500) {
      final chunk = ids.sublist(i, i + 500 > ids.length ? ids.length : i + 500);
      await (delete(pendingScrobbles)..where((p) => p.id.isIn(chunk))).go();
    }
  }

  Track _fromRow(TrackRow r) => Track(
    id: r.id,
    path: r.path,
    folderId: r.folderId,
    accountId: r.accountId,
    remoteId: r.remoteId,
    albumArtist: r.albumArtist,
    disc: r.disc,
    coverId: r.coverId,
    suffix: r.suffix,
    replayGain: r.replayGain,
    title: r.title,
    artist: r.artist,
    album: r.album,
    genre: r.genre,
    trackNo: r.trackNo,
    durationMs: r.durationMs,
    hasCover: r.hasCover,
    mtime: r.mtime,
    size: r.size,
    missing: r.missing,
  );

  Future<void> upsertTrack(Track t) => upsertTracks([t]);

  Future<void> upsertTracks(List<Track> list) => batch((b) {
    for (final t in list) {
      final row = TracksCompanion.insert(
        path: t.path,
        folderId: Value(t.folderId),
        accountId: Value(t.accountId),
        remoteId: Value(t.remoteId),
        albumArtist: Value(t.albumArtist),
        disc: Value(t.disc),
        coverId: Value(t.coverId),
        suffix: Value(t.suffix),
        replayGain: Value(t.replayGain),
        title: t.title,
        artist: t.artist,
        album: t.album,
        albumKey: sortKey(t.album),
        mergeKey: Value(mergeKey(t)),
        albumMergeKey: Value(albumMergeKey(t)),
        genre: Value(t.genre),
        trackNo: Value(t.trackNo),
        durationMs: t.durationMs,
        hasCover: t.hasCover,
        mtime: Value(t.mtime),
        size: t.size,
        missing: Value(t.missing),
        searchKey: sortKey('${t.title}\n${t.artist}\n${t.album}'),
      );
      // même chemin : on remplace toutes les colonnes (le chemin est la clé)
      b.insert(
        tracks,
        row,
        onConflict: DoUpdate(
          (_) => row.copyWith(path: const Value.absent()),
          target: [tracks.path],
        ),
      );
    }
  });

  Future<Track?> trackByPath(String path) async {
    final r = await (select(
      tracks,
    )..where((t) => t.path.equals(path))).getSingleOrNull();
    return r == null ? null : _fromRow(r);
  }

  /// Deletes all tracks of one account, plus those tracks' play counts and loudness rows.
  /// [root]: see [dropServerTracks].
  Future<void> deleteAccountTracks(
    String accountId, {
    required CopyRoot? root,
  }) => transaction(() async {
    final paths =
        await (selectOnly(tracks)
              ..addColumns([tracks.path])
              ..where(tracks.accountId.equals(accountId)))
            .map((r) => r.read(tracks.path)!)
            .get();
    await dropServerTracks(paths, root: root);
  });

  /// Server tracks whose account no longer exists (removed while the folder was unreachable):
  /// finished copies that are still on disk become local tracks, the rest goes ([dropServerTracks]).
  /// Safe to repeat; call it only with a reachable [root].
  Future<void> adoptOrphans(CopyRoot root) async {
    final orphans = await customSelect(
      "SELECT path FROM tracks WHERE account_id <> 'local' "
      'AND account_id NOT IN (SELECT id FROM accounts)',
      readsFrom: {tracks, accountRows},
    ).map((r) => r.read<String>('path')).get();
    if (orphans.isNotEmpty) await dropServerTracks(orphans, root: root);
  }

  /// Server tracks [paths] that are gone (removed from the server, or their account removed).
  /// Their offline rows go, except finished copies: with a reachable [root], one whose file
  /// exists becomes a local track (plays follow, the file is never touched) and one whose file
  /// is gone is dropped; with a null [root] (folder unreachable or unknown) we can't tell
  /// whether the file is there, so finished copies and their tracks are left as they are.
  Future<void> dropServerTracks(
    List<String> paths, {
    required CopyRoot? root,
  }) => transaction(() async {
    for (var i = 0; i < paths.length; i += 500) {
      final chunk = paths.skip(i).take(500).toList();
      final rows = {
        for (final o in await (select(
          offline,
        )..where((o) => o.trackPath.isIn(chunk))).get())
          o.trackPath: o,
      };
      final gone = <String>[];
      for (final path in chunk) {
        final o = rows[path];
        final rel = o?.filePath;
        final done = o != null && o.state == OfflineState.done.name;
        if (done && root == null) continue; // can't tell: nothing lost
        if (done && rel != null) {
          final abs = p.join(root!.path, rel);
          final file = File(abs);
          // iCloud a pu mettre le fichier de côté (`.nom.icloud`) : il est toujours là
          final row = fileOrPlaceholderExists(abs)
              ? await (select(
                  tracks,
                )..where((t) => t.path.equals(path))).getSingleOrNull()
              : null;
          if (row != null) {
            final t = _fromRow(row);
            final key = await root.keyFor?.call(abs) ?? abs;
            await upsertTracks([
              Track(
                path: key,
                accountId: 'local',
                remoteId: '',
                albumArtist: t.albumArtist,
                disc: t.disc,
                coverId: t.coverId,
                suffix: t.suffix,
                replayGain: t.replayGain,
                title: t.title,
                artist: t.artist,
                album: t.album,
                genre: t.genre,
                trackNo: t.trackNo,
                durationMs: t.durationMs,
                hasCover: t.hasCover,
                mtime: file.existsSync()
                    ? file.statSync().modified.millisecondsSinceEpoch
                    : t.mtime,
                size: file.existsSync()
                    ? file.lengthSync()
                    : (o.size > 0 ? o.size : t.size),
              ),
            ]);
            await movePlays(path, key);
          }
        }
        gone.add(path);
      }
      await deletePaths(gone);
      await removeOffline(gone);
    }
  });

  /// The server's counts [counts] (path -> count). The server's number already holds the
  /// listens the app scrobbled, so what it knows beyond the app's own `count` goes in
  /// `imported`: `imported = max(imported, server - count)`, never lowered.
  Future<void> raisePlayCounts(Map<String, int> counts) async {
    for (final e in counts.entries) {
      await customUpdate(
        'INSERT INTO play_counts (path, count, imported, last_played) '
        'VALUES (?, 0, ?, 0) ON CONFLICT(path) DO UPDATE SET '
        'imported = max(imported, excluded.imported - count)',
        variables: [Variable(e.key), Variable(e.value)],
        updates: {playCounts},
      );
    }
  }

  Future<void> deletePaths(List<String> paths) => transaction(() async {
    await (delete(tracks)..where((t) => t.path.isIn(paths))).go();
    await (delete(playCounts)..where((t) => t.path.isIn(paths))).go();
    await (delete(loudness)..where((t) => t.path.isIn(paths))).go();
  });

  /// Une écoute de plus (voir PlayCounter).
  Future<void> addPlay(String path, DateTime at) => customUpdate(
    'INSERT INTO play_counts (path, count, last_played) VALUES (?, 1, ?) '
    'ON CONFLICT(path) DO UPDATE SET count = count + 1, last_played = excluded.last_played',
    variables: [Variable(path), Variable(at.millisecondsSinceEpoch)],
    updates: {playCounts}, // le Top 100 affiché se met à jour
  );

  /// Les [limit] plus écoutés (morceaux absents du disque cachés) avec leur nombre d'écoutes.
  /// [accounts] : seulement ces comptes et les fichiers du téléphone (null : tous).
  Stream<List<(Track, int)>> watchTop(int limit, {Set<String>? accounts}) =>
      _topQuery(limit, accounts).watch().map(_topRows);

  /// Le même classement, une fois (le Top 100 gardé sur le téléphone).
  Future<List<(Track, int)>> top(int limit) async =>
      _topRows(await _topQuery(limit).get());

  JoinedSelectStatement<HasResultSet, dynamic> _topQuery(
    int limit, [
    Set<String>? accounts,
  ]) =>
      select(tracks)
          .join([innerJoin(playCounts, playCounts.path.equalsExp(tracks.path))])
        ..where(
          tracks.missing.equals(false) &
              (accounts == null
                  ? const Constant(true)
                  : tracks.accountId.equals('local') |
                        tracks.accountId.isIn(accounts)),
        )
        ..orderBy([
          OrderingTerm.desc(playCounts.count + playCounts.imported),
          OrderingTerm.desc(playCounts.lastPlayed),
        ])
        ..limit(limit);

  List<(Track, int)> _topRows(List<TypedResult> rows) => [
    for (final r in rows)
      (
        _fromRow(r.readTable(tracks)),
        r.readTable(playCounts).count + r.readTable(playCounts).imported,
      ),
  ];

  /// Retire les lignes [trackPaths] (seulement celles de [reason] si donné), en une
  /// transaction, et rend `chemin du morceau -> fichier` de celles retirées.
  Future<Map<String, String?>> takeOffline(
    List<String> trackPaths, {
    OfflineReason? reason,
  }) => transaction(() async {
    final taken = <String, String?>{};
    for (final p in trackPaths) {
      final row = await offlineOf(p);
      if (row == null || (reason != null && row.reason != reason.name)) {
        continue;
      }
      taken[p] = row.filePath;
    }
    await removeOffline(taken.keys.toList());
    return taken;
  });

  /// Le Top 100 ne garde plus [trackPaths] tout seul (l'utilisateur les a retirés).
  Future<void> blockAutoKeep(List<String> trackPaths) => batch(
    (b) => b.insertAll(autoKeepBlocks, [
      for (final p in trackPaths) AutoKeepBlocksCompanion.insert(trackPath: p),
    ], mode: InsertMode.insertOrIgnore),
  );

  /// Lève le blocage de [trackPaths] (un « Garder » de l'utilisateur).
  Future<void> unblockAutoKeep(List<String> trackPaths) =>
      (delete(autoKeepBlocks)..where((b) => b.trackPath.isIn(trackPaths))).go();

  Future<Set<String>> autoKeepBlocked() async => {
    for (final b in await select(autoKeepBlocks).get()) b.trackPath,
  };

  /// Les copies `top100` (finies ou en file), de la moins écoutée à la plus écoutée
  /// (le classement du Top 100 à l'envers) : celles qui ont quitté le Top viennent d'abord.
  Future<List<OfflineRow>> top100ByLeastPlayed() async {
    final rows = await top100Offline();
    final plays = {
      for (final c in await select(playCounts).get())
        c.path: (c.count + c.imported, c.lastPlayed),
    };
    rows.sort((a, b) {
      final x = plays[a.trackPath], y = plays[b.trackPath];
      final c = (x?.$1 ?? 0).compareTo(y?.$1 ?? 0);
      if (c != 0) return c;
      final l = (x?.$2 ?? 0).compareTo(y?.$2 ?? 0);
      return l != 0 ? l : a.trackPath.compareTo(b.trackPath);
    });
    return rows;
  }

  /// Taille que le serveur annonce pour ce morceau (0 ou absente : inconnue).
  Future<int?> trackSize(String path) async {
    final t = await (select(
      tracks,
    )..where((t) => t.path.equals(path))).getSingleOrNull();
    final s = t?.size ?? 0;
    return s > 0 ? s : null;
  }

  /// Les copies `top100` (finies ou en file).
  Future<List<OfflineRow>> top100Offline() => (select(
    offline,
  )..where((o) => o.reason.equals(OfflineReason.top100.name))).get();

  /// Remplacer : les écoutes de l'ancien fichier passent au nouveau.
  Future<void> movePlays(String from, String to) => transaction(() async {
    final old = await (select(
      playCounts,
    )..where((p) => p.path.equals(from))).getSingleOrNull();
    if (old == null) return;
    await (delete(playCounts)..where((p) => p.path.equals(from))).go();
    // la destination a déjà des écoutes : on additionne, la dernière écoute est la plus récente
    await customUpdate(
      'INSERT INTO play_counts (path, count, imported, last_played) VALUES (?, ?, ?, ?) '
      'ON CONFLICT(path) DO UPDATE SET count = count + excluded.count, '
      'imported = imported + excluded.imported, '
      'last_played = max(last_played, excluded.last_played)',
      variables: [
        Variable(to),
        Variable(old.count),
        Variable(old.imported),
        Variable(old.lastPlayed),
      ],
      updates: {playCounts},
    );
  });

  Future<LoudnessData?> _loud(String path, int mtime) =>
      (select(loudness)
            ..where((l) => l.path.equals(path) & l.mtime.equals(mtime)))
          .getSingleOrNull();

  /// LUFS mesuré pour ce fichier dans cet état, null si absent ou non mesurable.
  Future<double?> loudnessOf(String path, int mtime) async =>
      (await _loud(path, mtime))?.lufs;

  /// Déjà mesuré (ou noté non mesurable) dans cet état.
  Future<bool> hasLoudness(String path, int mtime) async =>
      await _loud(path, mtime) != null;

  Future<void> setLoudness(String path, double? lufs, int mtime) =>
      into(loudness).insertOnConflictUpdate(
        LoudnessCompanion.insert(path: path, lufs: Value(lufs), mtime: mtime),
      );

  Future<List<Track>> folderTracks(int folderId) async => (await (select(
    tracks,
  )..where((t) => t.folderId.equals(folderId))).get()).map(_fromRow).toList();

  /// Tracks of files (not server tracks), whatever folder they live in.
  Future<List<Track>> localTracks() async => (await (select(
    tracks,
  )..where((t) => t.accountId.equals('local'))).get()).map(_fromRow).toList();

  /// Every offline row (to tell our own copies from files placed by hand).
  Future<List<OfflineRow>> offlineRows() => select(offline).get();

  Future<void> markMissing(int folderId, bool missing) =>
      (update(tracks)..where((t) => t.folderId.equals(folderId))).write(
        TracksCompanion(missing: Value(missing)),
      );

  /// One row per song, the same song on several accounts shown once (see [LibraryView]):
  /// the tracks of [accounts] (null: every account) and every local file, as the SQL of a
  /// `reps` table (with `offline_state`) for [_shown]. Among the twins (same `merge_key`) the
  /// row shown is the one kept on the phone, else one with a copy under way, else the first
  /// account in the order of the accounts screen. A file on the phone stands for its server
  /// twins; local files are never merged together (each one always shows), nor two rows of
  /// one account (the server's own duplicates: its 2nd one pairs with the other account's 2nd).
  (String, List<Variable<Object>>) _reps(Set<String>? accounts) {
    final ids = accounts?.toList() ?? const <String>[];
    final filter = accounts == null
        ? ''
        : ids.isEmpty
        ? "WHERE t.account_id = 'local' "
        : "WHERE t.account_id = 'local' OR t.account_id IN "
              '(${List.filled(ids.length, '?').join(', ')}) ';
    return (
      'WITH occ AS (SELECT t.*, ROW_NUMBER() OVER '
          '(PARTITION BY t.account_id, t.merge_key ORDER BY t.path) AS n '
          'FROM tracks t $filter), '
          'ranked AS (SELECT t.*, o.state AS offline_state, '
          'ROW_NUMBER() OVER (PARTITION BY CASE '
          "WHEN t.account_id = 'local' OR t.merge_key = '' THEN t.path "
          'ELSE t.merge_key END, t.n ORDER BY '
          'CASE WHEN o.state = ? THEN 0 WHEN o.track_path IS NOT NULL THEN 1 ELSE 2 END, '
          'COALESCE(a.position, 2147483647), t.path) AS rn '
          'FROM occ t LEFT JOIN offline o ON o.track_path = t.path '
          'LEFT JOIN accounts a ON a.id = t.account_id), '
          'reps AS (SELECT * FROM ranked r WHERE r.rn = 1 AND ('
          "r.account_id = 'local' OR r.merge_key = '' OR NOT EXISTS ("
          "SELECT 1 FROM tracks l WHERE l.account_id = 'local' "
          'AND l.missing = 0 AND l.merge_key = r.merge_key))) ',
      [
        // in the order of the `?` above
        for (final i in ids) Variable.withString(i),
        Variable.withString(OfflineState.done.name),
      ],
    );
  }

  Selectable<QueryRow> _shown(
    Set<String>? accounts,
    String select, [
    List<Variable<Object>> vars = const [],
  ]) {
    final (sql, v) = _reps(accounts);
    return customSelect(
      '$sql$select',
      variables: [...v, ...vars],
      readsFrom: {tracks, offline, accountRows},
    );
  }

  Selectable<Track> _shownTracks(
    Set<String>? accounts, {
    String where = '1',
    List<Variable<Object>> vars = const [],
    required String order,
    int? limit,
  }) => _shown(
    accounts,
    'SELECT * FROM reps WHERE $where ORDER BY $order, id'
    '${limit == null ? '' : ' LIMIT $limit'}',
    vars,
  ).map((r) => _fromRow(tracks.map(r.data)));

  /// The albums shown (one per [albumMergeKey], whatever the account): name, songs, length.
  Stream<List<Album>> watchAlbums({Set<String>? accounts}) =>
      _shown(
        accounts,
        'SELECT album_merge_key AS k, MIN(album) AS name, MIN(album_key) AS sk, '
        'COUNT(*) AS c, SUM(duration_ms) AS d, MIN(path) AS cover FROM reps '
        'GROUP BY album_merge_key ORDER BY sk, name, k',
      ).watch().map(
        (rows) => [
          for (final r in rows)
            Album(
              key: r.read<String>('k'),
              name: r.read<String>('name'),
              trackCount: r.read<int>('c'),
              durationMs: r.read<int?>('d') ?? 0,
              coverTrackPath: r.read<String?>('cover'),
            ),
        ],
      );

  /// Albums ([Album.key]) whose every server track shown has a finished copy (⬇ rose de l'Accueil).
  Stream<Set<String>> watchKeptAlbums({Set<String>? accounts}) => _shown(
    accounts,
    "SELECT album_merge_key AS k FROM reps WHERE path LIKE 'subsonic://%' "
    'GROUP BY album_merge_key '
    'HAVING COUNT(*) = SUM(CASE WHEN offline_state = ? THEN 1 ELSE 0 END)',
    [Variable.withString(OfflineState.done.name)],
  ).watch().map((rows) => {for (final r in rows) r.read<String>('k')});

  /// The songs of album [key] ([Album.key]), by number, those without one at the end.
  Stream<List<Track>> watchAlbumTracks(String key, {Set<String>? accounts}) =>
      _shownTracks(
        accounts,
        where: 'album_merge_key = ?',
        vars: [Variable.withString(key)],
        order: 'track_no IS NULL, track_no, title',
      ).watch();

  Future<List<Track>> search(String q, {Set<String>? accounts}) async {
    final k = sortKey(q.trim());
    if (k.isEmpty) return [];
    return _shownTracks(
      accounts,
      where: 'instr(search_key, ?) > 0',
      vars: [Variable.withString(k)],
      order: 'search_key',
      limit: 200,
    ).get();
  }

  Stream<List<Track>> watchAllTracks({Set<String>? accounts}) =>
      _shownTracks(accounts, order: 'search_key').watch();

  Stream<bool> watchAnyMissing() {
    final c = tracks.id.count();
    return (selectOnly(tracks)
          ..addColumns([c])
          ..where(tracks.missing.equals(true)))
        .watchSingle()
        .map((r) => (r.read(c) ?? 0) > 0);
  }

  Stream<List<(String, int)>> _names(String col, Set<String>? accounts) =>
      _shown(
        accounts,
        "SELECT $col AS n, COUNT(*) AS c FROM reps WHERE $col <> '' GROUP BY $col",
      ).watch().map((rows) {
        final list = [
          for (final r in rows) (r.read<String>('n'), r.read<int>('c')),
        ];
        list.sort((a, b) => sortKey(a.$1).compareTo(sortKey(b.$1)));
        return list;
      });

  Stream<List<(String, int)>> watchArtists({Set<String>? accounts}) =>
      _names('artist', accounts);
  Stream<List<(String, int)>> watchGenres({Set<String>? accounts}) =>
      _names('genre', accounts);

  Stream<List<Track>> watchArtistTracks(
    String artist, {
    Set<String>? accounts,
  }) => _shownTracks(
    accounts,
    where: 'artist = ?',
    vars: [Variable.withString(artist)],
    order: 'album_key, track_no, title',
  ).watch();

  Stream<List<Track>> watchGenreTracks(String genre, {Set<String>? accounts}) =>
      _shownTracks(
        accounts,
        where: 'genre = ?',
        vars: [Variable.withString(genre)],
        order: 'album_key, track_no, title',
      ).watch();

  /// Every row of the song of [path] (same `merge_key` on the phone or another account,
  /// [path] included): local files first, then the accounts in the order of the accounts
  /// screen. Rows of a removed account are left out. Empty when [path] is not in the library.
  Future<List<Track>> twinsOf(String path) => customSelect(
    'SELECT t.* FROM tracks t LEFT JOIN accounts a ON a.id = t.account_id '
    "WHERE t.merge_key <> '' "
    'AND t.merge_key = (SELECT merge_key FROM tracks WHERE path = ?) '
    'AND (t.path = ? OR t.account_id <> '
    '(SELECT account_id FROM tracks WHERE path = ?)) '
    "AND (t.account_id = 'local' OR a.id IS NOT NULL) "
    "ORDER BY t.account_id <> 'local', COALESCE(a.position, 0), t.path",
    variables: [for (var i = 0; i < 3; i++) Variable.withString(path)],
    readsFrom: {tracks, accountRows},
  ).map((r) => _fromRow(tracks.map(r.data))).get();

  /// Songs on more than one row: `merge_key` → (path, account) in [twinsOf]'s order
  /// (rows of one account included: the reader keeps the other accounts' ones).
  Stream<Map<String, List<(String, String)>>> watchTwins() =>
      customSelect(
        'SELECT t.path AS p, t.account_id AS acc, t.merge_key AS k FROM tracks t '
        'LEFT JOIN accounts a ON a.id = t.account_id '
        'WHERE t.merge_key IN (SELECT merge_key FROM tracks '
        "WHERE merge_key <> '' GROUP BY merge_key HAVING COUNT(*) > 1) "
        "AND (t.account_id = 'local' OR a.id IS NOT NULL) "
        "ORDER BY t.merge_key, t.account_id <> 'local', "
        'COALESCE(a.position, 0), t.path',
        readsFrom: {tracks, accountRows},
      ).watch().map((rows) {
        final m = <String, List<(String, String)>>{};
        for (final r in rows) {
          (m[r.read<String>('k')] ??= []).add((
            r.read<String>('p'),
            r.read<String>('acc'),
          ));
        }
        return m;
      });

  /// The finished or queued copy of another row of the song of [path], if any (a
  /// « Garder » makes no second copy of the same song).
  Future<OfflineRow?> twinOffline(String path) => customSelect(
    'SELECT o.* FROM offline o JOIN tracks t ON t.path = o.track_path '
    "WHERE t.merge_key <> '' "
    'AND t.merge_key = (SELECT merge_key FROM tracks WHERE path = ?) '
    'AND t.account_id <> (SELECT account_id FROM tracks WHERE path = ?) '
    'AND o.state IN (?, ?) '
    'ORDER BY o.state = ? DESC, o.track_path LIMIT 1',
    variables: [
      Variable.withString(path),
      Variable.withString(path),
      Variable.withString(OfflineState.done.name),
      Variable.withString(OfflineState.queued.name),
      Variable.withString(OfflineState.done.name),
    ],
    readsFrom: {tracks, offline},
  ).map((r) => offline.map(r.data)).getSingleOrNull();

  /// The accounts' ids in the order of the accounts screen.
  Stream<List<String>> watchAccountIds() =>
      (select(accountRows)..orderBy([(a) => OrderingTerm.asc(a.position)]))
          .watch()
          .map((rows) => [for (final r in rows) r.id]);
}
