import 'dart:math';

enum Repeat { off, all, one }

/// File d'attente pure : ordre (normal ou aléatoire), morceau courant, répétition,
/// et les morceaux « ajoutés » (Lire ensuite / Ajouter à la file) juste après le morceau en cours.
class PlayQueue<T> {
  PlayQueue(List<T> tracks, {int index = 0})
    : _tracks = List.of(tracks),
      _order = List.of(tracks),
      _added = List.filled(tracks.length, false, growable: true),
      _pos = tracks.isEmpty ? 0 : index.clamp(0, tracks.length - 1) {
    _touch();
  }

  PlayQueue.empty() : this(const []);

  final List<T> _tracks; // la liste de départ (l'album), sans les ajouts
  List<T> get tracks => List.unmodifiable(_tracks);
  List<T> _order;
  List<bool>
  _added; // _added[i] : order[i] vient de Lire ensuite / Ajouter à la file
  int _pos;
  int? _dropped;
  T? _anchor; // dernier morceau de l'album joué : l'album reprend après lui
  bool shuffle = false;
  Repeat repeat = Repeat.off;

  List<T> get order => List.unmodifiable(_order);
  int get position => _pos;
  T? get current => _order.isEmpty ? null : _order[_pos];

  /// Nombre d'ajouts qui suivent le morceau en cours.
  int get addedCount {
    var n = 0;
    while (_pos + 1 + n < _order.length && _added[_pos + 1 + n]) {
      n++;
    }
    return n;
  }

  List<T> get added => _order.sublist(_pos + 1, _pos + 1 + addedCount);

  /// Place dans [order] d'un ajout joué puis retiré par le dernier [next] / [jumpTo] (le lecteur le retire de mpv).
  int? takeDropped() {
    final d = _dropped;
    _dropped = null;
    return d;
  }

  /// Lire ensuite : juste après le morceau en cours, en tête des ajouts.
  void playNext(List<T> items) => _insert(_pos + 1, items);

  /// Ajouter à la file : après le dernier ajout.
  void enqueue(List<T> items) => _insert(_pos + 1 + addedCount, items);

  void _insert(int at, List<T> items) {
    if (items.isEmpty) return;
    if (_order.isEmpty) {
      // rien ne joue : ces morceaux deviennent la liste
      _tracks.addAll(items);
      _order = List.of(items);
      _added = List.filled(items.length, false, growable: true);
      _pos = 0;
      _touch();
      return;
    }
    _order.insertAll(at, items);
    _added.insertAll(at, List.filled(items.length, true));
  }

  /// Déplace un morceau à venir ; il fait partie des ajouts s'il arrive dans leur bloc.
  void move(int from, int to) {
    if (from <= _pos || from >= _order.length) return;
    final t = _order.removeAt(from);
    final wasAdded = _added.removeAt(from);
    final at = to.clamp(_pos + 1, _order.length);
    final isAdded = at <= _pos + 1 + addedCount;
    _order.insert(at, t);
    _added.insert(at, isAdded);
    if (wasAdded && !isAdded) _tracks.add(t);
    if (!wasAdded && isAdded) _tracks.remove(t);
  }

  /// Vider : retire les ajouts, la suite de l'album reste.
  void clearAdded() {
    final n = addedCount;
    _order.removeRange(_pos + 1, _pos + 1 + n);
    _added.removeRange(_pos + 1, _pos + 1 + n);
  }

  void _dropIfAdded(int i) {
    if (i == _pos || i >= _order.length || !_added[i]) return;
    _order.removeAt(i);
    _added.removeAt(i);
    if (i < _pos) _pos--;
    _dropped = i;
  }

  /// Morceau suivant ; false si la liste est finie (répéter off).
  bool next() {
    if (_order.isEmpty) return false;
    if (repeat == Repeat.one) return true;
    final leaving = _pos;
    if (_pos + 1 < _order.length) {
      _pos++;
    } else if (repeat == Repeat.all) {
      _pos = 0;
    } else {
      return false;
    }
    _dropIfAdded(leaving);
    _touch();
    return true;
  }

  /// Après 3 s on recommence le morceau, avant on revient au précédent.
  void previous(Duration elapsed) {
    if (_order.isEmpty || elapsed > const Duration(seconds: 3)) return;
    if (_pos > 0) {
      _pos--;
    } else if (repeat == Repeat.all) {
      _pos = _order.length - 1;
    }
    _touch();
  }

  void _touch() {
    if (_order.isNotEmpty && !_added[_pos]) _anchor = _order[_pos];
  }

