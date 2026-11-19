import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/painting.dart' show FileImage;
import 'package:flutter_taglib/flutter_taglib.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../sources/remote_key.dart';

typedef EmbeddedCover = Future<Uint8List?> Function(String trackPath);

/// Cover of a server track (`subsonic://…`, `jellyfin://…`), fetched with the account headers.
typedef RemoteCover = Future<Uint8List?> Function(String trackPath, int size);

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
/// Morceau du serveur : téléchargée par [remote], même cache disque ; avec [remoteKey] (compte + id de
/// pochette), une seule pochette par album : un téléchargement, un fichier.
class Covers {
  Covers({
    required this.cacheDir,
    this.embedded = taglibCover,
    this.remote,
    this.remoteKey,
    this.absolute,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;
  final Directory cacheDir;
  final EmbeddedCover embedded;
  final RemoteCover? remote;
  final Future<String?> Function(String trackPath)? remoteKey;
  final DateTime Function() _clock;

  /// Chemin actuel d'un fichier local (clé `docs://` → Documents).
  final Future<String> Function(String path)? absolute;

  /// Un échec (réseau coupé, compte inutilisable) est retenu ce temps-là : pas un essai à chaque image.
  static const retryAfter = Duration(minutes: 1);

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

  /// Pochettes d'un compte du serveur : rangées à part, effacées avec le compte.
  Directory _accountDir(String accountId) =>
      Directory(p.join(cacheDir.path, 'server', accountId));

  File _remoteFile(String accountId, String id, int size) => File(
    p.join(
      _accountDir(accountId).path,
      '${sha1.convert(utf8.encode(id))}-$size.jpg',
    ),
  );

  /// Compte retiré : ses pochettes quittent le disque et la mémoire.
  Future<void> forgetAccount(String accountId) async {
    if (accountId.isEmpty || accountId.contains(RegExp(r'[/\\.]'))) return;
    bool mine(String k) =>
        remoteSchemes.any((s) => k.contains('|$s$accountId/'));
    _memo.removeWhere((k, _) => mine(k));
    _failedAt.removeWhere((k, _) => mine(k));
    final d = _accountDir(accountId);
    if (await d.exists()) await d.delete(recursive: true);
  }

  // Résultats en mémoire, « pas de pochette » compris : l'interface redemande la même image à chaque image.
  final _memo = <String, Future<File?>>{};

  final _failedAt = <String, DateTime>{};

  Future<File?> get(String trackPath, int size) {
    final key = '$size|$trackPath';
    final failed = _failedAt[key];
    if (failed != null && !_clock().isBefore(failed.add(retryAfter))) {
      _failedAt.remove(key);
      _memo.remove(key); // on réessaie
    }
    return _memo.putIfAbsent(
      key,
      () => _load(trackPath, size).catchError((Object _) {
        _failedAt[key] = _clock(); // null retenu pendant [retryAfter]
        return null;
      }),
    );
  }

  /// Après une modification de pochette : la prochaine demande relit le fichier.
  void forget(String trackPath) {
    _memo.removeWhere((k, _) => k.endsWith('|$trackPath'));
    for (final size in const [64, 300, 600]) {
      final f = _cacheFile(trackPath, size);
      FileImage(f).evict(); // même chemin de cache : sans ça, l'ancienne image reste affichée
      if (f.existsSync()) f.deleteSync();
    }
  }

  // téléchargements en cours, par pochette du serveur : les morceaux d'un album affichés ensemble attendent le même
  final _downloads = <String, Future<File?>>{};

  Future<File?> _load(String trackPath, int size) async {
    if (!isRemotePath(trackPath)) {
      return _make(_cacheFile(trackPath, size), size, () async {
        final file = await absolute?.call(trackPath) ?? trackPath;
        Uint8List? bytes = await embedded(file);
        if (bytes == null || bytes.isEmpty) {
          for (final name in folderNames) {
            final f = File(p.join(p.dirname(file), name));
            if (await f.exists()) {
              bytes = await f.readAsBytes();
              break;
            }
          }
        }
        return bytes;
      });
    }
    final fetch = remote;
    if (fetch == null) return null;
    final keyOf = remoteKey;
    final cover = keyOf == null ? trackPath : await keyOf(trackPath);
    if (cover == null) return null; // pas de pochette sur le serveur
    final rest = trackPath.substring(remoteSchemeOf(trackPath)!.length);
    final account = rest.contains('/')
        ? rest.substring(0, rest.indexOf('/'))
        : rest;
    final file = _remoteFile(
      account,
      keyOf == null ? cover : 'cover:$cover',
      size,
    );
    final id = file.path; // la taille est dans le nom
    final running = _downloads[id];
    if (running != null) return running;
    final f = _make(file, size, () => fetch(trackPath, size));
    _downloads[id] = f;
    try {
      return await f;
    } finally {
      _downloads.remove(id);
    }
  }

  /// Le fichier en cache, sinon [source] réduite à [size] et écrite dans [cached].
  Future<File?> _make(
    File cached,
    int size,
    Future<Uint8List?> Function() source,
  ) async {
    if (await cached.exists()) return cached;
    final bytes = await source();
    if (bytes == null || bytes.isEmpty) return null;
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
    await cached.parent.create(recursive: true);
    await cached.writeAsBytes(jpg);
    return cached;
  }
}
