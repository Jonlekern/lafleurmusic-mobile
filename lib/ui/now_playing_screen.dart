import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_scope.dart';
import '../player/player.dart';
import '../theme/colors.dart';
import '../theme/widgets.dart';
import 'cover_image.dart';
import 'equalizer_panel.dart';
import 'playback_card.dart';
import 'player_bar.dart';

/// En cours + égaliseur (maquette 4). Échap pour revenir.
class NowPlayingScreen extends StatelessWidget {
  const NowPlayingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.strings;
    return Focus(
      autofocus: true,
      onKeyEvent: (_, e) {
        if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.escape) {
          Navigator.of(context).maybePop();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
        body: Column(
          children: [
            const TitleBar(),
            Expanded(
              child: StreamBuilder<PlayerState>(
                stream: app.player.state,
                initialData: app.player.current,
                builder: (context, snap) {
                  final t = snap.data?.track;
                  final q = app.player.queue;
                  final cover = (MediaQuery.sizeOf(context).height * 0.52)
                      .clamp(220.0, 470.0);
                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(60, 46, 60, 30),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                color: context.colors.coverBack,
                                blurRadius: 60,
                                offset: Offset(0, 20),
                              ),
                            ],
                          ),
                          child: CoverImage(
                            trackPath: t?.path,
                            size: cover,
                            radius: 8,
                          ),
                        ),
                        const SizedBox(width: 60),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 10),
                              if (t != null && q != null)
                                Text(
                                  s.nOfM(
                                    q.position + 1,
                                    q.order.length,
                                    t.album,
                                  ),
                                  style: TextStyle(
                                    color: context.colors.sub,
                                    fontSize: 14,
                                  ),
                                ),
                              const SizedBox(height: 10),
                              Text(
                                t?.title ?? '',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 46,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                t == null
                                    ? ''
                                    : (t.artist.isEmpty
                                          ? s.unknownArtist
                                          : t.artist),
                                style: const TextStyle(fontSize: 22),
                              ),
                              const SizedBox(height: 46),
                              EqualizerPanel(
                                equalizer: app.equalizer,
                                strings: s,
                              ),
                              const SizedBox(height: 22),
                              const PlaybackCard(),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const PlayerBar(eqOpen: true),
          ],
        ),
      ),
    );
  }
}

void openNowPlaying(BuildContext context) => Navigator.of(context).push(
  PageRouteBuilder<void>(
    pageBuilder: (_, _, _) => const NowPlayingScreen(),
    transitionsBuilder: (_, a, _, child) =>
        FadeTransition(opacity: a, child: child),
  ),
);
