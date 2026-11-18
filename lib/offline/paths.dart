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
