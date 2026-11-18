import 'dart:async';

import '../player/player.dart';
import 'db.dart';

/// Compte une écoute quand on a écouté la moitié du morceau ou 4 min, une fois par lecture.
class PlayCounter {
  PlayCounter(Stream<PlayerState> states, this.db, {DateTime Function()? now})
    : _now = now ?? DateTime.now {
    _sub = states.listen(_on);
  }

  final LibraryDb db;
  final DateTime Function() _now;
  late final StreamSubscription<PlayerState> _sub;
  String? _path;
  bool _counted = false;
  bool _armed = false; // vu sous le seuil : seul un vrai passage du seuil compte (pas la position de l'ancien morceau)

  static const _cap = Duration(minutes: 4);
  static const _restart = Duration(seconds: 2);

  void _on(PlayerState s) {
    final t = s.track;
    if (t == null) return;
    if (t.path != _path) {
      _path = t.path;
      _counted = false;
      _armed = false;
    } else if (_counted && s.position < _restart) {
      _counted = false; // rejoué depuis le début : nouvelle lecture
      _armed = false;
    }
    if (_counted) return;
    final dur = s.duration > Duration.zero
        ? s.duration
        : Duration(milliseconds: t.durationMs);
    if (dur <= Duration.zero) return;
    final half = dur ~/ 2;
    final threshold = half < _cap ? half : _cap;
    if (s.position < threshold) {
      _armed = true;
    } else if (_armed) {
      _counted = true;
      unawaited(db.addPlay(t.path, _now()));
    }
  }

  Future<void> dispose() => _sub.cancel();
}
