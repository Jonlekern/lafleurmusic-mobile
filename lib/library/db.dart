import 'package:drift/drift.dart';

import 'models.dart';

part 'db.g.dart';

@DataClassName('TrackRow')
class Tracks extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get path => text().unique()();
  IntColumn get folderId => integer()();
  TextColumn get title => text()();
  TextColumn get artist => text()();
  TextColumn get album => text()();
  TextColumn get albumKey => text()();
  TextColumn get genre => text().withDefault(const Constant(''))();
  IntColumn get trackNo => integer().nullable()();
  IntColumn get durationMs => integer()();
  BoolColumn get hasCover => boolean()();
  IntColumn get mtime => integer()();
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

@DriftDatabase(tables: [Tracks, PlayCounts, Loudness])
class LibraryDb extends _$LibraryDb {
  LibraryDb(super.e);

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.addColumn(tracks, tracks.genre); // plan 2 : genres
        // le scan saute les fichiers inchangés : date à zéro pour qu'il relise les genres
        await customStatement('UPDATE tracks SET mtime = 0');
      }
      if (from < 3) {
        // plan 5 : Top 100 et Volume égal
        await m.createTable(playCounts);
        await m.createTable(loudness);
      }
    },
  );

  Track _fromRow(TrackRow r) => Track(
    id: r.id,
    path: r.path,
    folderId: r.folderId,
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
        folderId: t.folderId,
        title: t.title,
        artist: t.artist,
        album: t.album,
        albumKey: sortKey(t.album),
        genre: Value(t.genre),
        trackNo: Value(t.trackNo),
        durationMs: t.durationMs,
        hasCover: t.hasCover,
        mtime: t.mtime,
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
