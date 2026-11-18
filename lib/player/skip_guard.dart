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
