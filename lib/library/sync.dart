import '../sources/source.dart';
import 'db.dart';
import 'models.dart';

String trackKey(String accountId, String songId) =>
    'subsonic://$accountId/$songId';

class SyncResult {
  const SyncResult({
    required this.added,
    required this.updated,
    required this.removed,
    required this.complete,
  });
  final int added, updated, removed;
  final bool complete;
}

/// Copies a server library into the local tracks table, one album at a time.
class LibrarySync {
  /// [copyRoot]: where the kept copies live (null: unknown, finished copies are left alone).
  LibrarySync(this._db, {this.copyRoot});
  final LibraryDb _db;
  final Future<CopyRoot?> Function()? copyRoot;

  /// This many albums failing one after the other: the server is gone, stop the run.
  static const maxFailuresInARow = 5;

  Future<SyncResult> run(MusicSource s) async {
    var added = 0, updated = 0, removed = 0;
    var complete = true;
    final seen = <String>{};
    var albumCount = 0, failedInARow = 0;
    try {
      albums:
      await for (final page in s.albums()) {
        for (final album in page) {
          albumCount++;
          final List<SourceSong> songs;
          try {
            songs = await s.albumSongs(album.id);
          } on Object {
            // one album that won't read is skipped; the run is incomplete (nothing is
            // deleted) and tried again later. A server that fails every time stops it.
            complete = false;
            if (++failedInARow >= maxFailuresInARow) break albums;
            continue;
          }
          failedInARow = 0;
          final r = await _store(s.accountId, album, songs, seen);
          added += r.$1;
          updated += r.$2;
        }
      }
    } on Exception {
      complete = false;
    }
    // A server answering with no album at all (e.g. mid-rescan) must not wipe
    // an account that already has tracks.
    if (complete && albumCount == 0 && await _hasTracks(s.accountId)) {
      complete = false;
    }
    if (complete) {
      removed = await _removeUnseen(s.accountId, seen);
    }
    return SyncResult(
      added: added,
      updated: updated,
      removed: removed,
      complete: complete,
    );
  }

  Future<(int, int)> _store(
    String acc,
    SourceAlbum album,
    List<SourceSong> songs,
    Set<String> seen,
  ) async {
    final byId = {
      for (final s in songs) s.id: s,
    }; // a song listed twice counts once
    songs = byId.values.toList();
    final tracks = [
      for (final s in songs)
        Track(
          path: trackKey(acc, s.id),
          accountId: acc,
          remoteId: s.id,
          title: s.title,
          artist: s.artist,
          album: s.album,
          albumArtist: s.albumArtist,
          genre: s.genre,
          trackNo: s.track,
          disc: s.disc,
          durationMs: s.durationMs,
          hasCover: s.coverId != null,
          coverId: s.coverId,
          suffix: s.suffix,
          replayGain: s.replayGainTrack ?? s.replayGainAlbum,
          size: s.size,
        ),
    ];
    final paths = [for (final t in tracks) t.path];
    seen.addAll(paths);
    var added = 0, updated = 0;
    await _db.transaction(() async {
      final old = {
        for (final r in await (_db.select(
          _db.tracks,
        )..where((t) => t.path.isIn(paths))).get())
          r.path: r,
      };
      final changed = <Track>[];
      for (final t in tracks) {
        final o = old[t.path];
        if (o == null) {
          added++;
          changed.add(t);
        } else if (!_same(o, t)) {
          updated++;
          changed.add(t);
        }
      }
      await _db.upsertTracks(changed);
      await _db.raisePlayCounts({
        for (var i = 0; i < songs.length; i++)
          if (songs[i].playCount > 0) tracks[i].path: songs[i].playCount,
      });
    });
    return (added, updated);
  }

  static bool _same(TrackRow o, Track t) =>
      o.title == t.title &&
      o.artist == t.artist &&
      o.album == t.album &&
      o.albumArtist == t.albumArtist &&
      o.genre == t.genre &&
      o.trackNo == t.trackNo &&
      o.disc == t.disc &&
      o.durationMs == t.durationMs &&
      o.coverId == t.coverId &&
      o.suffix == t.suffix &&
      o.replayGain == t.replayGain &&
      o.size == t.size &&
      o.remoteId == t.remoteId;

  Future<bool> _hasTracks(String acc) async =>
      await (_db.select(_db.tracks)
            ..where((t) => t.accountId.equals(acc))
            ..limit(1))
          .getSingleOrNull() !=
      null;

  Future<int> _removeUnseen(String acc, Set<String> seen) async {
    final root = await copyRoot?.call();
    return _db.transaction(() async {
        final all =
            await (_db.selectOnly(_db.tracks)
                  ..addColumns([_db.tracks.path])
                  ..where(_db.tracks.accountId.equals(acc)))
                .map((r) => r.read(_db.tracks.path)!)
                .get();
        final gone = [
          for (final p in all)
            if (!seen.contains(p)) p,
        ];
        await _db.dropServerTracks(gone, root: root);
        return gone.length;
      });
  }
}
