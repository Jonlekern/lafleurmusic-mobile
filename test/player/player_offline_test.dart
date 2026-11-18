import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/player/mpv_port.dart';
import 'package:lafleurmusic/player/queue.dart';

/// Faux mpv réduit à ce que le saut utilise : la liste et la place jouée.
class _Port implements MpvPort {
  var list = <String>[];
  var index = 0;
  final jumps = <int>[];
  @override
  Future<void> openAll(List<String> paths, int index) async {
    list = List.of(paths);
    this.index = index;
  }

  @override
  Future<void> jump(int i) async {
    jumps.add(i);
    index = i;
  }

  @override
  Future<void> insertAt(int at, String path) async => list.insert(at, path);
  @override
  Future<void> move(int from, int to) async {}
  @override
  Future<void> remove(int i) async => list.removeAt(i);
  @override
  Future<void> replace(int i, String path) async => list[i] = path;
}

void main() {
  late _Port port;
  late QueueSync<String> sync;
  // « k… » : gardé sur le téléphone ; « s… » : sur le serveur, hors de portée
  bool ok(String t) => t.startsWith('k');

  setUp(() {
    port = _Port();
    sync = QueueSync(port, (t) => t);
  });

  test('hors ligne, [gardé, pas gardé, gardé] : le 2e est sauté, le 3e joue', () async {
    final q = PlayQueue(['k1', 's2', 'k3']);
    await sync.open(q);
    expect(await sync.skipUnplayable(q, ok), (skipped: null, stopped: false));
    q.next(); // mpv passe tout seul au 2e
    await sync.advanced(q, 1);
    final r = await sync.skipUnplayable(q, ok);
    expect(r, (skipped: 's2', stopped: false));
    expect((q.current, q.position, port.index), ('k3', 2, 2));
  });

  test('plusieurs de suite : un seul saut, une seule alerte', () async {
    final q = PlayQueue(['k1', 's2', 's3', 's4', 'k5']);
    await sync.open(q);
    await sync.advanced(q, 1);
    final r = await sync.skipUnplayable(q, ok);
    expect(r.skipped, 's2');
    expect(q.current, 'k5');
    expect(port.jumps, [4]);
  });

  test('plus rien de jouable derrière : on s’arrête', () async {
    final q = PlayQueue(['k1', 's2', 's3']);
    await sync.open(q);
    await sync.advanced(q, 1);
    final r = await sync.skipUnplayable(q, ok);
    expect((r.skipped, r.stopped), ('s2', true));
    expect(port.jumps, isEmpty);
  });

  test('répéter tout : on repart du début, et sans rien de jouable on s’arrête', () async {
    final q = PlayQueue(['k1', 's2', 's3'])..repeat = Repeat.all;
    await sync.open(q);
    await sync.advanced(q, 2);
    expect((await sync.skipUnplayable(q, ok)).skipped, 's3');
    expect(q.current, 'k1');
    final none = PlayQueue(['s1', 's2'])..repeat = Repeat.all;
    await sync.open(none);
    expect((await sync.skipUnplayable(none, ok)).stopped, isTrue);
  });

  test('départ : la liste démarre au premier morceau jouable à partir du choix', () {
    final q = PlayQueue(['s1', 's2', 'k3', 'k4'], index: 1);
    expect(firstPlayable(q, ok), 2);
    expect(firstPlayable(PlayQueue(['s1', 's2']), ok), isNull);
    expect(firstPlayable(PlayQueue(['k1', 's2']), ok), 0);
  });

  test('fondu : seulement vers un suivant jouable, sinon le saut normal s’en charge', () {
    final q = PlayQueue(['k1', 's2', 'k3']);
    expect(fadeTarget(q, ok), isNull); // s2 injouable : pas de fondu dans le vide
    expect(fadeTarget(q, null), 1); // sans règle, comme avant
    q.jumpTo(1);
    expect(fadeTarget(q, ok), 2);
    q.jumpTo(2);
    expect(fadeTarget(q, ok), isNull); // fin de liste
    q.repeat = Repeat.all;
    expect(fadeTarget(q, ok), 0);
    expect(fadeTarget(PlayQueue(['k1']), ok), isNull);
  });
}
