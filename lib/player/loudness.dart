import 'dart:async';
import 'dart:collection';

import '../library/db.dart';
import '../library/models.dart';
import 'loudness_probe.dart';
import 'player.dart';

/// Gain pour viser −18 LUFS (comme ReplayGain), borné à ±12 dB ; pas de mesure = pas de correction.
double gainFor(double? lufs) =>
    lufs == null ? 0 : (-18 - lufs).clamp(-12.0, 12.0).toDouble();

/// Morceau du serveur : pas de mesure (il faudrait tout télécharger), le ReplayGain du serveur
/// sert de gain (même cible, −18 LUFS), borné à ±12 dB ; sans ReplayGain, pas de correction.
bool _remote(Track t) => t.path.startsWith('subsonic://');
double _serverGain(Track t) =>
    (t.replayGain ?? 0).clamp(-12.0, 12.0).toDouble();

/// Volume égal : mesure chaque morceau une fois (en fond, un à la fois, le morceau en cours d'abord,
/// puis les 5 suivants de la file), garde la mesure en base et règle le gain au début de chaque morceau.
class LoudnessService {
  LoudnessService(
    this.db,
    this.player, {
    Future<double?> Function(String path)? measure,
  }) : _measure = measure ?? measureLoudness;

  final LibraryDb db;
  final PlayerController player;
  final Future<double?> Function(String path) _measure;
  static const lookahead = 5;

  bool _enabled = false;
  StreamSubscription<PlayerState>? _state;
  StreamSubscription<void>? _queue;
  Track? _current;
  final _todo = Queue<Track>();
  bool _working = false;

  bool get enabled => _enabled;
  set enabled(bool v) {
    if (v == _enabled) return;
    _enabled = v;
    if (v) {
      _state = player.state.listen((s) => _onTrack(s.track));
      _queue = player.queueChanged.listen((_) => _lookahead());
      _onTrack(player.current.track);
    } else {
      _state?.cancel();
      _queue?.cancel();
      _todo.clear();
      _current = null;
      unawaited(player.setTrackGain(0));
    }
  }

  void _onTrack(Track? t) {
    if (t == null || (t.path == _current?.path && t.mtime == _current?.mtime)) {
      return;
    }
    _current = t;
    unawaited(_apply(t));
  }

  Future<void> _apply(Track t) async {
    if (_remote(t) && !await db.hasLoudness(t.path, t.mtime)) {
      if (_enabled && _current?.path == t.path) {
        await player.setTrackGain(_serverGain(t));
      }
    } else if (await db.hasLoudness(t.path, t.mtime)) {
      if (_enabled && _current?.path == t.path) {
        await player.setTrackGain(
          gainFor(await db.loudnessOf(t.path, t.mtime)),
        );
      }
    } else {
      await player.setTrackGain(0); // pas encore mesuré : sans correction
      _todo.addFirst(t);
    }
    _lookahead();
  }

  void _lookahead() {
    if (!_enabled) return;
    final q = player.queue;
    if (q != null) {
      for (final t in q.order.skip(q.position + 1).take(lookahead)) {
        if (_remote(t)) continue; // jamais sondé : ReplayGain du serveur
        if (!_todo.any((x) => x.path == t.path)) _todo.add(t);
      }
    }
    unawaited(_work());
  }

  Future<void> _work() async {
    if (_working) return;
    _working = true;
    try {
      while (_enabled && _todo.isNotEmpty) {
        final t = _todo.removeFirst();
        if (await db.hasLoudness(t.path, t.mtime)) continue;
        // gardé pour la prochaine écoute : jamais de saut de volume en plein morceau
        await db.setLoudness(t.path, await _measure(t.path), t.mtime);
      }
    } finally {
      _working = false;
    }
  }

  /// Gain à donner à [t] avant qu'il joue (fondu enchaîné) ; 0 s'il n'est pas mesuré ou si l'option est éteinte.
  Future<double> gainOf(Track t) async {
    if (!_enabled) return 0;
    if (_remote(t) && !await db.hasLoudness(t.path, t.mtime)) {
      return _serverGain(t);
    }
    return gainFor(await db.loudnessOf(t.path, t.mtime));
  }

  void dispose() {
    _state?.cancel();
    _queue?.cancel();
  }
}
