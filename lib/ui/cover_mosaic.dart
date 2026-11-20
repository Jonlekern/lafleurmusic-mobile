import 'package:flutter/material.dart';

import '../library/models.dart';
import 'cover_image.dart';

/// Pochettes à montrer pour une liste qui n'est pas un album (Morceaux, Artiste, Genre…) :
/// une de chacun des 4 premiers albums qui en ont une ; moins de 4 albums : une seule ; aucune : la fleur.
List<String> mosaicPaths(List<Track> tracks) {
  final seen = <String>{};
  final out = <String>[];
  for (final t in tracks) {
    if (!t.hasCover || seen.contains(t.album)) continue;
    seen.add(t.album);
    out.add(t.path);
    if (out.length == 4) return out;
  }
  return out.take(1).toList();
}

/// Mosaïque 2 × 2 façon iTunes, ou une seule pochette.
class CoverMosaic extends StatelessWidget {
  const CoverMosaic({
    super.key,
    required this.tracks,
    required this.size,
    this.radius = 6,
  });
  final List<Track> tracks;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final paths = mosaicPaths(tracks);
    if (paths.length < 4) {
      return CoverImage(
        trackPath: paths.isEmpty ? null : paths.first,
        size: size,
        radius: radius,
      );
    }
    final half = size / 2;
    final mosaic = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: Wrap(
          children: [
            for (final p in paths)
              CoverImage(trackPath: p, size: half, radius: 0, edge: false),
          ],
        ),
      ),
    );
    return CoverEdge(radius: radius, child: mosaic);
  }
}
