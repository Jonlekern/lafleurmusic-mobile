import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/painting.dart' show Size;

import 'player/equalizer.dart';

/// Quels comptes la bibliothèque montre : un seul, tous (fusionnés), ou un choix.
enum DisplayMode { one, all, custom }

/// Réglages de l'appli (dossier de support / settings.json).
class AppSettings {
  AppSettings({
    Equalizer? equalizer,
    this.artistGrid = true,
    this.skin,
    this.winampDouble = true,
    this.winampEq = true,
    this.winampPl = true,
    this.visMode = 0,
    this.winampMode = false,
    this.lafleurSize,
    this.equalVolume = false,
    this.crossfade = false,
    this.crossfadeSeconds = 5,
    this.storageLimitBytes = defaultStorageLimitBytes,
    this.musicFolder,
    this.displayMode = DisplayMode.all,
    this.oneAccount,
    List<String>? customAccounts,
  }) : customAccounts = customAccounts ?? [],
       equalizer = equalizer ?? Equalizer.named('flat');
  Equalizer equalizer;
  bool artistGrid; // vue Artistes : grille de photos (sinon liste)
  // mini lecteur Winamp
  String? skin; // nom du fichier .wsz choisi
  bool winampDouble,
      winampEq,
      winampPl; // taille double, fenêtres égaliseur et playlist
  int visMode; // visualiseur : 0 barres, 1 vague, 2 rien
  bool winampMode; // l'appli était en Winamp en quittant
  Size?
  lafleurSize; // taille de la grande fenêtre, retrouvée en sortant du Winamp
  // carte Lecture (plan 5)
  bool equalVolume; // tous les morceaux au même niveau sonore
  bool crossfade; // fondu enchaîné
  int crossfadeSeconds; // 1 à 10 s
  int
  storageLimitBytes; // place maximale des copies hors ligne (bornes : l'écran)

  String? musicFolder; // dossier choisi pour les copies (iOS : signet en base64) ; null = dossier par défaut

  DisplayMode displayMode; // plusieurs comptes : un, tous ou un choix
  String? oneAccount; // le compte montré quand displayMode = one
  List<String> customAccounts; // les comptes montrés quand displayMode = custom

  static const defaultStorageLimitBytes = 10 * 1024 * 1024 * 1024;

  static Future<AppSettings> load(File f) async {
    try {
      final j = jsonDecode(await f.readAsString());
      if (j is Map<String, Object?>) {
        return AppSettings(
          equalizer: j['equalizer'] is Map
              ? Equalizer.fromJson(
                  (j['equalizer']! as Map).cast<String, Object?>(),
                )
              : null,
          artistGrid: j['artistGrid'] != false,
          skin: j['skin'] is String ? j['skin']! as String : null,
          winampDouble: j['winampDouble'] != false,
          winampEq: j['winampEq'] != false,
          winampPl: j['winampPl'] != false,
          visMode: j['visMode'] is int ? (j['visMode']! as int).clamp(0, 2) : 0,
          winampMode: j['winampMode'] == true,
          lafleurSize:
              j['lafleurSize'] is List &&
                  (j['lafleurSize']! as List).length == 2
              ? Size(
                  ((j['lafleurSize']! as List)[0] as num).toDouble(),
                  ((j['lafleurSize']! as List)[1] as num).toDouble(),
                )
              : null,
          equalVolume: j['equalVolume'] == true,
          crossfade: j['crossfade'] == true,
          crossfadeSeconds: j['crossfadeSeconds'] is int
              ? (j['crossfadeSeconds']! as int).clamp(1, 10)
              : 5,
          storageLimitBytes:
              j['storageLimitBytes'] is int &&
                  (j['storageLimitBytes']! as int) > 0
              ? j['storageLimitBytes']! as int
              : defaultStorageLimitBytes,
          musicFolder:
              j['musicFolder'] is String &&
                  (j['musicFolder']! as String).isNotEmpty
              ? j['musicFolder']! as String
              : null,
          displayMode: DisplayMode.values.firstWhere(
            (m) => m.name == j['displayMode'],
            orElse: () => DisplayMode.all,
          ),
          oneAccount: j['oneAccount'] is String
              ? j['oneAccount']! as String
              : null,
          customAccounts: j['customAccounts'] is List
              ? [
                  for (final a in j['customAccounts']! as List)
                    if (a is String) a,
                ]
              : null,
        );
      }
    } on Object {
      // absent ou illisible : réglages par défaut
    }
    return AppSettings();
  }

  final _saver = Latest();

  /// Enregistre ; des appels rapprochés ne se marchent pas dessus, le dernier état gagne.
  Future<void> save(File f) => _saver.run(() => _write(f));

  Future<void> _write(File f) async {
    await f.parent.create(recursive: true);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(
      jsonEncode({
        'equalizer': equalizer.toJson(),
        'artistGrid': artistGrid,
        'skin': skin,
        'winampDouble': winampDouble,
        'winampEq': winampEq,
        'winampPl': winampPl,
        'visMode': visMode,
        'winampMode': winampMode,
        'lafleurSize': lafleurSize == null
            ? null
            : [lafleurSize!.width, lafleurSize!.height],
        'equalVolume': equalVolume,
        'crossfade': crossfade,
        'crossfadeSeconds': crossfadeSeconds,
        'storageLimitBytes': storageLimitBytes,
        'musicFolder': musicFolder,
        'displayMode': displayMode.name,
        'oneAccount': oneAccount,
        'customAccounts': customAccounts,
      }),
    );
    await tmp.rename(f.path);
  }
}

/// Un travail à la fois ; pendant qu'il tourne, seul le dernier demandé attend son tour
/// (curseur d'égaliseur glissé : des dizaines de demandes par seconde).
class Latest {
  bool _running = false;
  Future<void> Function()? _next;
  Completer<void>? _nextDone;

  Future<void> run(Future<void> Function() job) {
    if (_running) {
      _next = job;
      return (_nextDone ??= Completer<void>()).future;
    }
    return _start(job);
  }

  Future<void> _start(Future<void> Function() job) async {
    _running = true;
    try {
      await job();
    } finally {
      _running = false;
      final next = _next, done = _nextDone;
      _next = null;
      _nextDone = null;
      if (next != null) {
        _start(next).then(done!.complete, onError: done.completeError);
      }
    }
  }
}
