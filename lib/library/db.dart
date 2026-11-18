import 'package:drift/drift.dart';

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
        for (final p in trackPaths) {
          final old = await offlineOf(p);
          if (old == null) {
            await into(offline).insert(
              OfflineCompanion.insert(
                trackPath: p,
                addedAt: now,
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
  Future<OfflineRow?> nextQueued() =>
      (select(offline)
            ..where(
              (o) =>
                  o.state.equals(OfflineState.queued.name) &
                  o.failures.isSmallerThanValue(3),
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

  Future<void> deletePending(List<int> ids) =>
      (delete(pendingScrobbles)..where((p) => p.id.isIn(ids))).go();

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
  Future<void> deleteAccountTracks(String accountId) => transaction(() async {
    final paths =
        await (selectOnly(tracks)
              ..addColumns([tracks.path])
              ..where(tracks.accountId.equals(accountId)))
            .map((r) => r.read(tracks.path)!)
            .get();
    for (var i = 0; i < paths.length; i += 500) {
      await deletePaths(paths.skip(i).take(500).toList());
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
  Stream<List<(Track, int)>> watchTop(int limit) {
    final q =
        select(tracks).join([
            innerJoin(playCounts, playCounts.path.equalsExp(tracks.path)),
          ])
          ..where(tracks.missing.equals(false))
          ..orderBy([
            OrderingTerm.desc(playCounts.count),
            OrderingTerm.desc(playCounts.lastPlayed),
          ])
          ..limit(limit);
    return q.watch().map(
      (rows) => [
        for (final r in rows)
          (_fromRow(r.readTable(tracks)), r.readTable(playCounts).count),
      ],
    );
  }

  /// Remplacer : les écoutes de l'ancien fichier passent au nouveau.
  Future<void> movePlays(String from, String to) => transaction(() async {
    final old = await (select(
      playCounts,
    )..where((p) => p.path.equals(from))).getSingleOrNull();
    if (old == null) return;
    await (delete(playCounts)..where((p) => p.path.equals(from))).go();
    await into(playCounts).insertOnConflictUpdate(
      PlayCountsCompanion.insert(
        path: to,
        count: old.count,
        lastPlayed: old.lastPlayed,
      ),
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
