import 'queue.dart';

enum SkipAction { warn, quiet, stop }

/// Fichiers illisibles : un seul avertissement toutes les 3 s, et arrêt après 5 d'affilée (NAS tombé en pleine lecture).
class SkipGuard {
  SkipGuard({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;
  final DateTime Function() _clock;
  int _inARow = 0;
  DateTime? _lastWarn;

  SkipAction onError() {
    _inARow++;
    if (_inARow >= 5) {
      _inARow = 0;
      return SkipAction.stop;
    }
    final now = _clock();
    if (_lastWarn == null ||
        now.difference(_lastWarn!) >= const Duration(seconds: 3)) {
      _lastWarn = now;
      return SkipAction.warn;
    }
    return SkipAction.quiet;
  }

  void onPlayed() => _inARow = 0;
}

/// Comment mpv a quitté un morceau de sa liste.
enum FileEnd { eof, error, other }

/// Suit le morceau que mpv joue ou essaie d'ouvrir, d'après ses « fin de fichier » (une par morceau, dans l'ordre
/// de sa liste) ; un échec (fichier illisible, morceau disparu du serveur : 404) est signalé, mpv passe au suivant.
class EndFiles<T> {
  EndFiles({SkipGuard? guard}) : guard = guard ?? SkipGuard();
  final SkipGuard guard;
  int mpvIndex = 0;

  /// [skipped] : le morceau à signaler (null = rien à dire) ; [stop] : mettre en pause (5 échecs de suite).
  ({T? skipped, bool stop}) ended(PlayQueue<T> q, FileEnd how) {
    if (q.order.isEmpty) return (skipped: null, stop: false);
    final i = mpvIndex.clamp(0, q.order.length - 1);
    T? skipped;
    var stop = false;
    if (how == FileEnd.error) {
      switch (guard.onError()) {
        case SkipAction.warn:
          skipped = q.order[i];
        case SkipAction.quiet:
          break;
        case SkipAction.stop:
          stop = true; // le NAS ou le serveur est sans doute tombé
          skipped = q.order[i];
      }
    } else if (how == FileEnd.eof) {
      guard.onPlayed();
    }
    if (how != FileEnd.other) {
      mpvIndex = q.repeat == Repeat.one ? i : (i + 1) % q.order.length;
    }
    return (skipped: skipped, stop: stop);
  }
}
