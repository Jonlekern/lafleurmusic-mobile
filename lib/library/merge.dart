import 'models.dart';

/// Clé de fusion : le même morceau sur deux comptes donne la même clé.
/// Album, titre (sans accents ni casse, sans espaces autour) et numéro de piste
/// (vide s'il manque), séparés par NUL pour que les champs ne se mélangent pas.
String mergeKey(Track t) =>
    '${sortKey(t.album).trim()}\u0000${sortKey(t.title).trim()}\u0000${t.trackNo ?? ''}';
