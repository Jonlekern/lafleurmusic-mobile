import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import '../offline/paths.dart';
import '../sources/remote_key.dart';
import '../settings.dart' show AlbumSort;
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
  // quand la ligne a été enregistrée la première fois (ms) ; jamais réécrite ensuite
  IntColumn get addedAt => integer().withDefault(const Constant(0))();
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

/// Les playlists qui vivent seulement sur le téléphone (plan 9), sans aucun compte.
@DataClassName('PhonePlaylistRow')
class PhonePlaylists extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();

  /// La pochette choisie : un fichier du dossier de l'appli (nom seul), null = la mosaïque.
  TextColumn get coverFile => text().nullable()();
  IntColumn get createdAt => integer()(); // ms
}

/// Les morceaux d'une playlist du téléphone, dans l'ordre (`position`), désignés par leur clé
/// (`subsonic://…`, `jellyfin://…`, `plex://…` ou un chemin local). `mergeKey` : la clé de fusion du
/// morceau quand il a été ajouté, pour retrouver le même morceau ailleurs si son compte s'en va.
@DataClassName('PhonePlaylistItemRow')
class PhonePlaylistItems extends Table {
  IntColumn get playlistId => integer()();
  IntColumn get position => integer()();
  TextColumn get trackPath => text()();
  TextColumn get mergeKey => text().withDefault(const Constant(''))();
  @override
  Set<Column> get primaryKey => {playlistId, position};
}

/// Pourquoi l'utilisateur garde un morceau : `album:<albumMergeKey>`, `playlist:<compte>/<id>`
/// ou `song` (règle Q13). Retirer un album ou une playlist n'efface que les morceaux qui n'ont
/// plus aucune raison (jumeaux compris).
@DataClassName('KeepOriginRow')
class KeepOrigins extends Table {
  TextColumn get trackPath => text()();
  TextColumn get origin => text()();
  @override
  Set<Column> get primaryKey => {trackPath, origin};
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
    KeepOrigins,
    PhonePlaylists,
    PhonePlaylistItems,
  ],
)
class LibraryDb extends _$LibraryDb {
  LibraryDb(super.e);

