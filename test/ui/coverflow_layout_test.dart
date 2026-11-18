import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/ui/coverflow_layout.dart';

void main() {
  test('pochette du centre de face, pleine taille', () {
    final c = layout(3, 3);
    expect(c.dx, 0);
    expect(c.angle, 0);
    expect(c.scale, 1);
    expect(c.brightness, 1);
  });
  test('voisins symétriques, inclinés à 60°', () {
    final l = layout(3, 2), r = layout(3, 4);
    expect(l.dx, -270);
    expect(r.dx, 270);
    expect(l.angle, closeTo(pi / 3, 1e-9));
    expect(r.angle, closeTo(-pi / 3, 1e-9));
  });
  test('au-delà : 80 px de plus par pochette, de plus en plus sombres', () {
    expect(layout(3, 5).dx, 350);
    expect(layout(3, 6).dx, 430);
    expect(layout(3, 6).brightness, lessThan(layout(3, 5).brightness));
  });
  test('ordre de dessin : le centre devant', () {
    final order = drawOrder(3.0, 7);
    expect(order.last, 3);
    expect(order.first, anyOf(0, 6));
  });
  test('settle : borné et posé sur un album', () {
    expect(settle(-3.4, 10), 0);
    expect(settle(4.6, 10), 5);
    expect(settle(42, 10), 9);
    expect(settle(2, 0), 0);
  });
  test('un seul album : un seul emplacement visible', () {
    expect(visibleIndexes(0, 1), [0]);
    expect(visibleIndexes(50, 500).length, 7);
  });
}
