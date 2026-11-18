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
    _timer = Timer(debounce, () => unawaited(refresh()));
  }

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
        unawaited(refresh());
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
    if (out.isNotEmpty) await downloader.forget(out);
    for (final (t, _) in top) {
      if (!atHome()) return;
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
