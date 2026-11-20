import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../settings.dart';

/// Clé d'un fichier local posé dans le dossier Documents de l'appli (iPhone) : le chemin absolu
/// change quand l'appli est mise à jour ou restaurée, la partie après `docs://` reste.
const docsScheme = 'docs://';

/// Clé d'un fichier du dossier privé de l'appli ([Device.privateRoot]) : la partie après
/// `app://` est relative à ce dossier, son chemin absolu peut changer (conteneur iOS).
const appScheme = 'app://';

/// Ce que l'appli demande au téléphone : dossiers des copies, sélecteur, place libre.
///
/// Deux racines : [keptRoot] (où vont les morceaux gardés et leurs `.m3u8`) et
/// [visibleRoot] (le dossier que l'utilisateur voit, relu pour les fichiers posés à la main).
/// Elles sont la même tant que le réglage `keepInApp` est faux.
abstract class Device {
  /// Où le téléchargeur range les morceaux gardés : [privateRoot] avec `keepInApp`,
  /// sinon [visibleRoot].
  Future<Directory> keptRoot();

  /// Le dossier visible : le dossier choisi s'il est accessible, sinon le dossier par défaut
  /// (Android : peut-être pas encore créé, faute de droit d'écriture ; le premier
  /// téléchargement le crée).
  Future<Directory> visibleRoot();

  /// Le dossier privé de l'appli, effacé avec elle (iOS : exclu de la sauvegarde iCloud ;
  /// Android : jamais annoncé à la médiathèque). Créé seulement avec [create] : sinon son
  /// chemin seul, le dossier peut ne pas exister (personne n'y a encore rien gardé).
  Future<Directory> privateRoot({bool create = true});

  /// Enregistre le réglage `keepInApp` ; une erreur d'enregistrement le laisse comme avant.
  /// [forgetFolder] : le dossier choisi est oublié en même temps (retour au dossier par
  /// défaut, le dossier choisi ne répond plus).
  Future<void> setKeepInApp(bool value, {bool forgetFolder = false});

  /// Sélecteur de dossier du système. Renvoie un candidat (sans changer de dossier),
  /// ou null si annulé. Lève [FolderNotLocalException] si le dossier n'est pas sur le
  /// téléphone (Android), [FolderNotWritableException] si l'appli ne peut pas y écrire.
  Future<PickedFolder?> pickFolder();

  /// Abandonne le candidat (déplacement raté ou annulé) : iOS ferme son accès.
  Future<void> releaseCandidate();

  /// Adopte le candidat : [visibleRoot] renvoie ce dossier, le choix est enregistré.
  Future<void> commitFolder(PickedFolder c);

  /// Faux si le dossier des morceaux gardés ne répond plus : le dossier choisi est parti
  /// (carte SD retirée, signet périmé) et [keptRoot] est le dossier visible. Le dossier
  /// privé répond toujours.
  Future<bool> rootReachable();

  /// Faux si le dossier choisi ne répond plus : [visibleRoot] retombe alors sur le dossier
  /// par défaut.
  Future<bool> visibleReachable();

  /// Android : demande les droits de stockage (écriture jusqu'à l'API 29 ; lecture des
  /// autres fichiers si [readOthers]). Vrai si accordés ou inutiles. iOS : toujours vrai.
  Future<bool> ensureAccess({bool readOthers = false});

  /// `docs://rel` → chemin actuel dans Documents (iPhone), `app://rel` → dans le dossier
  /// privé ; tout autre chemin tel quel.
  Future<String> absolutePath(String key);

  /// Inverse : un fichier du dossier privé reçoit sa clé `app://rel`, un fichier dans
  /// Documents (iPhone) `docs://rel` ; les autres restent absolus.
  Future<String> keyFor(String absolutePath);

  Future<int> freeBytes(String path);

  /// Android : prévient la médiathèque du système d'un nouveau fichier (jamais pour le
  /// dossier privé). iOS : rien.
  Future<void> announce(String path);

  /// Android : ouvre l'installeur du système sur l'APK [path] (dans `<cache>/updates/`).
  /// Faux si le fichier manque, est hors de ce dossier, ou ailleurs qu'Android.
  Future<bool> installApk(String path);
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
    bool? android,
  }) : _ch = channel ?? const MethodChannel('studio.lafleur/device'),
       _ios = ios ?? Platform.isIOS,
       _android = android ?? Platform.isAndroid;

  final AppSettings settings;
  final Future<void> Function() saveSettings;
  final MethodChannel _ch;
  final bool _ios;
  final bool _android;

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
  Future<Directory> visibleRoot() async {
    await _resolve();
    return _chosen ?? await _default();
  }

  @override
  Future<Directory> keptRoot() =>
      settings.keepInApp ? privateRoot() : visibleRoot();

  String? _private; // dernier chemin du dossier privé rendu par le natif

  /// Avec [create], le natif crée le dossier et (iOS) le remarque exclu de la sauvegarde.
  @override
  Future<Directory> privateRoot({bool create = true}) async {
    final path = (await _ch.invokeMethod<String>('privateRoot', {
      'excludeFromBackup': true,
      'create': create,
    }))!;
    _private = path;
    return Directory(path);
  }

  /// Le dossier privé pour les clés `app://`, ou null si le téléphone ne le donne pas.
  Future<String?> _privatePath() async {
    final known = _private;
    if (known != null) return known;
    try {
      // son chemin seul : rien n'est créé
      return (await privateRoot(create: false)).path;
    } on Object {
      return null;
    }
  }

  @override
  Future<void> setKeepInApp(bool value, {bool forgetFolder = false}) async {
    final before = settings.keepInApp, folder = settings.musicFolder;
    settings.keepInApp = value;
    if (forgetFolder) settings.musicFolder = null;
    try {
      await saveSettings();
    } on Object {
      settings
        ..keepInApp = before
        ..musicFolder = folder;
      rethrow;
    }
    if (forgetFolder) {
      _chosen = null; // le dossier par défaut, tout de suite
      _resolving = Future.value();
    }
  }

  @override
  Future<bool> rootReachable() async =>
      settings.keepInApp || await visibleReachable();

  @override
  Future<bool> visibleReachable() async {
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
  Future<String> absolutePath(String key) async {
    if (key.startsWith(docsScheme)) {
      return p.join(await _docs(), key.substring(docsScheme.length));
    }
    if (key.startsWith(appScheme)) {
      final priv = await _privatePath();
      if (priv != null) return p.join(priv, key.substring(appScheme.length));
    }
    return key;
  }

  @override
  Future<String> keyFor(String absolutePath) async {
    final priv = await _privatePath();
    if (priv != null && p.isWithin(priv, absolutePath)) {
      return '$appScheme${p.posix.joinAll(p.split(p.relative(absolutePath, from: priv)))}';
    }
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
    final priv = await _privatePath();
    if (priv != null && (p.equals(priv, path) || p.isWithin(priv, path))) {
      return; // le dossier privé n'est jamais montré à la médiathèque
    }
    await _ch.invokeMethod<void>('announce', {'path': path});
  }

  @override
  Future<bool> installApk(String path) async {
    if (!_android) return false;
    return (await _ch.invokeMethod<bool>('installApk', {'path': path})) ??
        false;
  }
}
