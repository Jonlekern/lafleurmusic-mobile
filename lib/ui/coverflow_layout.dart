import 'dart:math';

import 'package:flutter/widgets.dart';

import '../theme/colors.dart';

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

/// Téléphone (maquette 2, écran 5) : les voisines plus loin du centre, et les suivantes bien espacées
/// (l'éventail de trois pochettes de chaque côté ne s'entasse pas). Aussi le petit Cover Flow du
/// Mode Classic (maquette 18).
double spreadDx(double dx) {
  final a = dx.abs();
  return dx.sign * (a <= 270 ? a * 1.35 : 270 * 1.35 + (a - 270) * 1.9);
}

/// Une pochette du Cover Flow à sa place [slot] : décalée de [dx] (px), réduite, inclinée en
/// perspective, assombrie, avec son reflet ([reflection] : la part de la pochette reflétée).
class FlowCover extends StatelessWidget {
  const FlowCover({
    super.key,
    required this.slot,
    required this.dx,
    required this.size,
    required this.image,
    required this.reflection,
    this.perspective = 0.0006,
    this.onTap,
  });
  final CoverSlot slot;
  final double dx;
  final double size;
  final Widget image;
  final double reflection;
  final double perspective;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final b = slot.brightness;
    return Transform(
      alignment: Alignment.topCenter,
      origin: Offset(0, size / 2), // pivote autour du milieu de la pochette
      // décalage à plat, puis réduction (côtés plus petits que le centre, maquette 3), puis inclinaison en perspective
      transform: Matrix4.translationValues(dx, 0, 0)
        ..multiply(Matrix4.diagonal3Values(slot.scale, slot.scale, 1))
        ..multiply(Matrix4.identity()..setEntry(3, 2, perspective))
        ..rotateY(slot.angle),
      child: GestureDetector(
        onTap: onTap,
        child: ColorFiltered(
          colorFilter: ColorFilter.matrix([
            b,
            0,
            0,
            0,
            0,
            0,
            b,
            0,
            0,
            0,
            0,
            0,
            b,
            0,
            0,
            0,
            0,
            0,
            1,
            0,
          ]),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              image,
              const SizedBox(height: 2),
              // reflet : seulement le haut de la pochette retournée
              ClipRect(
                child: Align(
                  alignment: Alignment.topCenter,
                  heightFactor: reflection,
                  child: ShaderMask(
                    shaderCallback: (r) => LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [context.colors.shine, context.colors.shineFade],
                      stops: [0, 0.9],
                    ).createShader(r),
                    blendMode: BlendMode.dstIn,
                    child: Transform.flip(flipY: true, child: image),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
