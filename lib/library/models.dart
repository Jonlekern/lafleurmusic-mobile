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
    this.addedAt = 0,
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

  /// When the library first stored it (ms); 0 = not yet stored (the db then stamps it).
  final int addedAt;
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
    this.artist = '',
  });

  /// Son identité, la même sur tous les comptes (`albumMergeKey`) : ce qu'on demande pour ses morceaux.
  final String key;
  final String name;
  final int trackCount;
  final int durationMs;
  final String? coverTrackPath;

  /// L'artiste de l'album (artiste de l'album, sinon celui du morceau) : tri « Artiste ».
  final String artist;
}

/// Une playlist d'un serveur telle que l'Accueil la montre : jamais fusionnée entre comptes.
/// The account id under which phone playlists go wherever a playlist is named by
/// (account, id): `KeptPlaylists`, keep origins, [ServerPlaylist]. Never a real account id.
const phonePlaylistAccount = 'phone';

/// A playlist, wherever it lives: on the phone ([PlaylistRef.phone]) or on a server.
sealed class PlaylistRef {
  const PlaylistRef();
  const factory PlaylistRef.phone(int id) = PhonePlaylistRef;
  const factory PlaylistRef.server(String accountId, String remoteId) =
      ServerPlaylistRef;

  /// (account, id) as the tables of kept playlists name it.
  String get accountId;
  String get playlistId;
}

class PhonePlaylistRef extends PlaylistRef {
  const PhonePlaylistRef(this.id);
  final int id;
  @override
  String get accountId => phonePlaylistAccount;
  @override
  String get playlistId => '$id';
  @override
  bool operator ==(Object other) => other is PhonePlaylistRef && other.id == id;
  @override
  int get hashCode => id.hashCode;
  @override
  String toString() => 'PlaylistRef.phone($id)';
}

class ServerPlaylistRef extends PlaylistRef {
  const ServerPlaylistRef(this.accountId, this.remoteId);
  @override
  final String accountId;
  final String remoteId;
  @override
  String get playlistId => remoteId;
  @override
  bool operator ==(Object other) =>
      other is ServerPlaylistRef &&
      other.accountId == accountId &&
      other.remoteId == remoteId;
  @override
  int get hashCode => Object.hash(accountId, remoteId);
  @override
  String toString() => 'PlaylistRef.server($accountId, $remoteId)';
}

/// A playlist as the lists show it: a server's, or one on the phone ([onPhone]: its
/// [accountId] is [phonePlaylistAccount], its [accountName] empty).
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

  /// It lives on the phone only (no account).
  bool get onPhone => accountId == phonePlaylistAccount;

  PlaylistRef get ref => onPhone
      ? PlaylistRef.phone(int.parse(id))
      : PlaylistRef.server(accountId, id);

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
