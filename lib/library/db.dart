import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import 'models.dart';

part 'db.g.dart';

@DataClassName('TrackRow')
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
}

/// Écoutes (Top 100) : une ligne par fichier écouté.
class PlayCounts extends Table {
  TextColumn get path => text()();
  IntColumn get count => integer()();
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

/// Écoutes faites hors ligne, à envoyer au serveur (scrobble) au retour du réseau.
@DataClassName('PendingScrobble')
class PendingScrobbles extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get accountId => text()();
  TextColumn get remoteId => text()();
  IntColumn get at => integer()(); // ms
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
  ],
)
class LibraryDb extends _$LibraryDb {
  LibraryDb(super.e);

  // v2 : copies hors ligne et écoutes en attente.
  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(offline);
        await m.createTable(pendingScrobbles);
      }
    },
  );

  /// Met en file les morceaux [trackPaths] ; ne rétrograde jamais `user` en `top100`.
  /// Une copie déjà faite reste ; une copie abandonnée repart à zéro.
  Future<void> queueOffline(List<String> trackPaths, OfflineReason reason) =>
      transaction(() async {
        final now = DateTime.now().millisecondsSinceEpoch;
        for (final (i, p) in trackPaths.indexed) {
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
  /// Sans [top100], les copies du Top 100 sont laissées en file.
  Future<OfflineRow?> nextQueued({bool top100 = true}) =>
      (select(offline)
            ..where(
              (o) =>
                  o.state.equals(OfflineState.queued.name) &
                  o.failures.isSmallerThanValue(3) &
                  (top100
                      ? const Constant(true)
                      : o.reason.equals(OfflineReason.top100.name).not()),
            )
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
    final ids = (await select(accountRows).get()).map((r) => r.id).toSet();
    final paths =
        await (selectOnly(tracks)
              ..addColumns([tracks.path, tracks.accountId])
              ..where(tracks.accountId.equals('local').not()))
            .map((r) => (r.read(tracks.path)!, r.read(tracks.accountId)!))
            .get();
    final orphans = [
      for (final (path, acc) in paths)
        if (!ids.contains(acc)) path,
    ];
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
          final row = file.existsSync()
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
                mtime: file.statSync().modified.millisecondsSinceEpoch,
                size: file.lengthSync(),
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

  /// Raises counts to [counts] (path -> count) where higher; never lowers one.
  Future<void> raisePlayCounts(Map<String, int> counts) async {
    for (final e in counts.entries) {
      await into(playCounts).insert(
        PlayCountsCompanion.insert(path: e.key, count: e.value, lastPlayed: 0),
        onConflict: DoUpdate(
          (_) => PlayCountsCompanion.custom(
            count: const CustomExpression('max(count, excluded.count)'),
          ),
          target: [playCounts.path],
        ),
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
  Stream<List<(Track, int)>> watchTop(int limit) =>
      _topQuery(limit).watch().map(_topRows);

  /// Le même classement, une fois (le Top 100 gardé sur le téléphone).
  Future<List<(Track, int)>> top(int limit) async =>
      _topRows(await _topQuery(limit).get());

  JoinedSelectStatement<HasResultSet, dynamic> _topQuery(int limit) =>
      select(tracks)
          .join([innerJoin(playCounts, playCounts.path.equalsExp(tracks.path))])
        ..where(tracks.missing.equals(false))
        ..orderBy([
          OrderingTerm.desc(playCounts.count),
          OrderingTerm.desc(playCounts.lastPlayed),
        ])
        ..limit(limit);

  List<(Track, int)> _topRows(List<TypedResult> rows) => [
    for (final r in rows)
      (_fromRow(r.readTable(tracks)), r.readTable(playCounts).count),
  ];

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
      'INSERT INTO play_counts (path, count, last_played) VALUES (?, ?, ?) '
      'ON CONFLICT(path) DO UPDATE SET count = count + excluded.count, '
      'last_played = max(last_played, excluded.last_played)',
      variables: [Variable(to), Variable(old.count), Variable(old.lastPlayed)],
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

  Stream<List<Album>> watchAlbums() {
    final count = tracks.id.count();
    final dur = tracks.durationMs.sum();
    final cover = tracks.path.min();
    final q = selectOnly(tracks)
      ..addColumns([tracks.album, tracks.albumKey, count, dur, cover])
      ..groupBy([tracks.album, tracks.albumKey])
      ..orderBy([
        OrderingTerm.asc(tracks.albumKey),
        OrderingTerm.asc(tracks.album),
      ]);
    return q.watch().map(
      (rows) => rows
          .map(
            (r) => Album(
              name: r.read(tracks.album)!,
              trackCount: r.read(count)!,
              durationMs: r.read(dur) ?? 0,
              coverTrackPath: r.read(cover),
            ),
          )
          .toList(),
    );
  }

  Stream<List<Track>> watchAlbumTracks(String album) =>
      (select(tracks)
            ..where((t) => t.album.equals(album))
            ..orderBy([
              (t) => OrderingTerm(
                expression: t.trackNo.isNull(),
                mode: OrderingMode.asc,
              ),
              (t) => OrderingTerm.asc(t.trackNo),
              (t) => OrderingTerm.asc(t.title),
            ]))
          .watch()
          .map((rows) => rows.map(_fromRow).toList());

  Future<List<Track>> search(String q) async {
    final k = sortKey(q.trim());
    if (k.isEmpty) return [];
    final rows =
        await (select(tracks)
              ..where((t) => t.searchKey.contains(k))
              ..limit(200))
            .get();
    return rows.map(_fromRow).toList();
  }

  Stream<List<Track>> watchAllTracks() =>
      (select(tracks)..orderBy([(t) => OrderingTerm.asc(t.searchKey)]))
          .watch()
          .map((rows) => rows.map(_fromRow).toList());

  Stream<bool> watchAnyMissing() {
    final c = tracks.id.count();
    return (selectOnly(tracks)
          ..addColumns([c])
          ..where(tracks.missing.equals(true)))
        .watchSingle()
        .map((r) => (r.read(c) ?? 0) > 0);
  }

  Stream<List<(String, int)>> _names(GeneratedColumn<String> col) {
    final c = tracks.id.count();
    final q = selectOnly(tracks)
      ..addColumns([col, c])
      ..where(col.equals('').not())
      ..groupBy([col]);
    return q.watch().map((rows) {
      final list = [for (final r in rows) (r.read(col)!, r.read(c)!)];
      list.sort((a, b) => sortKey(a.$1).compareTo(sortKey(b.$1)));
      return list;
    });
  }

  Stream<List<(String, int)>> watchArtists() => _names(tracks.artist);
  Stream<List<(String, int)>> watchGenres() => _names(tracks.genre);

  Stream<List<Track>> _tracksWhere(
    Expression<bool> Function($TracksTable t) where,
  ) =>
      (select(tracks)
            ..where(where)
            ..orderBy([
              (t) => OrderingTerm.asc(t.albumKey),
              (t) => OrderingTerm.asc(t.trackNo),
              (t) => OrderingTerm.asc(t.title),
            ]))
          .watch()
          .map((rows) => rows.map(_fromRow).toList());

  Stream<List<Track>> watchArtistTracks(String artist) =>
      _tracksWhere((t) => t.artist.equals(artist));
  Stream<List<Track>> watchGenreTracks(String genre) =>
      _tracksWhere((t) => t.genre.equals(genre));
}
