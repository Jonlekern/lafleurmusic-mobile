/// Album name stored at sync time for songs a Jellyfin server holds outside any album.
const unknownAlbumName = 'Album inconnu';

/// Un morceau de la bibliothèque (une ligne de la base, reflet des tags du fichier).
class Track {
  const Track({
    this.id,
    required this.path,
    this.folderId = 0,
    this.accountId = 'local',
    this.remoteId = '',
    this.albumArtist = '',
    this.disc,
    this.coverId,
    this.suffix,
    this.replayGain,
    required this.title,
    required this.artist,
    required this.album,
    this.genre = '',
    this.trackNo,
    required this.durationMs,
    required this.hasCover,
    this.mtime = 0,
    required this.size,
    this.missing = false,
    this.albumGroup,
  });

  final int? id;
  final String path;
  final int folderId;
  final String accountId; // 'local' for scanned files
  final String remoteId; // server song id
  final String albumArtist;
  final int? disc;
  final String? coverId, suffix;
  final double? replayGain;
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

  /// The album it is shown in, as the library stored it (`Tracks.albumMergeKey`; a file
  /// placed by hand may have joined a server album). Null for a track not read from the library.
  final String? albumGroup;
}

/// Un album = une playlist (les albums compilés de Johnny).
class Album {
  const Album({
    required this.key,
    required this.name,
    required this.trackCount,
    required this.durationMs,
    this.coverTrackPath,
  });

  /// Son identité, la même sur tous les comptes (`albumMergeKey`) : ce qu'on demande pour ses morceaux.
  final String key;
  final String name;
  final int trackCount;
  final int durationMs;
  final String? coverTrackPath;
}

/// Une playlist d'un serveur telle que l'Accueil la montre : jamais fusionnée entre comptes.
class ServerPlaylist {
  const ServerPlaylist({
    required this.accountId,
    required this.id,
    required this.name,
    required this.accountName,
    required this.songCount,
    required this.kept,
    this.covers = const [],
  });

  final String accountId, id, name, accountName;
  final int songCount;

  /// Gardée (« Garder » la playlist) et chacun de ses morceaux présents a une copie finie
  /// (la sienne ou celle d'un jumeau).
  final bool kept;

  /// Ses morceaux présents dans l'ordre, pour la mosaïque ([mosaicPaths]) : 4 albums au plus.
  final List<Track> covers;
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

/// Pourquoi un morceau est gardé hors ligne : choisi par l'utilisateur, ou Top 100 automatique.
enum OfflineReason { user, top100 }

/// État d'une copie hors ligne : en attente, téléchargée, abandonnée après 3 échecs.
enum OfflineState { queued, done, failed }
