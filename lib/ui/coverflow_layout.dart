import 'dart:math';

/// Position d'une pochette du Cover Flow (maquette 3), pour un défilement continu `pos`.
class CoverSlot {
  const CoverSlot(this.dx, this.angle, this.scale, this.brightness);
  final double dx; // décalage horizontal depuis le centre, px
  final double angle; // rotation Y, radians (gauche positive)
  final double scale;
  final double brightness; // 1 = normale
}

const _near = 270.0, _step = 80.0;

CoverSlot layout(double pos, int index) {
  final d = index - pos;
  final a = d.abs();
  final dx = a <= 1 ? d * _near : d.sign * (_near + (a - 1) * _step);
  final t = min(a, 1.0);
  return CoverSlot(
    dx,
    -d.sign * t * pi / 3,
    1 - 0.14 * t,
    1 - 0.3 * t - 0.12 * max(a - 1, 0).clamp(0, 3),
  );
}

/// Les 7 pochettes autour du centre (seules construites).
List<int> visibleIndexes(double pos, int count) {
  final c = pos.round();
  return [
    for (var i = c - 3; i <= c + 3; i++)
      if (i >= 0 && i < count) i,
  ];
}

/// Du plus loin au plus proche : le centre est dessiné en dernier, devant.
List<int> drawOrder(double pos, int count) =>
    visibleIndexes(pos, count)
      ..sort((a, b) => (b - pos).abs().compareTo((a - pos).abs()));

/// Fin de défilement : on se pose sur l'album le plus proche, entre le premier et le dernier.
double settle(double pos, int count) =>
    count <= 0 ? 0 : pos.round().clamp(0, count - 1).toDouble();
