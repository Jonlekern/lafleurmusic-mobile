import 'dart:async';

import '../player/media_resolver.dart';
import '../player/player.dart';
import '../sources/source.dart';
import '../sources/subsonic.dart';
import 'db.dart';

/// Le serveur ne connaît pas ce morceau (Subsonic 70) : renvoyer l'écoute ne servirait à rien.
bool scrobbleRefused(Object e) => e is SubsonicException && e.code == 70;

/// Compte une écoute quand on a écouté la moitié du morceau ou 4 min, une fois par lecture.
/// Morceau du serveur : l'écoute est aussi envoyée au serveur (scrobble) par [sourceOf].
class PlayCounter {
  PlayCounter(
    Stream<PlayerState> states,
    this.db, {
    DateTime Function()? now,
    this.sourceOf,
    this.playedAs,
  }) : _now = now ?? DateTime.now {
    _sub = states.listen(_on);
  }

  final LibraryDb db;
  final Future<MusicSource> Function(String accountId)? sourceOf;

  /// The row that really played the track (the same song on another account, or its
  /// kept copy: [MediaResolver.playedKey]); the listen is counted and sent there.
  final String Function(String path)? playedAs;
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
      final at = _now();
      final played = playedAs?.call(t.path) ?? t.path;
      unawaited(db.addPlay(played, at));
      unawaited(_scrobble(played, at));
    }
  }

  Future<void> _scrobble(String path, DateTime at) async {
    final key = parseRemoteKey(path), of = sourceOf;
    if (key == null || of == null) return;
    try {
      await (await of(key.$1)).scrobble(key.$2, at);
    } on Object catch (e) {
      // serveur injoignable ou en erreur : l'écoute attend son retour (rien dans les journaux) ;
      // morceau inconnu du serveur : inutile de réessayer
      if (scrobbleRefused(e)) return;
      try {
        await db.addPending(key.$1, key.$2, at);
      } on Object {
        // base fermée ou disque plein : cette écoute ne sera pas envoyée, rien de plus
      }
    }
  }

  Future<void> dispose() => _sub.cancel();
}
