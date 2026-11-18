import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/painting.dart' show FileImage;
import 'package:flutter_taglib/flutter_taglib.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

typedef EmbeddedCover = Future<Uint8List?> Function(String trackPath);

/// Pochette intégrée lue avec TagLib (dans un isolate).
Future<Uint8List?> taglibCover(String path) => Isolate.run(() {
  final f = TagLibFile.open(path);
  if (f == null) return null;
  try {
    return f.coverData;
  } finally {
    f.close();
  }
});

/// Pochettes réduites (64, 300, 600 px) en cache : image intégrée, sinon cover / folder / front.jpg du dossier.
class Covers {
  Covers({required this.cacheDir, this.embedded = taglibCover});
  final Directory cacheDir;
  final EmbeddedCover embedded;

  static const folderNames = [
    'cover.jpg',
    'folder.jpg',
    'front.jpg',
    'cover.png',
    'folder.png',
  ];

  File _cacheFile(String trackPath, int size) => File(
    p.join(cacheDir.path, '${sha1.convert(utf8.encode(trackPath))}-$size.jpg'),
  );

  // Résultats en mémoire, « pas de pochette » compris : l'interface redemande la même image à chaque image.
  final _memo = <String, Future<File?>>{};

  Future<File?> get(String trackPath, int size) =>
      _memo.putIfAbsent('$size|$trackPath', () => _load(trackPath, size));

  /// Après une modification de pochette : la prochaine demande relit le fichier.
  void forget(String trackPath) {
    _memo.removeWhere((k, _) => k.endsWith('|$trackPath'));
    for (final size in const [64, 300, 600]) {
      final f = _cacheFile(trackPath, size);
      FileImage(f).evict(); // même chemin de cache : sans ça, l'ancienne image reste affichée
      if (f.existsSync()) f.deleteSync();
    }
  }

  Future<File?> _load(String trackPath, int size) async {
    final cached = _cacheFile(trackPath, size);
    if (await cached.exists()) return cached;
    Uint8List? bytes = await embedded(trackPath);
    if (bytes == null || bytes.isEmpty) {
      for (final name in folderNames) {
        final f = File(p.join(p.dirname(trackPath), name));
        if (await f.exists()) {
          bytes = await f.readAsBytes();
          break;
        }
      }
    }
    if (bytes == null) return null;
    final src = bytes;
    final jpg = await Isolate.run(() {
      final image = img.decodeImage(src);
      if (image == null) return null;
      return img.encodeJpg(
        img.copyResizeCropSquare(image, size: size),
        quality: 88,
      );
    });
    if (jpg == null) return null;
    await cacheDir.create(recursive: true);
    await cached.writeAsBytes(jpg);
    return cached;
  }
}
