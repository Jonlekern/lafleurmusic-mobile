import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../settings.dart';

/// Clé d'un fichier local posé dans le dossier Documents de l'appli (iPhone) : le chemin absolu
/// change quand l'appli est mise à jour ou restaurée, la partie après `docs://` reste.
const docsScheme = 'docs://';

/// Ce que l'appli demande au téléphone : dossier des copies, sélecteur, place libre.
abstract class Device {
  /// Le dossier choisi s'il est accessible, sinon le dossier par défaut (Android : peut-être
  /// pas encore créé, faute de droit d'écriture ; le premier téléchargement le crée).
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

  /// Android : demande les droits de stockage (écriture jusqu'à l'API 29 ; lecture des
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
    // enregistré d'abord ; une erreur (disque, côté natif) remet l'ancien choix
    final before = settings.musicFolder;
    settings.musicFolder = c.bookmark ?? c.path;
    try {
      await saveSettings();
    } on Object {
      settings.musicFolder = before;
      rethrow;
    }
    try {
      // iOS : l'accès du candidat passe en service (l'ancien se ferme)
      if (_ios) await _ch.invokeMethod<void>('commitFolder');
    } on Object {
      settings.musicFolder = before;
      try {
        await saveSettings();
      } on Object {
        // le fichier garde le nouveau choix ; relu au prochain lancement, il retombe au défaut s'il manque
      }
      rethrow;
    }
    _chosen = Directory(c.path);
    _resolving = Future.value();
  }

  @override
  Future<void> releaseCandidate() async {
    if (_ios) await _ch.invokeMethod<void>('releaseCandidate');
  }

  final _asking = <Future<bool>>{}; // demandes natives en cours

  /// Une demande qui n'a besoin d'aucune fenêtre répond tout de suite ; si une autre fenêtre
  /// de droits est déjà ouverte, le côté natif dit « busy » : on attend sa réponse, puis on
  /// redemande (sans demande en cours ici, c'est un reste d'un redémarrage à chaud).
  @override
  Future<bool> ensureAccess({bool readOthers = false}) async {
    if (_ios) return true;
    for (var i = 0; ; i++) {
      final f = _ch
          .invokeMethod<bool>('ensureAccess', {'readOthers': readOthers})
          .then((v) => v ?? false);
      _asking.add(f);
      try {
        return await f;
      } on PlatformException catch (e) {
        if (e.code != 'busy' || i >= 400) rethrow;
      } finally {
        _asking.remove(f);
      }
      final others = List.of(_asking);
      if (others.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      } else {
        await Future.wait(others.map((o) => o.then((_) {}, onError: (_) {})));
      }
    }
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
