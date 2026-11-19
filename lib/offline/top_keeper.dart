import 'dart:async';

import '../library/db.dart';
import '../library/models.dart';
import '../player/media_resolver.dart';
import 'downloader.dart';

/// Garde le Top 100 sur le téléphone, tout seul, quand on est à la maison.
/// Une copie `user` n'est jamais touchée ; une copie `top100` sortie du Top est effacée.
class TopKeeper {
  TopKeeper({
    required this.db,
    required this.downloader,
    required this.atHome,
    this.debounce = const Duration(seconds: 3),
  });

  final LibraryDb db;
  final Downloader downloader;
  final bool Function() atHome;
  final Duration debounce;

  Timer? _timer;
  Future<void>? _running;
  bool _again = false;
  bool _disposed = false;

  /// Un tour bientôt ; une rafale d'écoutes n'en fait qu'un.
  void schedule() {
    if (_disposed) return;
    _timer?.cancel();
    _timer = Timer(debounce, refreshQuietly);
  }

  /// Comme [refresh], sans attendre ni laisser une erreur s'échapper.
  void refreshQuietly() => unawaited(refresh().catchError((Object _) {}));

  /// Un tour à la fois : une demande arrivée pendant un tour en refait un après.
  Future<void> refresh() {
    final running = _running;
    if (running != null) {
      _again = true;
      return running;
    }
    late final Future<void> f;
    f = _tour().whenComplete(() {
      _running = null;
      if (_again && !_disposed) {
        _again = false;
        refreshQuietly();
      }
    });
    return _running = f;
  }

  Future<void> _tour() async {
    if (!atHome()) return;
    final top = await db.top(100);
    final inTop = {for (final r in top) r.$1.path};
    final known = {for (final r in await db.top100Offline()) r.trackPath};
    final out = [
      for (final p in known)
        if (!inTop.contains(p)) p,
    ];
    // la raison est relue au moment d'effacer : un « garder » de l'utilisateur entre-temps l'emporte
    if (out.isNotEmpty) {
      await downloader.forget(out, only: OfflineReason.top100);
    }
    // retirés par l'utilisateur : on n'y touche plus, jusqu'à son prochain « Garder »
    for (final (t, _) in top) {
      if (!atHome()) return;
      // lui ou un jumeau (le même morceau sur un autre compte) : règle Q8
      if (await db.autoKeepBlockedFor(t.path)) continue;
      // local : déjà sur le téléphone
      if (parseRemoteKey(t.path) == null) continue;
      // gardé, en file ou en échec : rien à refaire
      if (await db.offlineOf(t.path) != null) continue;
      final r = await downloader.keep([t], reason: OfflineReason.top100);
      if (!r.ok) return; // limite atteinte (ou erreur) : on s'arrête là
    }
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
  }
}
