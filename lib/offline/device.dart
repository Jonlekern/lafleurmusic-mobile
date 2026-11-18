import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../settings.dart';

/// Clé d'un fichier local posé dans le dossier Documents de l'appli (iPhone) : le chemin absolu
/// change quand l'appli est mise à jour ou restaurée, la partie après `docs://` reste.
const docsScheme = 'docs://';

/// Ce que l'appli demande au téléphone : dossier des copies, sélecteur, place libre.
abstract class Device {
  /// Le dossier choisi s'il est accessible, sinon le dossier par défaut (créé au besoin).
  Future<Directory> musicRoot();

  /// Sélecteur de dossier du système. Renvoie un candidat (sans changer de dossier),
  /// ou null si annulé. Lève [FolderNotLocalException] si le dossier n'est pas sur le
  /// téléphone (Android), [FolderNotWritableException] si l'appli ne peut pas y écrire.
  Future<PickedFolder?> pickFolder();

  /// Abandonne le candidat (déplacement raté ou annulé) : iOS ferme son accès.
  Future<void> releaseCandidate();

  /// Adopte le candidat : [musicRoot] renvoie ce dossier, le choix est enregistré.
  Future<void> commitFolder(PickedFolder c);

  /// Faux si le dossier choisi ne répond plus (carte SD retirée, signet périmé) :
  /// [musicRoot] retombe alors sur le dossier par défaut.
  Future<bool> rootReachable();

  /// Android : demande les droits de stockage (écriture avant l'API 29 ; lecture des
  /// autres fichiers si [readOthers]). Vrai si accordés ou inutiles. iOS : toujours vrai.
  Future<bool> ensureAccess({bool readOthers = false});

  /// `docs://rel` → chemin actuel dans Documents (iPhone) ; tout autre chemin tel quel.
  Future<String> absolutePath(String key);

  /// Inverse : un fichier dans Documents (iPhone) reçoit sa clé `docs://rel` ; les autres restent absolus.
  Future<String> keyFor(String absolutePath);

  Future<int> freeBytes(String path);

  /// Android : prévient la médiathèque du système d'un nouveau fichier. iOS : rien.
  Future<void> announce(String path);
}

/// Un dossier choisi mais pas encore adopté (iOS : [bookmark] garde l'accès).
class PickedFolder {
  const PickedFolder(this.path, [this.bookmark]);
  final String path;
  final String? bookmark;
}

/// Le dossier choisi n'a pas de vrai chemin de fichiers (Android : cloud, etc.).
class FolderNotLocalException implements Exception {
  @override
  String toString() => 'FolderNotLocalException';
}

/// Le dossier choisi est sur le téléphone mais l'appli ne peut pas y écrire.
class FolderNotWritableException implements Exception {
  @override
  String toString() => 'FolderNotWritableException';
}

/// [Device] réel, par le canal natif `studio.lafleur/device`.
class ChannelDevice implements Device {
  ChannelDevice({
    required this.settings,
    required this.saveSettings,
    MethodChannel? channel,
    bool? ios,
  }) : _ch = channel ?? const MethodChannel('studio.lafleur/device'),
       _ios = ios ?? Platform.isIOS;

  final AppSettings settings;
  final Future<void> Function() saveSettings;
  final MethodChannel _ch;
  final bool _ios;

  Directory? _chosen; // dossier choisi, résolu et accessible
  Future<void>? _resolving;

  Future<Directory> _default() async =>
      Directory((await _ch.invokeMethod<String>('defaultRoot'))!);

  /// Résout le dossier choisi une fois (iOS : signet relu, accès démarré).
  Future<void> _resolve() => _resolving ??= _doResolve();

  Future<void> _doResolve() async {
    final saved = settings.musicFolder;
    if (saved == null) return;
    try {
      if (_ios) {
        final r = await _ch.invokeMapMethod<String, Object?>('openBookmark', {
          'bookmark': saved,
        });
        final path = r?['path'] as String?;
        if (path == null) return;
        final fresh = r?['bookmark'];
        if (fresh is String && fresh != saved) {
          settings.musicFolder = fresh; // signet périmé, renouvelé
          await saveSettings();
        }
        _chosen = Directory(path);
      } else {
        final d = Directory(saved);
        if (await d.exists()) _chosen = d;
      }
    } on Object {
      _chosen = null; // plugin absent, signet périmé, dossier illisible…
    }
  }

  @override
  Future<Directory> musicRoot() async {
    await _resolve();
    return _chosen ?? await _default();
  }

  @override
  Future<bool> rootReachable() async {
    await _resolve();
    return settings.musicFolder == null || _chosen != null;
  }

  @override
  Future<PickedFolder?> pickFolder() async {
    final Map<String, Object?>? r;
    try {
      r = await _ch.invokeMapMethod<String, Object?>('pickFolder');
    } on PlatformException catch (e) {
      if (e.code == 'not_local') throw FolderNotLocalException();
      if (e.code == 'not_writable') throw FolderNotWritableException();
      rethrow;
    }
    if (r == null) return null;
    return PickedFolder(
      r['path']! as String,
      _ios ? r['bookmark']! as String : null,
    );
  }

  @override
  Future<void> commitFolder(PickedFolder c) async {
    // iOS : l'accès du candidat passe en service (l'ancien se ferme)
    if (_ios) await _ch.invokeMethod<void>('commitFolder');
    settings.musicFolder = c.bookmark ?? c.path;
    await saveSettings();
    _chosen = Directory(c.path);
    _resolving = Future.value();
  }

  @override
  Future<void> releaseCandidate() async {
    if (_ios) await _ch.invokeMethod<void>('releaseCandidate');
  }

  @override
  Future<bool> ensureAccess({bool readOthers = false}) async {
    if (_ios) return true;
    return await _ch.invokeMethod<bool>('ensureAccess', {
          'readOthers': readOthers,
        }) ??
        false;
  }

  // Documents = le parent du dossier par défaut (Documents/LAFLEURMUSIC)
  Future<String> _docs() async => p.dirname((await _default()).path);

  @override
  Future<String> absolutePath(String key) async => key.startsWith(docsScheme)
      ? p.join(await _docs(), key.substring(docsScheme.length))
      : key;

  @override
  Future<String> keyFor(String absolutePath) async {
    if (!_ios) return absolutePath;
    final docs = await _docs();
    if (!p.isWithin(docs, absolutePath)) return absolutePath;
    return '$docsScheme${p.posix.joinAll(p.split(p.relative(absolutePath, from: docs)))}';
  }

  @override
  Future<int> freeBytes(String path) async =>
      (await _ch.invokeMethod<int>('freeBytes', {'path': path})) ?? 0;

  @override
  Future<void> announce(String path) async {
    if (_ios) return;
    await _ch.invokeMethod<void>('announce', {'path': path});
  }
}
