import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../player/player.dart';
import '../../theme/colors.dart';
import '../cover_image.dart';
import 'now_screen.dart';

/// Mini-lecteur du téléphone (bas de l'Accueil et des listes) : fil de progression rose, pochette, titre,
/// pause et suivant. Toucher ailleurs ouvre En cours. Rien tant qu'aucun morceau n'est chargé.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

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
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => openNow(context),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 3,
                color: context.colors.divider,
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: f,
                  child: Container(color: context.colors.pink),
                ),
              ),
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
        );
      },
    );
  }
}
