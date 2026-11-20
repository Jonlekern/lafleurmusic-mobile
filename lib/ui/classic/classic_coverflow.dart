import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_scope.dart';
import '../../library/models.dart';
import '../../theme/colors.dart';
import '../cover_image.dart';
import '../coverflow_layout.dart';

/// Un glissé de cette longueur (px) = un album, comme un cran de molette.
const _dragStep = 48.0;

/// Maquette 18 A : le Cover Flow du Mode Classic, dans l'écran façon iPod (sous le titre
/// COVER FLOW), la molette restant dessous. La pochette choisie au milieu, à plat, ses voisines
/// inclinées, les reflets ; le nom de l'album et l'artiste dessous, « n sur m » en bas.
/// La molette choisit l'album ([ClassicMenu]) ; le doigt glissé sur les pochettes aussi ([onMove]).
class ClassicCoverflow extends StatefulWidget {
  const ClassicCoverflow({
    super.key,
    required this.count,
    required this.index,
    required this.album,
    required this.onMove,
  });

  /// Le nombre d'albums, l'album choisi, et chaque album par son rang.
  final int count;
  final int index;
  final Album Function(int i) album;

  /// Un album plus loin (+) ou plus près (−), comme un cran de molette.
  final void Function(int steps) onMove;

  @override
  State<ClassicCoverflow> createState() => _ClassicCoverflowState();
}

class _ClassicCoverflowState extends State<ClassicCoverflow> {
  double _drag = 0;

  void _onDrag(DragUpdateDetails d) {
    _drag += d.delta.dx;
    while (_drag.abs() >= _dragStep) {
      final step = _drag < 0 ? 1 : -1; // vers la gauche : l'album suivant
      _drag += step * _dragStep;
      HapticFeedback.selectionClick();
      widget.onMove(step);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context).strings;
    final classic = context.classicColors;
    final n = widget.count;
    final album = n == 0 ? null : widget.album(widget.index.clamp(0, n - 1));
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: (_) => _drag = 0,
      onHorizontalDragUpdate: _onDrag,
      child: LayoutBuilder(
        builder: (context, c) {
          final h = c.maxHeight;
          final cover = h * 0.43;
          final k =
              cover / 400; // la géométrie du Cover Flow est donnée pour 400 px
          return Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned(
                top: h * 0.04,
                left: 0,
                right: 0,
                height: cover * 1.3,
                child: ExcludeSemantics(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(end: widget.index.toDouble()),
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    builder: (context, pos, _) => Stack(
                      alignment: Alignment.topCenter,
                      clipBehavior: Clip.none,
                      children: [
                        for (final i in drawOrder(pos, n))
                          _cover(layout(pos, i), i, cover, k),
                      ],
                    ),
                  ),
                ),
              ),
              if (album != null)
                Positioned(
                  top: h * 0.62,
                  left: 14,
                  right: 14,
                  child: Column(
                    children: [
                      Text(
                        album.name.isEmpty ? s.unknownArtist : album.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.colors.text,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (album.artist.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          album.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: classic.title, fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                ),
              if (album != null)
                Positioned(
                  bottom: 6,
                  left: 0,
                  right: 0,
                  child: Text(
                    s.classicPosition(widget.index + 1, n),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: classic.title, fontSize: 11),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _cover(CoverSlot slot, int i, double size, double k) => FlowCover(
    key: ValueKey(i),
    slot: slot,
    // maquette 18 : les voisines un peu plus loin que sur le téléphone couché
    dx: spreadDx(slot.dx) * k * 1.1,
    size: size,
    // la perspective suit la taille de la pochette (comme le grand Cover Flow, en petit)
    perspective: 0.2 / size,
    reflection: 0.25,
    image: CoverImage(
      trackPath: widget.album(i).coverTrackPath,
      size: size,
      radius: 0,
    ),
  );
}
