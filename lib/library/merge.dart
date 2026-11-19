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

/// Un album, le même sur tous les comptes : artiste de l'album et nom de l'album, normalisés
/// comme [mergeKey]. Sans artiste d'album (fichiers posés à la main : le lecteur de tags n'en
/// lit pas), l'album est son nom seul, comme avant : un album compilé d'artistes différents
/// reste un seul album au lieu d'un album par artiste.
String albumMergeKey(Track t) =>
    '${_norm(t.albumArtist)}\u0000${_norm(t.album)}';
