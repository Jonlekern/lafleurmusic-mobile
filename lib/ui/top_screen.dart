import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../library/models.dart';
import '../player/player.dart';
import '../theme/colors.dart';
import '../theme/widgets.dart';
import 'cover_image.dart';
import 'track_menu.dart';

/// Top 100 (maquette 9a) : les morceaux les plus écoutés et leur nombre d'écoutes.
class TopScreen extends StatelessWidget {
  const TopScreen({super.key, this.onPlay});
  final VoidCallback? onPlay; // ex. rendre le clavier au lecteur après un clic

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.strings;
    return StreamBuilder<List<(Track, int)>>(
      stream: app.library.top(100),
      builder: (context, snap) {
        final rows = snap.data ?? const <(Track, int)>[];
        final tracks = [for (final r in rows) r.$1];
        final most = rows.isEmpty ? 1 : rows.first.$2;
        return Padding(
          padding: const EdgeInsets.fromLTRB(30, 26, 30, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                s.topLabel,
                style: TextStyle(
                  color: context.colors.sub,
                  fontSize: 12,
                  letterSpacing: 1,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        s.mostPlayed,
                        style: const TextStyle(
                          fontSize: 44,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  PillButton(
                    label: s.play,
                    icon: Icons.play_arrow_rounded,
                    primary: true,
                    onPressed: tracks.isEmpty
                        ? null
                        : () => app.player.playTracks(tracks, 0),
                  ),
                  const SizedBox(width: 12),
                  PillButton(
                    label: s.shuffle,
                    icon: Icons.shuffle_rounded,
                    onPressed: tracks.isEmpty
                        ? null
                        : () => app.player.playTracks(tracks, 0, shuffle: true),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                s.playRule,
                style: TextStyle(color: context.colors.sub, fontSize: 13),
              ),
              const SizedBox(height: 22),
              const _Line(head: true),
              Expanded(
                child: rows.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.only(top: 30),
                        child: Text(
                          s.topEmpty,
                          style: TextStyle(
                            color: context.colors.sub,
                            fontSize: 15,
                          ),
                        ),
                      )
                    : StreamBuilder<PlayerState>(
                        stream: app.player.state,
                        initialData: app.player.current,
                        builder: (context, st) => ListView.builder(
                          itemCount: rows.length,
                          itemBuilder: (_, i) => TrackMenuArea(
                            track: rows[i].$1,
                            child: GestureDetector(
                              onTap: () {
                                onPlay?.call();
                                app.player.playTracks(tracks, i);
                              },
                              child: _Line(
                                rank: i + 1,
                                track: rows[i].$1,
                                plays: rows[i].$2,
                                most: most,
                                selected:
                                    st.data?.track?.path == rows[i].$1.path,
                              ),
                            ),
                          ),
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({
    this.head = false,
    this.rank = 0,
    this.track,
    this.plays = 0,
    this.most = 1,
    this.selected = false,
  });
  final bool head, selected;
  final int rank, plays, most;
  final Track? track;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context).strings;
    final fg = selected
        ? context.colors.ink
        : (head ? context.colors.sub : context.colors.text);
    TextStyle st({bool bold = true, Color? color, double size = 14}) =>
        TextStyle(
          color: color ?? fg,
          fontSize: head ? 11 : size,
          letterSpacing: head ? 1 : 0,
          fontWeight: bold || head ? FontWeight.w700 : FontWeight.w400,
        );
    final t = track;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: head ? 0 : 7),
      margin: EdgeInsets.only(bottom: head ? 10 : 0),
      decoration: BoxDecoration(
        color: selected ? context.colors.pink : null,
        borderRadius: head ? null : BorderRadius.circular(8),
      ),
      child: SizedBox(
        height: head ? 22 : 34,
        child: Row(
          children: [
            SizedBox(
              width: 36,
              child: Text(head ? '#' : '$rank', style: st(size: 16)),
            ),
            if (head)
              const SizedBox(width: 46) // place de la pochette
            else ...[
              CoverImage(trackPath: t!.path, size: 34),
              const SizedBox(width: 12),
            ],
            Expanded(
              flex: 5,
              child: Text(
                head ? s.title : t!.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: st(),
              ),
            ),
            Expanded(
              flex: 4,
              child: Text(
                head
                    ? s.artist
                    : (t!.artist.isEmpty ? s.unknownArtist : t.artist),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: st(),
              ),
            ),
            Expanded(
              flex: 4,
              child: Text(
                head ? s.albumHeader : t!.album,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: st(
                  color: selected || head ? null : context.colors.textLabel,
                ),
              ),
            ),
            SizedBox(
              width: 220,
              child: head
                  ? Text(s.playsHeader, style: st())
                  : Row(
                      children: [
                        Container(
                          width: 130 * plays / most,
                          height: 6,
                          decoration: BoxDecoration(
                            color: selected
                                ? context.colors.onPink
                                : context.colors.pink,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text('$plays', style: st()),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
