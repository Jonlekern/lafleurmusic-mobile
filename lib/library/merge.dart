import 'models.dart';

String _norm(String s) => sortKey(s).trim().replaceAll(RegExp(r'\s+'), ' ');

/// Clé de fusion : le même morceau sur deux comptes donne la même clé.
/// Artiste de l'album (l'artiste du morceau s'il manque), album, titre et numéro de piste
/// (vide s'il manque). Chaque texte est sans accents ni casse, espaces réduits ; les champs
/// sont séparés par NUL pour ne pas se mélanger. Deux albums de même nom d'artistes
/// différents ne fusionnent donc pas.
String mergeKey(Track t) =>
    '${_norm(t.albumArtist.isEmpty ? t.artist : t.albumArtist)}\u0000'
    '${_norm(t.album)}\u0000${_norm(t.title)}\u0000${t.trackNo ?? ''}';

/// Un album, le même sur tous les comptes : nom de l'album puis artiste de l'album, normalisés
/// comme [mergeKey] (le nom d'abord : tous les albums d'un même nom se suivent dans l'index).
/// Sans artiste d'album (fichiers posés à la main : le lecteur de tags n'en lit pas), l'album
/// est son nom seul : un album compilé d'artistes différents reste un seul album. Un tel album
/// rejoint ensuite l'album d'un serveur du même nom qui a un de ses morceaux (voir
/// `LibraryDb`, règle Q5b).
String albumMergeKey(Track t) =>
    '${albumNameKey(t.album)}\u0000${_norm(t.albumArtist)}';

/// L'album où [t] est montré : celui que la bibliothèque a retenu, sinon le sien.
String albumKeyOf(Track t) => t.albumGroup ?? albumMergeKey(t);

/// Le nom d'album normalisé : début de [albumMergeKey].
String albumNameKey(String album) => _norm(album);

/// Un morceau dans son album : titre normalisé et numéro (fin de [mergeKey]).
String songKey(Track t) => '${_norm(t.title)}\u0000${t.trackNo ?? ''}';
