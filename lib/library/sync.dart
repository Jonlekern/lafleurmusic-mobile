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
  LibrarySync(this._db);
  final LibraryDb _db;

  Future<SyncResult> run(MusicSource s) async {
    var added = 0, updated = 0, removed = 0;
    var complete = true;
    final seen = <String>{};
    try {
      await for (final page in s.albums()) {
        for (final album in page) {
          final songs = await s.albumSongs(album.id);
          final r = await _store(s.accountId, album, songs, seen);
          added += r.$1;
          updated += r.$2;
        }
      }
    } on Exception {
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

  Future<int> _removeUnseen(String acc, Set<String> seen) =>
      _db.transaction(() async {
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
        for (var i = 0; i < gone.length; i += 500) {
          await _db.deletePaths(gone.skip(i).take(500).toList());
        }
        return gone.length;
      });
}
