import 'dart:io';

import 'package:flutter/material.dart';

import '../app_scope.dart';

/// Pochette d'un morceau (cache Covers), la fleur LAFLEUR en attendant ou s'il n'y en a pas.
class CoverImage extends StatelessWidget {
  const CoverImage({
    super.key,
    required this.trackPath,
    required this.size,
    this.radius = 4,
  });
  final String? trackPath;
  final double size;
  final double radius;

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
    return ClipRRect(
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
  }
}
