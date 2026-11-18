import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/player/mpv_port.dart';
import 'package:lafleurmusic/player/queue.dart';

/// Faux mpv : tient sa propre liste comme mpv (sémantique de playlist-move comprise).
class FakePort implements MpvPort {
  final calls = <String>[];
  var list = <String>[];
  var index = 0;
  @override
  Future<void> openAll(List<String> paths, int index) async {
    calls.add('openAll');
    list = List.of(paths);
    this.index = index;
  }

  @override
  Future<void> insertAt(int at, String path) async {
    calls.add('insertAt $at');
    list.insert(at, path);
    if (at <= index) index++;
  }

  @override
  Future<void> move(int from, int to) async {
    calls.add('move $from $to');
    final cur = list[index];
    final p = list.removeAt(from);
    list.insert(to, p);
    index = list.indexOf(cur);
  }

  @override
  Future<void> remove(int i) async {
    calls.add('remove $i');
    list.removeAt(i);
    if (i < index) index--;
    index = index.clamp(0, list.isEmpty ? 0 : list.length - 1);
  }

  @override
  Future<void> jump(int i) async {
    calls.add('jump $i');
    index = i;
  }

  @override
  Future<void> replace(int i, String path) async {
    calls.add('replace $i');
    list[i] = path;
  }
}

void main() {
  late FakePort port;
  late QueueSync<String> sync;
  late PlayQueue<String> q;

  setUp(() async {
    port = FakePort();
    q = PlayQueue(['A', 'B', 'C']);
    sync = QueueSync(port, (t) => t);
    await sync.open(q);
    port.calls.clear();
  });

  void same() {
    expect(port.list, q.order);
    expect(port.index, q.position);
  }

  test('Ajouter à la file : un seul insertAt, aucune réouverture', () async {
    await sync.enqueue(q, ['X']);
    expect(port.calls, ['insertAt 1']);
    same();
    await sync.playNext(q, ['Y', 'Z']);
    expect(port.calls.where((c) => c == 'openAll'), isEmpty);
    same();
  });

  test('déplacer un ajout : mpv suit', () async {
    await sync.enqueue(q, ['X', 'Y']);
    await sync.move(q, 2, 1);
    same();
    await sync.move(q, 1, 3);
    same();
  });

  test('Vider : mpv suit', () async {
    await sync.enqueue(q, ['X', 'Y']);
    await sync.clearAdded(q);
    same();
  });

  test('Suivant après un ajout : il est retiré de mpv aussi', () async {
    await sync.playNext(q, ['Y']);
    await sync.next(q); // Y
    await sync.next(q); // B, Y retiré
    same();
    expect(q.current, 'B');
  });

  test('mpv passe tout seul au suivant : l’ajout fini est retiré', () async {
    await sync.playNext(q, ['Y']);
    port.index = 1; // mpv a fini A
    await sync.advanced(q, 1);
    port.index = 2; // puis Y
    await sync.advanced(q, 2);
    same();
    expect(q.order, ['A', 'B', 'C']);
  });

  test('retirer le morceau en cours, présent aussi dans les ajouts', () async {
    await sync.enqueue(q, ['A']);
    await sync.removeWhere(q, (t) => t == 'A');
    expect(port.calls.where((c) => c.startsWith('remove')).length, 2);
    same();
    expect(q.current, 'B');
  });

  test('remplacer le morceau en cours', () async {
    await sync.replaceWhere(q, (t) => t == 'A', 'A2');
    expect(port.calls, ['replace 0']);
    same();
    expect(q.current, 'A2');
  });

  test('file vide + Lire ensuite : mpv ouvre ce morceau', () async {
    final e = PlayQueue<String>.empty();
    await sync.playNext(e, ['Z']);
    expect(port.list, ['Z']);
    expect(e.current, 'Z');
  });

  test(
    'répéter tout : mpv revient au début, l’ajout fini est retiré',
    () async {
      final r = PlayQueue(['A', 'B'], index: 1)..cycleRepeat();
      await sync.open(r);
      await sync.enqueue(r, ['X']);
      port.index = 2;
      await sync.advanced(r, 2); // X
      port.index = 0;
      await sync.advanced(r, 0); // retour à A
      expect(r.order, ['A', 'B']);
      expect(port.list, ['A', 'B']);
    },
  );

  test('supprimer le dernier morceau pendant qu’il joue : mpv et la file restent sur le même', () async {
    final e = PlayQueue(['A', 'B', 'C'], index: 2);
    await sync.open(e);
    port.calls.clear();
    final ended = await sync.removeAt(e, 2);
    expect(ended, isTrue); // fin de liste : le lecteur se met en pause
    expect(e.current, 'B');
    expect(port.list, ['A', 'B']);
    expect(port.index, 1); // mpv replacé sur B
    expect(port.calls, ['remove 2', 'jump 1']);
  });

  test('supprimer un autre morceau : pas de fin de liste', () async {
    expect(await sync.removeAt(q, 2), isFalse);
  });
}
