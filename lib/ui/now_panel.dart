import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../library/models.dart';
import '../player/player.dart';
import '../theme/colors.dart';
import 'cover_image.dart';
import 'now_playing_screen.dart';

/// Panneau de droite (maquettes 2 et 8a) : en cours, puis À suivre (ajouts glissables, suite de l'album).
class NowPanel extends StatelessWidget {
  const NowPanel({super.key, this.extra});
  final Widget? extra; // sous « À suivre » (ex. résumé de l'artiste affiché)

  static const head = TextStyle(
    color: LafleurColors.sub,
    fontSize: 11,
    letterSpacing: 0.9,
    fontWeight: FontWeight.w700,
  );
  static const _section = TextStyle(
    color: Color(0xFF777777),
    fontSize: 10,
    letterSpacing: 0.9,
    fontWeight: FontWeight.w700,
  );

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.strings;
    return Container(
      width: 300,
      alignment: Alignment.topCenter, // toute la hauteur, contenu en haut
      decoration: const BoxDecoration(
        color: LafleurColors.panel,
        border: Border(left: BorderSide(color: LafleurColors.line)),
      ),
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 0),
      child: StreamBuilder<void>(
        stream: app.player.queueChanged,
        builder: (context, _) => StreamBuilder<PlayerState>(
          stream: app.player.state,
          initialData: app.player.current,
          builder: (context, snap) {
            final t = snap.data?.track;
            final q = app.player.queue;
            final added = q?.addedCount ?? 0;
            final first = (q?.position ?? 0) + 1;
            final next = q?.upcomingIndexes(10) ?? const <int>[];
            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.nowPlaying, style: head),
                  const SizedBox(height: 14),
                  GestureDetector(
                    onTap: () => openNowPlaying(context),
                    child: CoverImage(trackPath: t?.path, size: 264, radius: 6),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    t?.title ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    t == null
                        ? ''
                        : '${t.artist.isEmpty ? s.unknownArtist : t.artist} · ${t.album}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: LafleurColors.sub,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (q != null && (added > 0 || next.isNotEmpty))
                    Row(
                      children: [
                        Expanded(child: Text(s.upNext, style: head)),
                        if (added > 0)
                          GestureDetector(
                            onTap: app.player.clearAdded,
                            child: Text(
                              s.clearQueue,
                              style: const TextStyle(
                                color: LafleurColors.pink,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),
                  if (q != null && added > 0) ...[
                    const SizedBox(height: 12),
                    Text(s.addedByYou, style: _section),
                    const SizedBox(height: 4),
                    for (var i = first; i < first + added; i++)
                      _UpNextRow(index: i, track: q.order[i]),
                  ],
                  if (q != null && next.isNotEmpty) ...[
                    if (added > 0) ...[
                      const SizedBox(height: 14),
                      Text(s.nextInAlbum, style: _section),
                    ],
                    const SizedBox(height: 4),
                    for (final i in next)
                      _UpNextRow(index: i, track: q.order[i]),
                  ],
                  ?extra,
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Une ligne d'À suivre : ⋮⋮ pour glisser, ✕ pour retirer ; on dépose une ligne sur une autre pour la placer devant.
class _UpNextRow extends StatelessWidget {
  const _UpNextRow({required this.index, required this.track});
  final int index; // place dans queue.order
  final Track track;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.strings;
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Draggable<int>(
            key: Key('upnext-grip-$index'),
            data: index,
            feedback: Material(
              color: Colors.transparent,
              child: Opacity(
                opacity: 0.85,
                child: SizedBox(
                  width: 264,
                  child: Text(
                    track.title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
            child: const MouseRegion(
              cursor: SystemMouseCursors.grab,
              child: Icon(
                Icons.drag_indicator_rounded,
                size: 16,
                color: Color(0xFF666666),
              ),
            ),
          ),
          const SizedBox(width: 6),
          CoverImage(trackPath: track.path, size: 38),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  track.artist.isEmpty ? s.unknownArtist : track.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: LafleurColors.sub,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            key: Key('upnext-remove-$index'),
            onPressed: () => app.player.removeAt(index),
            icon: const Icon(Icons.close_rounded, size: 16),
            color: const Color(0xFF777777),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
    return DragTarget<int>(
      onWillAcceptWithDetails: (d) => d.data != index,
      // déposé sur cette ligne : prend sa place (celle-ci descend d'un cran)
      onAcceptWithDetails: (d) =>
          app.player.moveUpcoming(d.data, d.data < index ? index - 1 : index),
      builder: (_, cand, _) => Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: cand.isEmpty ? Colors.transparent : LafleurColors.pink,
              width: 2,
            ),
          ),
        ),
        child: row,
      ),
    );
  }
}
