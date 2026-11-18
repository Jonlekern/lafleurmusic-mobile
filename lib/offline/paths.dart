import 'dart:convert';

const _maxNameBytes = 120;

/// Un nom de fichier ou de dossier sûr sur iOS et Android : jamais de séparateur,
/// ni point de tête (fichier caché) ni point ou espace final.
String safeName(String s) {
  var out = s.replaceAll(RegExp(r'[/\\:*?"<>|\u0000-\u001f\u007f]'), '_');
  out = out.replaceFirstMapped(RegExp(r'^\.+'), (m) => '_' * m[0]!.length);
  out = _cut(out).replaceAll(RegExp(r'[ .]+$'), '');
  return out.trim().isEmpty ? '_' : out;
}

/// Coupe à [_maxNameBytes] octets UTF-8 sans couper un caractère.
String _cut(String s) {
  var bytes = 0;
  final b = StringBuffer();
  for (final r in s.runes) {
    final n = utf8.encode(String.fromCharCode(r)).length;
    if (bytes + n > _maxNameBytes) break;
    bytes += n;
    b.writeCharCode(r);
  }
  return b.toString();
}

/// Chemin relatif d'un morceau gardé : `Artiste/Album/NN Titre.ext`
/// (`D-NN` si le disque est > 1, pas de numéro s'il est inconnu).
String keptPath({
  required String albumArtist,
  required String album,
  int? disc,
  int? track,
  required String title,
  required String ext,
  String unknownArtist = 'Unknown artist',
  String unknownAlbum = 'Unknown album',
}) {
  String orElse(String s, String fallback) => s.trim().isEmpty ? fallback : s;
  final nn = track == null
      ? ''
      : '${disc != null && disc > 1 ? '$disc-' : ''}'
            '${track.toString().padLeft(2, '0')} ';
  final e = safeName(ext.startsWith('.') ? ext.substring(1) : ext);
  return '${safeName(orElse(albumArtist, unknownArtist))}/'
      '${safeName(orElse(album, unknownAlbum))}/'
      '$nn${safeName(title)}.$e';
}

/// Ajoute ` (2)`, ` (3)`… avant l'extension tant que [exists] dit oui.
String uniquePath(String rel, bool Function(String) exists) {
  if (!exists(rel)) return rel;
  final slash = rel.lastIndexOf('/');
  final dot = rel.lastIndexOf('.');
  final hasExt = dot > slash + 1;
  final stem = hasExt ? rel.substring(0, dot) : rel;
  final ext = hasExt ? rel.substring(dot) : '';
  for (var n = 2; ; n++) {
    final c = '$stem ($n)$ext';
    if (!exists(c)) return c;
  }
}

/// Marque de nos fichiers en cours, avant l'extension : `NN Titre.lafleur-part.mp3`.
/// Android 11+ ne laisse créer dans Music que des fichiers à extension audio.
const _partMark = '.lafleur-part';

/// Ancien suffixe (`NN Titre.mp3.lafleur.part`), refusé par Android : encore effacé.
const _legacyPartSuffix = '.lafleur.part';

final _partName = RegExp(r'\.lafleur-part(\.[^./\\]*)?$', caseSensitive: false);

/// Le fichier en cours de [path] (chemin du fichier final).
String partialPath(String path) {
  final slash = path.lastIndexOf('/');
  final dot = path.lastIndexOf('.');
  if (dot <= slash + 1) return '$path$_partMark';
  return '${path.substring(0, dot)}$_partMark${path.substring(dot)}';
}

/// Vrai pour nos fichiers en cours (nouveau ou ancien nom), jamais pour les `.part` des autres.
bool isPartialName(String path) =>
    _partName.hasMatch(path) || path.toLowerCase().endsWith(_legacyPartSuffix);

/// L'ancien nom du fichier en cours de [path], à effacer aussi.
String legacyPartialPath(String path) => '$path$_legacyPartSuffix';
