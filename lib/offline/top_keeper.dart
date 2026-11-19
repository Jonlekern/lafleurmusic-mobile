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
    this.reachable,
    this.debounce = const Duration(seconds: 3),
  });

  final LibraryDb db;
  final Downloader downloader;
  final bool Function() atHome;

  /// Can the account [id] be asked now? Null: every account.
  final bool Function(String id)? reachable;
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

  /// The row that stands for the song of [t] on the phone: the copy a twin already has
  /// (finished, then queued, then failed; the user's or the Top 100's), else the first
  /// twin, in the order of the accounts screen, whose account answers. Null: the song is
  /// a local file.
  Future<(String path, Track? toKeep)?> _source(Track t) async {
    if (parseRemoteKey(t.path) == null) return null;
    final group = [
      for (final w in await db.twinsOf(t.path))
        if (parseRemoteKey(w.path) != null) w,
    ];
    if (group.isEmpty) group.add(t);
    OfflineRow? best;
    int rank(OfflineRow o) => o.state == OfflineState.done.name
        ? 0
        : o.state == OfflineState.queued.name
        ? 1
        : 2;
    for (final w in group) {
      final o = await db.offlineOf(w.path);
      if (o != null && (best == null || rank(o) < rank(best))) best = o;
    }
    if (best != null) return (best.trackPath, null);
    final ok = reachable;
    final from = group.firstWhere(
      (w) => ok == null || ok(parseRemoteKey(w.path)!.$1),
      orElse: () => group.first,
    );
    return (from.path, from);
  }

  Future<void> _tour() async {
    if (!atHome()) return;
    // one row per song (the same song on several accounts is one rank)
    final top = await db.top(100);
    final plan = <(Track, (String, Track?)?)>[];
    final inTop = <String>{};
    for (final (t, _) in top) {
      final src = await _source(t);
      plan.add((t, src));
      inTop.add(src?.$1 ?? t.path);
    }
    final known = {for (final r in await db.top100Offline()) r.trackPath};
    final out = [
      for (final p in known)
        if (!inTop.contains(p)) p,
    ];
    // la raison est relue au moment d'effacer : un « garder » de l'utilisateur entre-temps l'emporte
    if (out.isNotEmpty) {
      await downloader.forget(out, only: OfflineReason.top100);
    }
    for (final (t, src) in plan) {
      if (!atHome()) return;
      // retirés par l'utilisateur : on n'y touche plus, jusqu'à son prochain « Garder »
      // lui ou un jumeau (le même morceau sur un autre compte) : règle Q8
      if (await db.autoKeepBlockedFor(t.path)) continue;
      // local : déjà sur le téléphone
      // gardé, en file ou en échec (sur n'importe quel jumeau) : rien à refaire
      final keep = src?.$2;
      if (keep == null) continue;
      final r = await downloader.keep([keep], reason: OfflineReason.top100);
      if (!r.ok) return; // limite atteinte (ou erreur) : on s'arrête là
    }
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
  }
}