  // v2 : copies hors ligne et écoutes en attente. v3 : morceaux retirés du Top 100 par l'utilisateur.
  // v4 : clé de fusion, écoutes importées, playlists des serveurs.
  // v5 : date d'ajout de chaque morceau (tri « Ajout récent »).
  // v6 : playlists du téléphone (plan 9).
  @override
  int get schemaVersion => 6;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    // tout ou rien : drift n'ouvre pas de transaction ici, et une appli tuée au milieu
    // laisserait des colonnes ajoutées sous l'ancienne version (« duplicate column » ensuite)
    onUpgrade: (m, from, to) => transaction(() async {
      if (from < 2) {
        await m.createTable(offline);
        await m.createTable(pendingScrobbles);
      }
      if (from < 3) await m.createTable(autoKeepBlocks);
      // avant la v4 : son code lit toutes les colonnes de `tracks`, `added_at` comprise
      if (from < 5) {
        await m.addColumn(tracks, tracks.addedAt);
        // date de modification du fichier si on la connaît, sinon le moment de la mise à jour
        await customStatement(
          'UPDATE tracks SET added_at = CASE WHEN mtime > 0 THEN mtime ELSE ? END',
          [DateTime.now().millisecondsSinceEpoch],
        );
      }
      if (from < 4) {
        await m.addColumn(tracks, tracks.mergeKey);
        await m.createIndex(tracksMergeKey);
        await m.addColumn(tracks, tracks.albumMergeKey);
        await m.createIndex(tracksAlbumMergeKey);
        await m.createTable(playlists);
        await m.createTable(playlistItems);
        await m.createTable(keptPlaylists);
        await m.createTable(keepOrigins);
        // les copies gardées par l'utilisateur avant la v4 : raison inconnue (un album ou le
        // morceau), qui n'empêche pas de retirer l'album (KeepOrigin.legacy)
        await customStatement(
          'INSERT OR IGNORE INTO keep_origins (track_path, origin) '
          "SELECT track_path, 'legacy' FROM offline WHERE reason = 'user'",
        );
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
        await _relinkAlbums({for (final r in rows) albumNameKey(r.album)});
      }
      if (from < 6) {
        await m.createTable(phonePlaylists);
        await m.createTable(phonePlaylistItems);
      }
    }),
  );

  /// Met en file les morceaux [trackPaths] ; ne rétrograde jamais `user` en `top100`.
  /// Une copie déjà faite reste ; une copie abandonnée repart à zéro.
  Future<void> queueOffline(List<String> trackPaths, OfflineReason reason) =>
      transaction(() async {
        final now = DateTime.now().millisecondsSinceEpoch;
        // retirés par l'utilisateur (ou un jumeau) : le Top 100 ne les remet pas en file
        // (relu ici, dans la transaction)
        for (final (i, p) in trackPaths.indexed) {
          if (reason == OfflineReason.top100 && await autoKeepBlockedFor(p)) {
            continue;
          }
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
                for (final scheme in remoteSchemes) {
                  final prefix = '$scheme$acc/';
                  w =
                      w &
                      o.trackPath.substr(1, prefix.length).equals(prefix).not();
                }
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

  /// The queued row [from] is now [to]'s (a twin on an account that answers), in the same
  /// place in the queue, with its reason. False if [from] is no longer queued or [to] has a row.
  Future<bool> moveQueued(String from, String to) => transaction(() async {
    final row = await offlineOf(from);
    if (row == null || row.state != OfflineState.queued.name) return false;
    if (await offlineOf(to) != null) return false;
    await into(offline).insert(
      OfflineCompanion.insert(
        trackPath: to,
        addedAt: row.addedAt,
        reason: row.reason,
        state: OfflineState.queued.name,
      ),
    );
    await (delete(offline)..where((o) => o.trackPath.equals(from))).go();
    return true;
  });

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
    addedAt: r.addedAt,
    size: r.size,
    missing: r.missing,
    albumGroup: r.albumMergeKey,
  );

  Future<void> upsertTrack(Track t) => upsertTracks([t]);

  /// Writes [list] (same path: every column replaced), then settles the albums of those
  /// names (rule Q5b, [_relinkAlbums]).
  Future<void> upsertTracks(List<Track> list) => transaction(() async {
    // the album names these paths had (a renamed album leaves its old name to settle too)
    final old = <String>{};
    for (var i = 0; i < list.length; i += 500) {
      final chunk = [for (final t in list.skip(i).take(500)) t.path];
      for (final r
          in await (selectOnly(tracks)
                ..addColumns([tracks.album])
                ..where(tracks.path.isIn(chunk)))
              .get()) {
        old.add(albumNameKey(r.read(tracks.album)!));
      }
    }
    await _upsert(list);
    await _relinkAlbums({...old, for (final t in list) albumNameKey(t.album)});
  });

  /// Rule Q5b: files placed by hand without album artist (key `name NUL`) join the server
  /// album of the same name that has one of their songs (title + number), the one with the
  /// most such songs; otherwise they keep their own key. Run for the album names [names]
  /// after any write of tracks of those names.
  Future<void> _relinkAlbums(Set<String> names) async {
    for (final n in names) {
      final rows = await customSelect(
        'SELECT * FROM tracks WHERE album_merge_key >= ? AND album_merge_key < ?',
        variables: [
          Variable.withString('$n\u0000'),
          Variable.withString('$n\u0001'),
        ],
        readsFrom: {tracks},
      ).map((r) => tracks.map(r.data)).get();
      final loose = [
        for (final r in rows)
          if (r.accountId == 'local' && r.albumArtist.isEmpty) r,
      ];
      if (loose.isEmpty) continue;
      final mine = {for (final r in loose) songKey(_fromRow(r))};
      final hits = <String, Set<String>>{};
      for (final r in rows) {
        if (r.accountId == 'local' || r.albumArtist.isEmpty) continue;
        final song = songKey(_fromRow(r));
        if (mine.contains(song)) (hits[r.albumMergeKey] ??= {}).add(song);
      }
      var target = '$n\u0000';
      var best = 0;
      for (final e in hits.entries) {
        final c = e.value.length;
        if (c > best || (c == best && e.key.compareTo(target) < 0)) {
          best = c;
          target = e.key;
        }
      }
      final moved = [
        for (final r in loose)
          if (r.albumMergeKey != target) r.id,
      ];
      if (moved.isEmpty) continue;
      await (update(tracks)..where((t) => t.id.isIn(moved))).write(
        TracksCompanion(albumMergeKey: Value(target)),
      );
    }
  }

  Future<void> _upsert(List<Track> list) => batch((b) {
    final now = DateTime.now().millisecondsSinceEpoch;
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
        addedAt: Value(
          t.addedAt > 0 ? t.addedAt : (t.mtime > 0 ? t.mtime : now),
        ),
        size: t.size,
        missing: Value(t.missing),
        searchKey: sortKey('${t.title}\n${t.artist}\n${t.album}'),
      );
      // même chemin : on remplace toutes les colonnes (le chemin est la clé)
      b.insert(
        tracks,
        row,
        onConflict: DoUpdate(
          // la date d'ajout reste celle de la première fois
          (_) => row.copyWith(
            path: const Value.absent(),
            addedAt: const Value.absent(),
          ),
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
                addedAt: t.addedAt,
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
    final names = {
      for (final r
          in await (selectOnly(tracks)
                ..addColumns([tracks.album])
                ..where(tracks.path.isIn(paths)))
              .get())
        albumNameKey(r.read(tracks.album)!),
    };
    await (delete(tracks)..where((t) => t.path.isIn(paths))).go();
    await _relinkAlbums(names);
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

  /// The [limit] most played songs (files missing from the disk hidden) with their
  /// merged number of listens, one row per song: the same song on several accounts is
  /// one rank, shown by the row of the merged view ([_reps]). [accounts]: only these
  /// accounts and the files on the phone are shown (null: all); the hidden accounts'
  /// listens still count.
  Stream<List<(Track, int)>> watchTop(int limit, {Set<String>? accounts}) {
    final (sql, v) = _topSql(limit, accounts);
    return customSelect(
      sql,
      variables: v,
      readsFrom: {tracks, offline, accountRows, playCounts},
    ).watch().map(_topRows);
  }

  /// The same ranking, once (the Top 100 kept on the phone: all accounts).
  Future<List<(Track, int)>> top(int limit) async {
    final (sql, v) = _topSql(limit, null);
    return _topRows(
      await customSelect(
        sql,
        variables: v,
        readsFrom: {tracks, offline, accountRows, playCounts},
      ).get(),
    );
  }

  /// The merged listens of a song: the server's own count is per account, so the value
  /// of a group of twins is `max(imported of the twins) + sum(count of the twins)`
  /// (what the servers knew, at most; plus every listen made in the app). Twins are
  /// the rows with one `merge_key` on other accounts, the n-th duplicate of an account
  /// pairing with the n-th of the other (as in [_reps]); local files are never grouped
  /// together. [base] is SQL naming a CTE `base(path)`, the songs to value: the result
  /// has `m(rp, imp, cnt, lp)` for each of them that was played.
  static const _mergedPlays =
      'nn AS (SELECT t.path, t.account_id, t.merge_key, ROW_NUMBER() OVER '
      '(PARTITION BY t.account_id, t.merge_key ORDER BY t.path) AS n '
      "FROM tracks t WHERE t.merge_key <> ''), "
      'grp AS (SELECT b.path AS rp, x.path AS xp FROM base b '
      'JOIN nn r ON r.path = b.path JOIN nn x ON x.merge_key = r.merge_key '
      "AND (x.n = r.n OR x.account_id = 'local' OR r.account_id = 'local') "
      "AND (x.account_id <> 'local' OR r.account_id <> 'local' OR x.path = r.path) "
      'UNION ALL SELECT b.path, b.path FROM base b '
      'WHERE b.path NOT IN (SELECT path FROM nn)), '
      'm AS (SELECT g.rp, MAX(p.imported) AS imp, SUM(p.count) AS cnt, '
      'MAX(p.last_played) AS lp FROM grp g JOIN play_counts p ON p.path = g.xp '
      'GROUP BY g.rp) ';

  (String, List<Variable<Object>>) _topSql(int limit, Set<String>? accounts) {
    final (reps, v) = _reps(accounts);
    return (
      '$reps, base AS (SELECT path FROM reps WHERE missing = 0), $_mergedPlays'
          'SELECT r.*, m.imp + m.cnt AS plays FROM reps r JOIN m ON m.rp = r.path '
          'ORDER BY plays DESC, m.lp DESC, r.id LIMIT $limit',
      v,
    );
  }

  List<(Track, int)> _topRows(List<QueryRow> rows) => [
    for (final r in rows) (_fromRow(tracks.map(r.data)), r.read<int>('plays')),
  ];

  /// Retire les lignes [trackPaths] (seulement celles de [reason] si donné), en une
  /// transaction, et rend `chemin du morceau -> (fichier, alike)` de celles retirées :
  /// [alike] = les fichiers que d'autres lignes nomment encore et qui ne diffèrent du sien
  /// que par la casse (tous alphabets) ; deux lignes peuvent nommer un même fichier (une
  /// copie effacée à la main libère son nom), c'est à l'appelant de voir sur le disque.
  Future<Map<String, ({String? rel, List<String> alike})>> takeOffline(
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
    final byName = <String, List<String>>{};
    if (taken.values.any((rel) => rel != null)) {
      // en Dart : le lower() de SQLite ne connaît que l'ASCII (« Été » ≠ « été »)
      for (final r in await (select(
        offline,
      )..where((o) => o.filePath.isNotNull())).get()) {
        (byName[r.filePath!.toLowerCase()] ??= []).add(r.filePath!);
      }
    }
    return {
      for (final e in taken.entries)
        e.key: (
          rel: e.value,
          alike: e.value == null
              ? const <String>[]
              : byName[e.value!.toLowerCase()] ?? const <String>[],
        ),
    };
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
      for (final r in await customSelect(
        'WITH base AS (SELECT DISTINCT track_path AS path FROM offline '
        "WHERE reason = ?), $_mergedPlays"
        'SELECT rp, imp + cnt AS plays, lp FROM m',
        variables: [Variable.withString(OfflineReason.top100.name)],
        readsFrom: {tracks, offline, playCounts},
      ).get())
        r.read<String>('rp'): (r.read<int>('plays'), r.read<int>('lp')),
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
  /// [scope] (SQL on the tracks' columns, with [scopeVars]) limits the work to the songs
  /// having a row that matches it: the caller still filters the rows shown.
  (String, List<Variable<Object>>) _reps(
    Set<String>? accounts, {
    String? scope,
    List<Variable<Object>> scopeVars = const [],
  }) {
    final ids = accounts?.toList() ?? const <String>[];
    final visible = accounts == null
        ? '1'
        : ids.isEmpty
        ? "t.account_id = 'local'"
        : "(t.account_id = 'local' OR t.account_id IN "
              '(${List.filled(ids.length, '?').join(', ')}))';
    final songs = scope == null
        ? '1'
        : "(($scope) OR t.merge_key IN (SELECT merge_key FROM tracks "
              "WHERE merge_key <> '' AND ($scope)))";
    return (
      'WITH occ AS (SELECT t.*, ROW_NUMBER() OVER '
          '(PARTITION BY t.account_id, t.merge_key ORDER BY t.path) AS n '
          'FROM tracks t WHERE $visible AND $songs), '
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
        if (scope != null) ...[...scopeVars, ...scopeVars],
        Variable.withString(OfflineState.done.name),
      ],
    );
  }

  Selectable<QueryRow> _shown(
    Set<String>? accounts,
    String select, [
    List<Variable<Object>> vars = const [],
    String? scope,
  ]) {
    final (sql, v) = _reps(accounts, scope: scope, scopeVars: vars);
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
    where == '1' ? null : where,
  ).map((r) => _fromRow(tracks.map(r.data)));

  // album, artist, genre: by disc, then number, those without one at the end
  // (files placed by hand have no disc: they count as disc 1, among the server's songs)
  static const _byDisc =
      'COALESCE(NULLIF(disc, 0), 1), track_no IS NULL, track_no, title';

  Album _albumRow(QueryRow r) => Album(
    key: r.read<String>('k'),
    name: r.read<String>('name'),
    trackCount: r.read<int>('c'),
    durationMs: r.read<int?>('d') ?? 0,
    coverTrackPath: r.read<String?>('cover'),
    artist: r.read<String>('artist'),
  );

  static const _albumCols =
      'album_merge_key AS k, MIN(album) AS name, MIN(album_key) AS sk, '
      'COUNT(*) AS c, SUM(duration_ms) AS d, MIN(path) AS cover, '
      "MIN(CASE WHEN album_artist <> '' THEN album_artist ELSE artist END) AS artist";

  /// The albums shown (one per [albumMergeKey], whatever the account): name, songs, length,
  /// in the order of [sort]. « Plus écouté » is one query: the merged listens of the songs
  /// ([_mergedPlays]) added up per album. « Ajout récent »: the oldest `added_at` of an album's
  /// rows, the newest first (an album already known on one account stays old on another).
  Stream<List<Album>> watchAlbums({
    Set<String>? accounts,
    AlbumSort sort = AlbumSort.name,
  }) {
    if (sort == AlbumSort.mostPlayed) {
      final (reps, v) = _reps(accounts);
      return customSelect(
        '$reps, base AS (SELECT path FROM reps), $_mergedPlays'
        'SELECT $_albumCols, COALESCE(SUM(m.imp + m.cnt), 0) AS plays FROM reps '
        'LEFT JOIN m ON m.rp = reps.path GROUP BY album_merge_key '
        'ORDER BY plays DESC, sk, name, k',
        variables: v,
        readsFrom: {tracks, offline, accountRows, playCounts},
      ).watch().map((rows) => [for (final r in rows) _albumRow(r)]);
    }
    final order = switch (sort) {
      // the oldest row of the album on ANY account, shown or not (rows of `reps` only
      // are the ones chosen to be shown: B ordered first must not make the album new)
      AlbumSort.recent =>
        '(SELECT MIN(t2.added_at) FROM tracks t2 '
            'WHERE t2.album_merge_key = reps.album_merge_key) DESC, sk, name, k',
      _ => 'sk, name, k',
    };
    return _shown(
      accounts,
      'SELECT $_albumCols FROM reps GROUP BY album_merge_key ORDER BY $order',
    ).watch().map((rows) {
      final list = [for (final r in rows) _albumRow(r)];
      if (sort == AlbumSort.artist) {
        // List.sort is not stable: the position given by the query (name order) breaks ties
        final keys = [for (final a in list) sortKey(a.artist)];
        final order = [for (var i = 0; i < list.length; i++) i]
          ..sort((a, b) {
            final c = keys[a].compareTo(keys[b]);
            return c != 0 ? c : a.compareTo(b);
          });
        return [for (final i in order) list[i]];
      }
      return list;
    });
  }

  /// The [limit] albums last played, the newest first, one per [albumMergeKey]: the same
  /// album played on two accounts is one. One query ([_mergedPlays] gives each song's
  /// last listen, twins included; imported server counts have no date and do not count); the listens of hidden accounts count for the song.
  Stream<List<Album>> watchRecentAlbums(int limit, {Set<String>? accounts}) {
    final (reps, v) = _reps(accounts);
    return customSelect(
      '$reps, base AS (SELECT path FROM reps), $_mergedPlays'
      'SELECT $_albumCols, MAX(m.lp) AS lp FROM reps JOIN m ON m.rp = reps.path '
      'GROUP BY album_merge_key HAVING MAX(m.lp) > 0 ORDER BY lp DESC, sk, name, k LIMIT $limit',
      variables: v,
      readsFrom: {tracks, offline, accountRows, playCounts},
    ).watch().map((rows) => [for (final r in rows) _albumRow(r)]);
  }

  /// Albums ([Album.key]) whose every server track shown has a finished copy, its own or a
  /// twin's on any account, shown or not (⬇ rose de l'Accueil).
  Stream<Set<String>> watchKeptAlbums({Set<String>? accounts}) {
    final (sql, v) = _reps(accounts);
    return customSelect(
      "${sql}SELECT r.album_merge_key AS k FROM reps r WHERE ${sqlIsRemote('r.path')} "
      'GROUP BY r.album_merge_key HAVING COUNT(*) = SUM(CASE WHEN EXISTS ('
      'SELECT 1 FROM tracks t2 JOIN offline o ON o.track_path = t2.path '
      'WHERE o.state = ? AND (t2.path = r.path OR (r.merge_key <> \'\' '
      'AND t2.merge_key = r.merge_key AND t2.account_id <> r.account_id))) '
      'THEN 1 ELSE 0 END)',
      variables: [...v, Variable.withString(OfflineState.done.name)],
      readsFrom: {tracks, offline, accountRows},
    ).watch().map((rows) => {for (final r in rows) r.read<String>('k')});
  }

  /// The songs of album [key] ([Album.key]), by number, those without one at the end.
  Stream<List<Track>> watchAlbumTracks(String key, {Set<String>? accounts}) =>
      _shownTracks(
        accounts,
        where: 'album_merge_key = ?',
        vars: [Variable.withString(key)],
        order: _byDisc,
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

  /// Whether any track is shown (one row read, not the whole library); emits only on change.
  Stream<bool> watchAnyTrack({Set<String>? accounts}) => _shown(
    accounts,
    'SELECT 1 AS x FROM reps LIMIT 1',
    const [],
    null,
  ).watch().map((rows) => rows.isNotEmpty).distinct();

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
    order: 'album_key, $_byDisc',
  ).watch();

  Stream<List<Track>> watchGenreTracks(String genre, {Set<String>? accounts}) =>
      _shownTracks(
        accounts,
        where: 'genre = ?',
        vars: [Variable.withString(genre)],
        order: 'album_key, $_byDisc',
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

  /// The rows of the song of [path] on the OTHER accounts (its twins), shown or not.
  Future<List<String>> twinPaths(String path) => customSelect(
    'SELECT t2.path AS p FROM tracks t1 JOIN tracks t2 ON t2.merge_key = t1.merge_key '
    "WHERE t1.path = ? AND t1.merge_key <> '' AND t2.account_id <> t1.account_id "
    "AND t2.account_id <> 'local' ORDER BY t2.path",
    variables: [Variable.withString(path)],
    readsFrom: {tracks},
  ).map((r) => r.read<String>('p')).get();

  /// The user removed [path] or one of its twins: the Top 100 leaves it alone (rule Q8).
  Future<bool> autoKeepBlockedFor(String path) async => (await customSelect(
    'SELECT 1 FROM auto_keep_blocks b WHERE b.track_path = ? '
    'OR b.track_path IN (SELECT t2.path FROM tracks t1 JOIN tracks t2 '
    "ON t2.merge_key = t1.merge_key WHERE t1.path = ? AND t1.merge_key <> '' "
    'AND t2.account_id <> t1.account_id) LIMIT 1',
    variables: [Variable.withString(path), Variable.withString(path)],
    readsFrom: {autoKeepBlocks, tracks},
  ).get()).isNotEmpty;

  /// The offline rows as the screens see them: each row under its own track, and for a
  /// server track the best copy of the song among its twins on any account, shown or not
  /// (done, then queued, then failed; its own first on a tie). « Retirer » then removes
  /// them all ([Downloader.forget] with `byUser`).
  Stream<Map<String, OfflineRow>> watchOfflineWithTwins() =>
      customSelect(
        'SELECT t.path AS shown, o.* FROM offline o '
        'JOIN tracks t2 ON t2.path = o.track_path '
        "JOIN tracks t ON t.merge_key = t2.merge_key AND t.merge_key <> '' "
        "AND t.account_id <> t2.account_id AND t.account_id <> 'local' "
        'UNION ALL SELECT o.track_path AS shown, o.* FROM offline o',
        readsFrom: {offline, tracks},
      ).watch().map((rows) {
        int rank(OfflineRow o) => o.state == OfflineState.done.name
            ? 0
            : o.state == OfflineState.queued.name
            ? 1
            : 2;
        final m = <String, OfflineRow>{};
        for (final r in rows) {
          final shown = r.read<String>('shown');
          final o = offline.map(r.data);
          final old = m[shown];
          final better =
              old == null ||
              rank(o) < rank(old) ||
              (rank(o) == rank(old) && o.trackPath == shown);
          if (better) m[shown] = o;
        }
        return m;
      });

  /// Replaces every playlist of [accountId] by [lists] (id, name, song paths in order;
  /// a song may come back twice), in one transaction. A playlist whose songs could not be
  /// read (`paths` null) keeps its old songs.
  Future<void> replacePlaylists(
    String accountId,
    List<({String id, String name, List<String>? paths})> lists,
  ) => transaction(() async {
    final old = {for (final l in await playlistsOf(accountId)) l.id: l.paths};
    // an id listed twice: the last one
    final byId = {for (final l in lists) l.id: l};
    await (delete(
      playlistItems,
    )..where((i) => i.accountId.equals(accountId))).go();
    await (delete(playlists)..where((p) => p.accountId.equals(accountId))).go();
    await batch((b) {
      for (final (pos, l) in byId.values.indexed) {
        b.insert(
          playlists,
          PlaylistsCompanion.insert(
            accountId: accountId,
            remoteId: l.id,
            name: l.name,
            position: pos,
          ),
        );
        final paths = l.paths ?? old[l.id] ?? const <String>[];
        for (final (i, path) in paths.indexed) {
          b.insert(
            playlistItems,
            PlaylistItemsCompanion.insert(
              accountId: accountId,
              playlistId: l.id,
              index: i,
              trackPath: path,
            ),
          );
        }
      }
    });
  });

  /// The playlists of [accountId], in the server's order, with their song paths.
  Future<List<({String id, String name, List<String> paths})>> playlistsOf(
    String accountId,
  ) async {
    final lists =
        await (select(playlists)
              ..where((p) => p.accountId.equals(accountId))
              ..orderBy([(p) => OrderingTerm.asc(p.position)]))
            .get();
    return [
      for (final l in lists)
        (
          id: l.remoteId,
          name: l.name,
          paths: await playlistPaths(accountId, l.remoteId),
        ),
    ];
  }

  /// The song paths of one playlist, in order (absent songs included). A phone playlist's
  /// songs as they play now ([_phoneShown]: the same song elsewhere when its own row is gone).
  Future<List<String>> playlistPaths(String accountId, String playlistId) =>
      accountId == phonePlaylistAccount
      ? customSelect(
          'SELECT $_phoneShown AS p FROM phone_playlist_items pi '
          'WHERE pi.playlist_id = ? ORDER BY pi.position',
          variables: [Variable.withInt(_phoneId(playlistId))],
          readsFrom: {phonePlaylistItems, tracks, accountRows},
        ).map((r) => r.read<String>('p')).get()
      : (select(playlistItems)
              ..where(
                (i) =>
                    i.accountId.equals(accountId) &
                    i.playlistId.equals(playlistId),
              )
              ..orderBy([(i) => OrderingTerm.asc(i.index)]))
            .map((i) => i.trackPath)
            .get();

  /// The name of a playlist, null if the server (or the phone) no longer has it.
  Future<String?> playlistName(String accountId, String playlistId) async {
    if (accountId == phonePlaylistAccount) {
      return (await (select(
            phonePlaylists,
          )..where((p) => p.id.equals(_phoneId(playlistId)))).getSingleOrNull())
          ?.name;
    }
    return (await (select(playlists)..where(
              (p) =>
                  p.accountId.equals(accountId) & p.remoteId.equals(playlistId),
            ))
            .getSingleOrNull())
        ?.name;
  }

  /// The id of a phone playlist named by text (-1: none, never a row).
  static int _phoneId(String playlistId) => int.tryParse(playlistId) ?? -1;

  /// SQL: the song a phone playlist item `pi` plays: its own row, else the same song on the
  /// phone or another account ([twinsOf]'s order: its account was removed), else its key
  /// (absent). The stored key never changes.
  static const _phoneShown =
      'COALESCE((SELECT t0.path FROM tracks t0 WHERE t0.path = pi.track_path), '
      '(SELECT t1.path FROM tracks t1 LEFT JOIN accounts a1 ON a1.id = t1.account_id '
      "WHERE pi.merge_key <> '' AND t1.merge_key = pi.merge_key "
      "AND (t1.account_id = 'local' OR a1.id IS NOT NULL) "
      "ORDER BY t1.account_id <> 'local', COALESCE(a1.position, 0), t1.path LIMIT 1), "
      'pi.track_path)';

  /// SQL: every playlist item, the server's and the phone's: `acc`, `pid`, `path`.
  static const _allItems =
      '(SELECT account_id AS acc, playlist_id AS pid, track_path AS path '
      'FROM playlist_items UNION ALL '
      "SELECT '$phonePlaylistAccount' AS acc, CAST(pi.playlist_id AS TEXT) AS pid, "
      '$_phoneShown AS path FROM phone_playlist_items pi)';

  /// SQL: the row `t` (a track) has a finished copy, its own or a twin's on another account.
  static const _hasDoneCopy =
      'EXISTS (SELECT 1 FROM tracks t2 JOIN offline o ON o.track_path = t2.path '
      'WHERE o.state = ? AND (t2.path = t.path OR (t.merge_key <> \'\' '
      'AND t2.merge_key = t.merge_key AND t2.account_id <> t.account_id)))';

  /// The playlists shown (the accounts of [accounts]; null: all), the accounts in the
  /// order of the accounts screen, each in the server's order; then the phone's, by name,
  /// whatever accounts are shown. A playlist whose account was removed is never shown.
  Stream<List<ServerPlaylist>> watchPlaylists({Set<String>? accounts}) {
    final ids = accounts?.toList() ?? const <String>[];
    final where = accounts == null
        ? '1'
        : ids.isEmpty
        ? '0'
        : 'p.account_id IN (${List.filled(ids.length, '?').join(', ')})';
    final vars = [for (final i in ids) Variable.withString(i)];
    final done = Variable.withString(OfflineState.done.name);
    return customSelect(
      'SELECT p.account_id AS acc, p.remote_id AS id, p.name AS name, '
      'a.name AS acc_name, '
      '(SELECT COUNT(*) FROM playlist_items i WHERE i.account_id = p.account_id '
      'AND i.playlist_id = p.remote_id) AS c, '
      '(SELECT COUNT(*) FROM playlist_items i JOIN tracks t ON t.path = i.track_path '
      'WHERE i.account_id = p.account_id AND i.playlist_id = p.remote_id) AS present, '
      '(SELECT COUNT(*) FROM playlist_items i JOIN tracks t ON t.path = i.track_path '
      'WHERE i.account_id = p.account_id AND i.playlist_id = p.remote_id '
      'AND NOT $_hasDoneCopy) AS uncopied, '
      'EXISTS (SELECT 1 FROM kept_playlists k WHERE k.account_id = p.account_id '
      'AND k.playlist_id = p.remote_id) AS rec, '
      '0 AS grp, a.position AS apos, p.position AS ppos '
      'FROM playlists p JOIN accounts a ON a.id = p.account_id '
      'WHERE $where '
      'UNION ALL '
      "SELECT '$phonePlaylistAccount' AS acc, CAST(pp.id AS TEXT) AS id, "
      "pp.name AS name, '' AS acc_name, "
      '(SELECT COUNT(*) FROM phone_playlist_items pi WHERE pi.playlist_id = pp.id) AS c, '
      '(SELECT COUNT(*) FROM phone_playlist_items pi JOIN tracks t '
      'ON t.path = $_phoneShown WHERE pi.playlist_id = pp.id) AS present, '
      '(SELECT COUNT(*) FROM phone_playlist_items pi JOIN tracks t '
      'ON t.path = $_phoneShown WHERE pi.playlist_id = pp.id '
      'AND NOT $_hasDoneCopy) AS uncopied, '
      "EXISTS (SELECT 1 FROM kept_playlists k WHERE k.account_id = '$phonePlaylistAccount' "
      'AND k.playlist_id = CAST(pp.id AS TEXT)) AS rec, '
      '1 AS grp, 0 AS apos, 0 AS ppos FROM phone_playlists pp '
      'ORDER BY grp, apos, ppos',
      variables: [done, ...vars, done],
      readsFrom: {
        playlists,
        playlistItems,
        phonePlaylists,
        phonePlaylistItems,
        tracks,
        offline,
        accountRows,
        keptPlaylists,
      },
    ).watch().asyncMap((rows) async {
      final out = <ServerPlaylist>[];
      final phone = <ServerPlaylist>[];
      for (final r in rows) {
        final acc = r.read<String>('acc'), id = r.read<String>('id');
        final present = r.read<int>('present');
        (acc == phonePlaylistAccount ? phone : out).add(
          ServerPlaylist(
            accountId: acc,
            id: id,
            name: r.read<String>('name'),
            accountName: r.read<String>('acc_name'),
            songCount: r.read<int>('c'),
            kept:
                r.read<bool>('rec') &&
                present > 0 &&
                r.read<int>('uncopied') == 0,
            covers: await _coverTracks(acc, id),
          ),
        );
      }
      phone.sort((a, b) => sortKey(a.name).compareTo(sortKey(b.name)));
      return [...out, ...phone];
    });
  }

  /// The first songs of a playlist that show 4 different albums (its mosaic).
  Future<List<Track>> _coverTracks(String acc, String id) async {
    final rows = acc == phonePlaylistAccount
        ? await customSelect(
            'SELECT t.* FROM phone_playlist_items pi JOIN tracks t '
            'ON t.path = $_phoneShown WHERE pi.playlist_id = ? AND t.has_cover = 1 '
            'ORDER BY pi.position LIMIT 200',
            variables: [Variable.withInt(_phoneId(id))],
            readsFrom: {phonePlaylistItems, tracks, accountRows},
          ).get()
        : await customSelect(
            'SELECT t.* FROM playlist_items i JOIN tracks t ON t.path = i.track_path '
            'WHERE i.account_id = ? AND i.playlist_id = ? AND t.has_cover = 1 '
            'ORDER BY i."index" LIMIT 200',
            variables: [Variable.withString(acc), Variable.withString(id)],
            readsFrom: {playlistItems, tracks},
          ).get();
    final albums = <String>{};
    return [
      for (final r in rows)
        if (albums.length < 4 && albums.add(r.read<String>('album')))
          _fromRow(tracks.map(r.data)),
    ];
  }

  /// The songs of a playlist in order, a song listed twice twice: (its path, its row, or null
  /// when the song is not in its account's library: absent). A phone playlist: (its stored
  /// key, the row it plays: its own, else the same song elsewhere, [_phoneShown]).
  Stream<List<(String, Track?)>> watchPlaylistItems(
    String accountId,
    String playlistId,
  ) =>
      (accountId == phonePlaylistAccount
              ? customSelect(
                  'SELECT pi.track_path AS item_path, t.* FROM phone_playlist_items pi '
                  'LEFT JOIN tracks t ON t.path = $_phoneShown '
                  'WHERE pi.playlist_id = ? ORDER BY pi.position',
                  variables: [Variable.withInt(_phoneId(playlistId))],
                  readsFrom: {phonePlaylistItems, tracks, accountRows},
                )
              : customSelect(
                  'SELECT i.track_path AS item_path, t.* FROM playlist_items i '
                  'LEFT JOIN tracks t ON t.path = i.track_path '
                  'WHERE i.account_id = ? AND i.playlist_id = ? ORDER BY i."index"',
                  variables: [
                    Variable.withString(accountId),
                    Variable.withString(playlistId),
                  ],
                  readsFrom: {playlistItems, tracks},
                ))
          .watch()
          .map(
            (rows) => [
              for (final r in rows)
                (
                  r.read<String>('item_path'),
                  r.read<int?>('id') == null
                      ? null
                      : _fromRow(tracks.map(r.data)),
                ),
            ],
          );

  /// For each of [paths] that has one, its finished copy: its own, else a twin's on another account.
  Future<Map<String, OfflineRow>> doneCopies(List<String> paths) async {
    final out = <String, OfflineRow>{};
    for (final path in {...paths}) {
      final rows = await customSelect(
        'SELECT o.* FROM tracks t JOIN tracks t2 ON (t2.path = t.path OR '
        "(t.merge_key <> '' AND t2.merge_key = t.merge_key "
        'AND t2.account_id <> t.account_id)) '
        'JOIN offline o ON o.track_path = t2.path '
        'WHERE t.path = ? AND o.state = ? AND o.file_path IS NOT NULL '
        'ORDER BY o.track_path <> t.path, o.track_path LIMIT 1',
        variables: [
          Variable.withString(path),
          Variable.withString(OfflineState.done.name),
        ],
        readsFrom: {tracks, offline},
      ).get();
      if (rows.isNotEmpty) out[path] = offline.map(rows.first.data);
    }
    return out;
  }

  /// One of [paths] still has an offline row, its own or a twin's, in any state (a failed
  /// copy is still kept: « Réessayer » brings it back).
  Future<bool> anyKept(List<String> paths) async {
    for (final path in {...paths}) {
      final rows = await customSelect(
        'SELECT 1 FROM offline o WHERE o.track_path = ? OR o.track_path IN '
        '(SELECT t2.path FROM tracks t1 JOIN tracks t2 ON t2.merge_key = t1.merge_key '
        "WHERE t1.path = ? AND t1.merge_key <> '' AND t2.account_id <> t1.account_id "
        "AND t2.account_id <> 'local') LIMIT 1",
        variables: [Variable.withString(path), Variable.withString(path)],
        readsFrom: {offline, tracks},
      ).get();
      if (rows.isNotEmpty) return true;
    }
    return false;
  }

  /// The playlists kept on the phone (their `.m3u8`, written by the app).
  Future<List<KeptPlaylistRow>> keptPlaylistRows() =>
      select(keptPlaylists).get();

  Stream<Set<(String, String)>> watchKeptPlaylists() =>
      select(keptPlaylists)
          .watch()
          .map((rows) => {for (final r in rows) (r.accountId, r.playlistId)});

  /// [fileName]: relative to `<root>/Playlists/`; empty while no file is written.
  Future<void> setKeptPlaylist(
    String accountId,
    String playlistId,
    String fileName,
  ) => into(keptPlaylists).insertOnConflictUpdate(
    KeptPlaylistsCompanion.insert(
      accountId: accountId,
      playlistId: playlistId,
      fileName: fileName,
    ),
  );

  /// Notée gardée (sans fichier encore) ; déjà notée : rien ne change (son fichier reste le sien).
  Future<void> addKeptPlaylist(String accountId, String playlistId) =>
      into(keptPlaylists).insert(
        KeptPlaylistsCompanion.insert(
          accountId: accountId,
          playlistId: playlistId,
          fileName: '',
        ),
        mode: InsertMode.insertOrIgnore,
      );

  Future<void> dropKeptPlaylist(String accountId, String playlistId) =>
      (delete(keptPlaylists)..where(
            (k) =>
                k.accountId.equals(accountId) & k.playlistId.equals(playlistId),
          ))
          .go();

  /// [path] and its twins on the other accounts (rule Q8 groups).
  Future<List<String>> _group(String path) async => [
    path,
    ...await twinPaths(path),
  ];

  /// The user keeps [paths] for [origin] (rule Q13).
  Future<void> addOrigins(Map<String, String> originOf) => batch((b) {
    for (final e in originOf.entries) {
      b.insert(
        keepOrigins,
        KeepOriginsCompanion.insert(trackPath: e.key, origin: e.value),
        mode: InsertMode.insertOrIgnore,
      );
    }
  });

  /// [origin] no longer keeps [paths] (nor their twins).
  Future<void> removeOrigin(String origin, List<String> paths) async {
    for (final path in {...paths}) {
      final group = await _group(path);
      await (delete(
        keepOrigins,
      )..where((o) => o.origin.equals(origin) & o.trackPath.isIn(group))).go();
    }
  }

  /// [origin] keeps nothing any more (a kept playlist dropped).
  Future<void> dropOrigin(String origin) =>
      (delete(keepOrigins)..where((o) => o.origin.equals(origin))).go();

  /// Every reason to keep [paths] goes (the user removed them one by one).
  Future<void> clearOrigins(List<String> paths) async {
    for (var i = 0; i < paths.length; i += 500) {
      final chunk = paths.skip(i).take(500).toList();
      await (delete(keepOrigins)..where((o) => o.trackPath.isIn(chunk))).go();
    }
  }

  /// The reasons the user keeps [path] or one of its twins.
  Future<Set<String>> originsOf(String path) async {
    final group = await _group(path);
    return {
      for (final o in await (select(
        keepOrigins,
      )..where((o) => o.trackPath.isIn(group))).get())
        o.origin,
    };
  }

  /// Every song kept for [from] is kept for [to] instead (a kept playlist the server no
  /// longer has: its songs stay, kept for themselves, rule Q15).
  Future<void> renameOrigin(String from, String to) => transaction(() async {
    await customStatement(
      'INSERT OR IGNORE INTO keep_origins (track_path, origin) '
      'SELECT track_path, ? FROM keep_origins WHERE origin = ?',
      [to, from],
    );
    await (delete(keepOrigins)..where((o) => o.origin.equals(from))).go();
  });

  /// The playlist is (still) kept on the phone.
  Future<bool> isKeptPlaylist(String accountId, String playlistId) async =>
      await (select(keptPlaylists)..where(
            (k) =>
                k.accountId.equals(accountId) & k.playlistId.equals(playlistId),
          ))
          .getSingleOrNull() !=
      null;

  /// In one query, for each kept playlist: its songs in the library that have no offline row
  /// (own or a twin's on another account, any state) and that the user did not remove one
  /// by one (no auto-keep block on them or a twin). The songs it gained on the server.
  Future<Map<(String, String), List<Track>>> keptPlaylistsMissing() async {
    final rows = await customSelect(
      'SELECT DISTINCT k.account_id AS k_acc, k.playlist_id AS k_id, t.* '
      'FROM kept_playlists k JOIN $_allItems i ON i.acc = k.account_id '
      'AND i.pid = k.playlist_id JOIN tracks t ON t.path = i.path '
      'WHERE NOT EXISTS (SELECT 1 FROM offline o WHERE o.track_path = t.path) '
      "AND NOT EXISTS (SELECT 1 FROM tracks t2 JOIN offline o2 ON o2.track_path = t2.path "
      "WHERE t.merge_key <> '' AND t2.merge_key = t.merge_key "
      "AND t2.account_id <> t.account_id AND t2.account_id <> 'local') "
      'AND NOT EXISTS (SELECT 1 FROM auto_keep_blocks b WHERE b.track_path = t.path '
      'OR b.track_path IN (SELECT t3.path FROM tracks t3 '
      "WHERE t.merge_key <> '' AND t3.merge_key = t.merge_key "
      'AND t3.account_id <> t.account_id)) '
      'ORDER BY k.account_id, k.playlist_id, t.path',
      readsFrom: {
        keptPlaylists,
        playlistItems,
        phonePlaylistItems,
        accountRows,
        tracks,
        offline,
        autoKeepBlocks,
      },
    ).get();
    final out = <(String, String), List<Track>>{};
    for (final r in rows) {
      (out[(r.read<String>('k_acc'), r.read<String>('k_id'))] ??= []).add(
        _fromRow(tracks.map(r.data)),
      );
    }
    return out;
  }

  /// The playlists of a removed account go with it; the `.m3u8` of a kept one is then
  /// deleted by `PlaylistFiles` and its songs stay kept for themselves (rules Q10, Q15).
  Future<void> deleteAccountPlaylists(String accountId) async {
    await (delete(
      playlistItems,
    )..where((i) => i.accountId.equals(accountId))).go();
    await (delete(playlists)..where((p) => p.accountId.equals(accountId))).go();
  }

  /// The accounts' ids in the order of the accounts screen.
  Stream<List<String>> watchAccountIds() =>
      (select(accountRows)..orderBy([(a) => OrderingTerm.asc(a.position)]))
          .watch()
          .map((rows) => [for (final r in rows) r.id]);
}
