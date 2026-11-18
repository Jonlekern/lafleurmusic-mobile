/// A music source (Subsonic today) as seen by sync and playback.
class SourceAlbum {
  const SourceAlbum({
    required this.id,
    required this.name,
    required this.artist,
    this.coverId,
    this.songCount = 0,
  });

  final String id, name, artist;
  final String? coverId;
  final int songCount;
}

class SourceSong {
  const SourceSong({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.albumArtist,
    this.genre = '',
    this.track,
    this.disc,
    this.durationMs = 0,
    this.size = 0,
    this.coverId,
    this.suffix,
    this.replayGainTrack,
    this.replayGainAlbum,
    this.playCount = 0,
  });

  final String id, title, artist, album, albumArtist, genre;
  final int? track, disc;
  final int durationMs, size;
  final String? coverId, suffix;
  final double? replayGainTrack, replayGainAlbum;
  final int playCount;
}

enum TestResult { ok, unreachable, wrongPassword, headerRefused, notSubsonic }

abstract interface class MusicSource {
  String get accountId;
  Future<TestResult> test();

  /// One page at a time, fetched lazily.
  Stream<List<SourceAlbum>> albums({int pageSize = 500});
  Future<List<SourceSong>> albumSongs(String albumId);

  /// Full authenticated URL (account headers are separate: [headers]).
  Uri streamUri(String songId);
  Uri coverUri(String coverId, int size);
  Map<String, String> get headers;
  Future<void> scrobble(String songId, DateTime at);
}
