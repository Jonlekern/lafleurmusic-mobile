import 'package:mpv_audio_kit/mpv_audio_kit.dart';

import 'media_resolver.dart';
import 'queue.dart';

/// La liste de lecture de mpv, vue par l'appli. [move] prend la place **finale** du morceau.
abstract interface class MpvPort {
  Future<void> openAll(List<String> paths, int index);
  Future<void> insertAt(int at, String path);
  Future<void> move(int from, int to);
  Future<void> remove(int index);
  Future<void> jump(int index);
  Future<void> replace(int index, String path);
}

/// mpv réel. On tient la longueur de la liste nous-mêmes : l'appli est seule à la modifier.
/// Chaque chemin passe par [resolver] (fichier local, ou flux du serveur avec les en-têtes du compte).
class PlayerPort implements MpvPort {
  PlayerPort(this.player, [MediaResolver? resolver])
    : resolver = resolver ?? MediaResolver.localOnly();
  final Player player;
  final MediaResolver resolver;
  int _length = 0;

  @override
  Future<void> openAll(List<String> paths, int index) async {
    final media = await Future.wait(paths.map(resolver.media));
    _length = paths.length;
    await player.openAll(media, index: index);
  }

  @override
  Future<void> insertAt(int at, String path) async {
    await player.add(await resolver.media(path)); // ajouté à la fin…
    _length++;
    if (at < _length - 1) await player.move(_length - 1, at); // …puis remonté
  }

  @override
  Future<void> move(int from, int to) async {
    if (from == to) return;
    // mpv : « to » désigne le morceau devant lequel on se place
    await player.move(from, to > from ? to + 1 : to);
  }

  @override
  Future<void> remove(int index) async {
    await player.remove(index);
    _length--;
  }

  @override
  Future<void> jump(int index) => player.jump(index);

  @override
  Future<void> replace(int index, String path) async =>
      player.replace(index, await resolver.media(path));
}

/// Applique chaque changement à la [PlayQueue] **et** à mpv, sans rouvrir la liste (pas de coupure).
class QueueSync<T> {
  QueueSync(this.port, this.pathOf);
  final MpvPort port;
  final String Function(T) pathOf;

  Future<void> open(PlayQueue<T> q) =>
      port.openAll([for (final t in q.order) pathOf(t)], q.position);

  Future<void> playNext(PlayQueue<T> q, List<T> items) =>
      _insert(q, items, q.position + 1, () => q.playNext(items));

  Future<void> enqueue(PlayQueue<T> q, List<T> items) =>
      _insert(q, items, q.position + 1 + q.addedCount, () => q.enqueue(items));

  Future<void> _insert(
    PlayQueue<T> q,
    List<T> items,
    int at,
    void Function() apply,
  ) async {
    if (items.isEmpty) return;
    final wasEmpty = q.order.isEmpty;
    apply();
    if (wasEmpty) return open(q);
    for (var i = 0; i < items.length; i++) {
      await port.insertAt(at + i, pathOf(items[i]));
    }
  }

  Future<void> move(PlayQueue<T> q, int from, int to) async {
    if (from <= q.position || from >= q.order.length) return;
    final at = to.clamp(q.position + 1, q.order.length - 1);
    q.move(from, to);
    await port.move(from, at);
  }

  Future<void> clearAdded(PlayQueue<T> q) async {
    final n = q.addedCount;
    final at = q.position + 1;
    q.clearAdded();
    for (var i = 0; i < n; i++) {
      await port.remove(at);
    }
  }

  /// Suivant demandé par l'appli ; false en fin de liste.
  Future<bool> next(PlayQueue<T> q) async {
    if (!q.next()) return false;
    await _go(q);
    return true;
  }

  Future<void> jumpTo(PlayQueue<T> q, int index) async {
    q.jumpTo(index);
    await _go(q);
  }

  Future<void> _go(PlayQueue<T> q) async {
    final d = q.takeDropped();
    // l'ajout qu'on quitte est encore dans mpv : la cible y est un cran plus loin
    await port.jump(q.position + (d != null && d <= q.position ? 1 : 0));
    if (d != null) await port.remove(d);
  }

  /// mpv est passé tout seul au morceau [mpvIndex].
  Future<void> advanced(PlayQueue<T> q, int mpvIndex) async {
    if (mpvIndex == q.position) return;
    q.jumpTo(mpvIndex);
    final d = q.takeDropped();
    if (d != null) await port.remove(d);
  }

  /// Retire une place ; true si c'était le morceau en cours **et** le dernier (fin de liste) :
  /// mpv est replacé sur le nouveau dernier, le lecteur doit se mettre en pause.
  Future<bool> removeAt(PlayQueue<T> q, int index) async {
    if (index < 0 || index >= q.order.length) return false;
    final ended =
        index == q.position &&
        index == q.order.length - 1 &&
        q.order.length > 1 &&
        q.repeat != Repeat.all;
    q.removeAt(index);
    await port.remove(index);
    if (ended) await port.jump(q.position);
    return ended;
  }

  /// Retire toutes les places où [test] est vrai (le morceau en cours compris : mpv passe au suivant).
  Future<bool> removeWhere(PlayQueue<T> q, bool Function(T) test) async {
    var ended = false;
    for (var i = q.order.length - 1; i >= 0; i--) {
      if (test(q.order[i])) ended = await removeAt(q, i) || ended;
    }
    return ended;
  }

  Future<void> replaceWhere(
    PlayQueue<T> q,
    bool Function(T) test,
    T now,
  ) async {
    for (final i in q.replaceWhere(test, now)) {
      await port.replace(i, pathOf(now));
    }
  }
}
