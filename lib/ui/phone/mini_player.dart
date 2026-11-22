import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../app_scope.dart';
import '../../player/player.dart';
import '../../theme/colors.dart';
import '../cover_image.dart';
import '../format.dart';
import '../seek_area.dart';
import 'now_screen.dart';

/// Mini-lecteur du téléphone (bas de l'Accueil et des listes) : fil de progression rose, pochette, titre,
/// pause et suivant. Toucher ou glisser le fil avance dans le morceau ; toucher ailleurs ouvre En cours. Rien tant qu'aucun morceau n'est chargé.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  /// Le fil rose, fin.
  static const lineHeight = 3.0;

  /// La bande de toucher invisible, centrée sur le fil (maquette 20 C) : toucher saute,
  /// glisser fait suivre le fil et saute au lâcher.
  static const touchBand = 28.0;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return StreamBuilder<PlayerState>(
      stream: app.player.state,
      initialData: app.player.current,
      builder: (context, snap) {
        final st = snap.data ?? const PlayerState();
        final t = st.track;
        if (t == null) return const SizedBox.shrink();
        final total = st.duration.inMilliseconds;
        final f = total > 0
            ? (st.position.inMilliseconds / total).clamp(0.0, 1.0)
            : 0.0;
        return _OverflowStack(
          clipBehavior: Clip.none,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => openNow(context),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // le fil (dessiné par la bande ci-dessous) garde sa place
                  const SizedBox(height: MiniPlayer.lineHeight),
                  Container(
                    height: 64,
                    decoration: BoxDecoration(
                      color: context.colors.bar,
                      border: Border(
                        top: BorderSide(color: context.colors.hairline),
                      ),
                    ),
                    padding: const EdgeInsets.only(left: 16, right: 6),
                    child: Row(
                      children: [
                        CoverImage(trackPath: t.path, size: 42),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                t.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                t.artist.isEmpty
                                    ? app.strings.unknownArtist
                                    : t.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: context.colors.textMuted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          key: const Key('mini-toggle'),
                          onPressed: app.player.toggle,
                          visualDensity: VisualDensity.compact,
                          icon: Icon(
                            st.playing
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            size: 24,
                            color: context.colors.text,
                          ),
                        ),
                        IconButton(
                          key: const Key('mini-next'),
                          onPressed: app.player.next,
                          visualDensity: VisualDensity.compact,
                          icon: Icon(
                            Icons.skip_next_rounded,
                            size: 24,
                            color: context.colors.text,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // la bande de toucher, centrée sur le fil, déborde sur la liste au-dessus
            Positioned(
              left: 0,
              right: 0,
              top: (MiniPlayer.lineHeight - MiniPlayer.touchBand) / 2,
              height: MiniPlayer.touchBand,
              child: SeekArea(
                key: const Key('mini-seek'),
                total: total,
                fraction: f,
                track: t.path,
                onSeek: app.player.seek,
                builder: (context, f, dragging) => _Line(
                  fraction: f,
                  dragging: dragging,
                  time: Duration(milliseconds: (f * total).round()),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Le fil de 3 points au milieu de la bande de toucher ; pendant un glisser, le rond rose et
/// le temps au-dessus (maquette 20 C).
class _Line extends StatelessWidget {
  const _Line({
    required this.fraction,
    required this.dragging,
    required this.time,
  });
  final double fraction;
  final bool dragging;
  final Duration time;

  static const knob = 14.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      const top = (MiniPlayer.touchBand - MiniPlayer.lineHeight) / 2;
      const mid = MiniPlayer.touchBand / 2;
      final x = c.maxWidth * fraction;
      return Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: top,
            height: MiniPlayer.lineHeight,
            child: Container(
              color: context.colors.divider,
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: fraction,
                child: Container(color: context.colors.pink),
              ),
            ),
          ),
          if (dragging) ...[
            Positioned(
              key: const Key('mini-seek-knob'),
              left: x - knob / 2,
              top: mid - knob / 2,
              width: knob,
              height: knob,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: context.colors.pink,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: context.colors.shadow.withValues(alpha: .35),
                      blurRadius: 3,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
              ),
            ),
            // le temps, centré au-dessus du rond, sans sortir de l'écran
            Positioned(
              left: 0,
              right: 0,
              bottom: MiniPlayer.touchBand - mid + knob / 2 + 8,
              child: IgnorePointer(
                child: CustomSingleChildLayout(
                  delegate: _CenterOn(x),
                  child: Container(
                    key: const Key('mini-seek-time'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: context.colors.text,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      clock(time),
                      maxLines: 1,
                      softWrap: false,
                      style: TextStyle(
                        color: context.colors.bg,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      );
    },
  );
}

/// Place l'enfant centré sur [x], gardé dans la largeur, son bas sur le bas de la boîte
/// (la boîte n'a pas de hauteur : l'étiquette monte au-dessus).
class _CenterOn extends SingleChildLayoutDelegate {
  const _CenterOn(this.x);
  final double x;

  @override
  Size getSize(BoxConstraints constraints) =>
      Size(constraints.maxWidth, constraints.constrainHeight(0));

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size child) {
    final max = size.width - child.width;
    return Offset(
      (x - child.width / 2).clamp(0.0, max < 0 ? 0.0 : max),
      size.height - child.height,
    );
  }

  @override
  bool shouldRelayout(_CenterOn old) => old.x != x;
}

/// Un Stack dont les enfants qui débordent (la bande de toucher au-dessus du fil) se touchent
/// aussi : un RenderStack ordinaire ne regarde que sa propre taille.
class _OverflowStack extends Stack {
  const _OverflowStack({super.clipBehavior, super.children});

  @override
  RenderStack createRenderObject(BuildContext context) => _RenderOverflowStack(
    alignment: alignment,
    textDirection: textDirection ?? Directionality.maybeOf(context),
    fit: fit,
    clipBehavior: clipBehavior,
  );
}

class _RenderOverflowStack extends RenderStack {
  _RenderOverflowStack({
    super.alignment,
    super.textDirection,
    super.fit,
    super.clipBehavior,
  });

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (size.contains(position)) {
      return super.hitTest(result, position: position);
    }
    if (hitTestChildren(result, position: position)) {
      result.add(BoxHitTestEntry(this, position));
      return true;
    }
    return false;
  }
}