  /// Retire le morceau à cette place de l'ordre ; le courant reste le même (ou le suivant s'il est retiré).
  void removeAt(int orderIndex) {
    if (orderIndex < 0 || orderIndex >= _order.length) return;
    final t = _order.removeAt(orderIndex);
    if (!_added.removeAt(orderIndex)) _tracks.remove(t);
    if (orderIndex < _pos) _pos--;
    _pos = _order.isEmpty ? 0 : _pos.clamp(0, _order.length - 1);
  }

  void jumpTo(int orderIndex) {
    if (_order.isEmpty) return;
    final leaving = _pos;
    _pos = orderIndex.clamp(0, _order.length - 1);
    // un ajout fini ne revient pas (en avant, ou retour au début en répétant tout)
    final wrapped =
        repeat == Repeat.all && leaving == _order.length - 1 && _pos == 0;
    if (_pos > leaving || wrapped) _dropIfAdded(leaving);
    _touch();
  }

  /// Remplace partout où [test] est vrai ; rend les places changées dans [order].
  List<int> replaceWhere(bool Function(T) test, T now) {
    for (var i = 0; i < _tracks.length; i++) {
      if (test(_tracks[i])) _tracks[i] = now;
    }
    final out = <int>[];
    for (var i = 0; i < _order.length; i++) {
      if (test(_order[i])) {
        _order[i] = now;
        out.add(i);
      }
    }
    if (_anchor != null && test(_anchor as T)) _anchor = now;
    return out;
  }

  void toggleShuffle(int seed) {
    if (_order.isEmpty) {
      shuffle = !shuffle;
      return;
    }
    final cur = _order[_pos];
    final curAdded = _added[_pos];
    final adds = added;
    shuffle = !shuffle;
    if (shuffle) {
      final rest = List.of(_tracks);
      if (!curAdded) rest.remove(cur);
      rest.shuffle(Random(seed));
      _set([
        (cur, curAdded),
        for (final a in adds) (a, true),
        for (final r in rest) (r, false),
      ]);
      _pos = 0;
    } else {
      // l'album reprend après le dernier morceau de l'album joué
      final a = curAdded ? _anchor : cur;
      final anchor = a == null ? -1 : _tracks.indexOf(a);
      _set([
        for (final t in _tracks.take(anchor + 1)) (t, false),
        if (curAdded) (cur, true),
        for (final a in adds) (a, true),
        for (final t in _tracks.skip(anchor + 1)) (t, false),
      ]);
      _pos = curAdded ? anchor + 1 : max(0, anchor);
    }
  }

  void _set(List<(T, bool)> entries) {
    _order = [for (final e in entries) e.$1];
    _added = [for (final e in entries) e.$2];
  }

  void cycleRepeat() =>
      repeat = Repeat.values[(repeat.index + 1) % Repeat.values.length];

  List<T> upNext(int count) {
    final out = <T>[];
    for (var i = 1; i <= count && out.length < count; i++) {
      final j = _pos + i;
      if (j < _order.length) {
        out.add(_order[j]);
      } else if (repeat == Repeat.all && _order.isNotEmpty) {
        out.add(_order[j % _order.length]);
      }
    }
    return out;
  }

  /// La suite après les ajouts (répéter tout compris ; les ajouts ne reviennent pas).
  List<T> upcoming(int count) => [
    for (final i in upcomingIndexes(count)) _order[i],
  ];

  /// Places dans [order] de [upcoming].
  List<int> upcomingIndexes(int count) {
    final out = <int>[];
    final n = _order.length;
    for (var j = _pos + 1 + addedCount; out.length < count; j++) {
      if (j < n) {
        if (!_added[j]) out.add(j);
      } else if (repeat == Repeat.all && n > 0 && j < 2 * n) {
        final k = j % n;
        if (!_added[k] || k == _pos) out.add(k);
      } else {
        break;
      }
    }
    return out;
  }
}

/// Place du premier morceau jouable à partir du morceau en cours (compris), ou juste après si
/// [after] ; la liste reprend au début en « répéter tout ». Null s'il n'y en a pas.
int? firstPlayable<T>(
  PlayQueue<T> q,
  bool Function(T) ok, {
  bool after = false,
}) {
  final n = q.order.length;
  for (var k = after ? 1 : 0; k < n; k++) {
    final i = q.position + k;
    if (i >= n && q.repeat != Repeat.all) return null;
    if (ok(q.order[i % n])) return i % n;
  }
  return null;
}
