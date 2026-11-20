import 'dart:io';

import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../theme/colors.dart';

/// Pochette d'un morceau (cache Covers), la fleur LAFLEUR en attendant ou s'il n'y en a pas.
class CoverImage extends StatelessWidget {
  const CoverImage({
    super.key,
    required this.trackPath,
    required this.size,
    this.radius = 4,
    this.edge = true,
  });
  final String? trackPath;
  final double size;
  final double radius;

  /// Filet du mode clair ; non pour une case de mosaïque (le filet entoure la mosaïque entière).
  final bool edge;

  int get _cacheSize => size <= 64 ? 64 : (size <= 300 ? 300 : 600);

  @override
  Widget build(BuildContext context) {
    final covers = AppScope.of(context).covers;
    final fallback = Image.asset(
      'assets/fleur-tile.png',
      width: size,
      height: size,
      fit: BoxFit.cover,
    );
    final path = trackPath;
    final cover = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: path == null
            ? fallback
            : FutureBuilder<File?>(
                key: ValueKey('$path-$_cacheSize'),
                future: covers.get(path, _cacheSize),
                builder: (_, snap) => snap.data == null
                    ? fallback
                    : Image.file(
                        snap.data!,
                        width: size,
                        height: size,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                      ),
              ),
      ),
    );
    return edge ? CoverEdge(radius: radius, child: cover) : cover;
  }
}

/// Mode clair : un filet fin autour d'une pochette, pour qu'une pochette blanche ne se perde pas sur
/// le fond blanc. Mode sombre : rien.
class CoverEdge extends StatelessWidget {
  const CoverEdge({super.key, required this.radius, required this.child});
  final double radius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final color = context.colors.coverEdge;
    if (color.a == 0) return child;
    return DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: child,
    );
  }
}
