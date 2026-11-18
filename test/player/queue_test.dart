import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/player/queue.dart';

PlayQueue q(int n, {int index = 0}) =>
    PlayQueue(List.generate(n, (i) => 't$i'), index: index);

void main() {
  removeTests();
  test('fin de liste, répéter off : s’arrête', () {
    final x = q(2, index: 1);
    expect(x.next(), isFalse);
    expect(x.current, 't1');
  });
  test('répéter tout : revient au début', () {
    final x = q(2, index: 1)..cycleRepeat();
    expect(x.repeat, Repeat.all);
    expect(x.next(), isTrue);
    expect(x.current, 't0');
  });
  test('répéter un seul : même morceau', () {
    final x = q(3, index: 1)
      ..cycleRepeat()
      ..cycleRepeat();
    expect(x.repeat, Repeat.one);
    x.next();
    expect(x.current, 't1');
    x.cycleRepeat();
    expect(x.repeat, Repeat.off);
  });
  test('précédent : avant 3 s morceau d’avant, après 3 s même morceau', () {
    final x = q(3, index: 1);
    x.previous(const Duration(seconds: 5));
    expect(x.current, 't1');
    x.previous(const Duration(seconds: 2));
    expect(x.current, 't0');
  });
  test(
    'aléatoire : garde le courant en tête et tous les morceaux une fois',
    () {
      final x = q(10, index: 4)..toggleShuffle(42);
      expect(x.shuffle, isTrue);
      expect(x.current, 't4');
      expect(x.order.toSet().length, 10);
      expect(x.order.first, 't4');
      x.toggleShuffle(0);
      expect(x.order, List.generate(10, (i) => 't$i'));
      expect(x.current, 't4');
    },
  );
  test('à suivre suit l’aléatoire', () {
    final x = q(10, index: 0)..toggleShuffle(7);
    expect(x.upNext(3), x.order.sublist(1, 4));
  });
  test('à suivre en fin de liste répéter tout', () {
    final x = q(3, index: 2)..cycleRepeat();
    expect(x.upNext(2), ['t0', 't1']);
  });
  test('liste vide', () {
    final x = PlayQueue(const <String>[]);
    expect(x.current, isNull);
    expect(x.next(), isFalse);
  });
}

void removeTests() {
  test(
    'removeAt : retire un morceau avant le courant, le courant ne change pas',
    () {
      final q = PlayQueue(['a', 'b', 'c', 'd'], index: 2);
      q.removeAt(0);
      expect(q.order, ['b', 'c', 'd']);
      expect(q.current, 'c');
    },
  );

  test('removeAt : retire le morceau courant, le suivant devient courant', () {
    final q = PlayQueue(['a', 'b', 'c'], index: 1);
    q.removeAt(1);
    expect(q.order, ['a', 'c']);
    expect(q.current, 'c');
  });

  test('removeAt : le dernier, puis la liste vide', () {
    final q = PlayQueue(['a', 'b'], index: 1);
    q.removeAt(1);
    expect(q.current, 'a');
    q.removeAt(0);
    expect(q.current, isNull);
    expect(q.tracks, isEmpty);
  });
}
