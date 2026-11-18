/// Un morceau de la bibliothèque (une ligne de la base, reflet des tags du fichier).
class Track {
  const Track({
    this.id,
    required this.path,
    required this.folderId,
    required this.title,
    required this.artist,
    required this.album,
    this.genre = '',
    this.trackNo,
    required this.durationMs,
    required this.hasCover,
    required this.mtime,
    required this.size,
    this.missing = false,
  });

  final int? id;
  final String path;
  final int folderId;
  final String title;
  final String artist;
  final String album;
  final String genre;
  final int? trackNo;
  final int durationMs;
  final bool hasCover;
  final int mtime;
  final int size;
  final bool missing;
}

/// Un album = une playlist (les albums compilés de Johnny).
class Album {
  const Album({
    required this.name,
    required this.trackCount,
    required this.durationMs,
    this.coverTrackPath,
  });
  final String name;
  final int trackCount;
  final int durationMs;
  final String? coverTrackPath;
}

/// Clé de tri sans accents ni casse (« Été » entre « dub » et « Funk »).
String sortKey(String s) {
  const from = 'àáâãäåçèéêëìíîïñòóôõöøùúûüýÿ';
  const to = 'aaaaaaceeeeiiiinoooooouuuuyy';
  final b = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    final i = from.indexOf(ch);
    b.write(i >= 0 ? to[i] : ch);
  }
  return b
      .toString()
      .replaceAll('æ', 'ae')
      .replaceAll('œ', 'oe')
      .replaceAll('ß', 'ss');
}
