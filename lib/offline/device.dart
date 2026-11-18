import 'dart:io';

import 'package:flutter/services.dart';

import '../settings.dart';

/// Ce que l'appli demande au téléphone : dossier des copies, sélecteur, place libre.
abstract class Device {
  /// Le dossier choisi s'il est accessible, sinon le dossier par défaut (créé au besoin).
  Future<Directory> musicRoot();

  /// Sélecteur de dossier du système. Renvoie le nouveau chemin, ou null si annulé.
  /// Lève [FolderNotLocalException] si le dossier n'est pas sur le téléphone (Android),
  /// [FolderNotWritableException] si l'appli ne peut pas y écrire.
  Future<String?> pickFolder();

  /// Faux si le dossier choisi ne répond plus (carte SD retirée, signet périmé) :
  /// [musicRoot] retombe alors sur le dossier par défaut.
  Future<bool> rootReachable();

  /// Android : demande les droits de stockage (écriture avant l'API 29 ; lecture des
  /// autres fichiers si [readOthers]). Vrai si accordés ou inutiles. iOS : toujours vrai.
  Future<bool> ensureAccess({bool readOthers = false});

  Future<int> freeBytes(String path);

  /// Android : prévient la médiathèque du système d'un nouveau fichier. iOS : rien.
  Future<void> announce(String path);
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
  Future<String?> pickFolder() async {
    final Map<String, Object?>? r;
    try {
      r = await _ch.invokeMapMethod<String, Object?>('pickFolder');
    } on PlatformException catch (e) {
      if (e.code == 'not_local') throw FolderNotLocalException();
      if (e.code == 'not_writable') throw FolderNotWritableException();
      rethrow;
    }
    if (r == null) return null;
    final path = r['path']! as String;
    settings.musicFolder = _ios ? r['bookmark']! as String : path;
    await saveSettings();
    _chosen = Directory(path);
    _resolving = Future.value();
    return path;
  }

  @override
  Future<bool> ensureAccess({bool readOthers = false}) async {
    if (_ios) return true;
    return await _ch.invokeMethod<bool>('ensureAccess', {
          'readOthers': readOthers,
        }) ??
        false;
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
