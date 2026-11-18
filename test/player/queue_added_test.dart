import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/player/queue.dart';

PlayQueue<String> abc({int index = 0}) =>
    PlayQueue(['A', 'B', 'C'], index: index);

void main() {
  test('Ajouter à la file puis Lire ensuite : Y avant X, avant la suite', () {
    final q = abc()
      ..enqueue(['X'])
      ..playNext(['Y']);
    expect(q.order, ['A', 'Y', 'X', 'B', 'C']);
    expect(q.addedCount, 2);
    expect(q.added, ['Y', 'X']);
    expect(q.upcoming(5), ['B', 'C']);
  });

  test('les ajouts jouent puis l’album reprend', () {
    final q = abc()
      ..enqueue(['X'])
      ..playNext(['Y']);
    q.next();
    expect(q.current, 'Y');
    expect(q.addedCount, 1);
    q.next();
    expect(q.current, 'X');
    expect(q.addedCount, 0);
    q.next();
    expect(q.current, 'B');
  });

  test('un ajout joué est retiré de la file (signalé une fois)', () {
    final q = abc()..playNext(['Y']);
    q.next(); // Y
    expect(q.takeDropped(), isNull); // A n'est pas un ajout
    q.next(); // B
    expect(q.takeDropped(), 1);
    expect(q.takeDropped(), isNull);
    expect(q.order, ['A', 'B', 'C']);
    expect(q.current, 'B');
  });

  test('aléatoire : les ajouts restent juste après, non mélangés', () {
    final q = PlayQueue(List.generate(20, (i) => 't$i'))..enqueue(['X', 'Y']);
    q.toggleShuffle(42);
    expect(q.current, 't0');
    expect(q.order.sublist(1, 3), ['X', 'Y']);
    expect(q.addedCount, 2);
    q.toggleShuffle(7);
    expect(q.order.sublist(0, 4), ['t0', 'X', 'Y', 't1']);
    expect(q.addedCount, 2);
  });

  test(
    'aléatoire basculé pendant un ajout : l’album reprend au bon endroit',
    () {
      final q = PlayQueue(['A', 'B', 'C', 'D'], index: 1)..enqueue(['X', 'Y']);
      q.next(); // X
      q.toggleShuffle(3);
      expect(q.current, 'X');
      expect(q.order[1], 'Y');
      q.toggleShuffle(3);
      expect(q.order, ['A', 'B', 'X', 'Y', 'C', 'D']);
      expect(q.current, 'X');
    },
  );

  test('Vider retire seulement les ajouts', () {
    final q = abc()..enqueue(['X', 'Y']);
    q.clearAdded();
    expect(q.order, ['A', 'B', 'C']);
    expect(q.addedCount, 0);
  });

  test('glisser un ajout derrière B : il quitte le bloc', () {
    final q = abc()..enqueue(['X', 'Y']);
    q.move(1, 3); // X derrière B : A, Y, B, X, C
    expect(q.order, ['A', 'Y', 'B', 'X', 'C']);
    expect(q.addedCount, 1);
  });

  test('glisser le 2e ajout en tête', () {
    final q = abc()..enqueue(['X', 'Y']);
    q.move(2, 1);
    expect(q.added, ['Y', 'X']);
  });

  test('retirer un ajout', () {
    final q = abc()..enqueue(['X', 'Y']);
    q.removeAt(1);
    expect(q.added, ['Y']);
    expect(q.order, ['A', 'Y', 'B', 'C']);
  });

  test('répéter tout : les ajouts ne sont joués qu’une fois', () {
    final q = abc(index: 2)..cycleRepeat();
    q.enqueue(['X']);
    q.next();
    expect(q.current, 'X');
    q.next();
    expect(q.current, 'A');
    expect(q.order, ['A', 'B', 'C']);
    expect(q.upcoming(4), ['B', 'C', 'A', 'B']);
  });

  test('file vide : Lire ensuite lance ce morceau', () {
    final q = PlayQueue<String>.empty()..playNext(['Z']);
    expect(q.current, 'Z');
    expect(q.addedCount, 0);
    final r = PlayQueue<String>.empty()..enqueue(['Z', 'W']);
    expect(r.current, 'Z');
    expect(r.upcoming(3), ['W']);
  });

  test('upcomingIndexes : places dans order de la suite (répéter tout)', () {
    final q = abc()
      ..cycleRepeat()
      ..enqueue(['X']);
    expect(q.upcomingIndexes(4), [2, 3, 0, 2]);
    expect(q.upcoming(4), ['B', 'C', 'A', 'B']);
  });
}
