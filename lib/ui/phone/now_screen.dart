import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../player/player.dart';
import '../../player/queue.dart';
import '../../theme/colors.dart';
import '../cover_image.dart';
import '../equalizer_panel.dart';
import '../format.dart';
import '../now_panel.dart';
import '../playback_card.dart';
import '../track_menu.dart';
import 'phone_shell.dart';

Future<void> openNow(BuildContext context) =>
    pushPhone(context, const NowScreen());

enum _Tab { upNext, equalizer, playback }

/// En cours sur le téléphone = la colonne de droite du Mac (maquette 1, écran 3) : pochette, titre,
/// progression, commandes, puis les onglets À suivre / Égaliseur / Lecture.
class NowScreen extends StatefulWidget {
  const NowScreen({super.key});
  @override
  State<NowScreen> createState() => _NowScreenState();
}

class _NowScreenState extends State<NowScreen> {
  _Tab _tab = _Tab.upNext;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.strings;
    return StreamBuilder<PlayerState>(
      stream: app.player.state,
      initialData: app.player.current,
      builder: (context, snap) {
        final st = snap.data ?? const PlayerState();
        final t = st.track;
        final q = app.player.queue;
        final total = st.duration.inMilliseconds;
        final f = total > 0
            ? (st.position.inMilliseconds / total).clamp(0.0, 1.0)
            : 0.0;
        Widget tab(_Tab k, String label) => GestureDetector(
          onTap: () => setState(() => _tab = k),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              border: Border.all(
                color: _tab == k ? LafleurColors.pink : const Color(0xFF444444),
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: _tab == k ? LafleurColors.pink : LafleurColors.text,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
        Widget btn(IconData icon, VoidCallback onTap, {bool on = false}) =>
            IconButton(
              onPressed: onTap,
              icon: Icon(
                icon,
                size: 28,
                color: on ? LafleurColors.pink : LafleurColors.text,
              ),
            );
        return PhoneScaffold(
          mini: false,
          header: PhoneHeader(
            leading: HeaderButton(
              icon: Icons.keyboard_arrow_down_rounded,
              color: LafleurColors.pink,
              size: 26,
              onTap: () => Navigator.of(context).maybePop(),
            ),
            trailing: HeaderButton(
              icon: Icons.more_horiz_rounded,
              onTap: t == null
                  ? null
                  : () => showTrackSheet(
                      context,
                      title: t.title,
                      sub: t.artist,
                      tracks: () async => [t],
                    ),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
            children: [
              Center(
                child: CoverImage(trackPath: t?.path, size: 300, radius: 8),
              ),
              const SizedBox(height: 18),
              Text(
                t?.title ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                t == null
                    ? ''
                    : '${t.artist.isEmpty ? s.unknownArtist : t.artist} · ${t.album}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFF999999), fontSize: 14),
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (_, c) => GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (d) => total > 0
                      ? app.player.seek(
                          Duration(
                            milliseconds:
                                (d.localPosition.dx / c.maxWidth * total)
                                    .round(),
                          ),
                        )
                      : null,
                  child: Container(
                    height: 12,
                    alignment: Alignment.centerLeft,
                    child: Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFF333333),
                        borderRadius: BorderRadius.circular(2),
                      ),
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: f,
                        child: Container(
                          decoration: BoxDecoration(
                            color: LafleurColors.pink,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Text(clock(st.position), style: _time),
                  const Spacer(),
                  Text('−${clock(st.duration - st.position)}', style: _time),
                ],
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    btn(
                      Icons.shuffle_rounded,
                      app.player.toggleShuffle,
                      on: q?.shuffle ?? false,
                    ),
                    btn(Icons.skip_previous_rounded, app.player.previous),
                    InkWell(
                      key: const Key('now-toggle'),
                      onTap: app.player.toggle,
                      customBorder: const CircleBorder(),
                      child: Container(
                        width: 64,
                        height: 64,
                        decoration: const BoxDecoration(
                          color: LafleurColors.pink,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          st.playing
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          size: 30,
                          color: LafleurColors.ink,
                        ),
                      ),
                    ),
                    btn(Icons.skip_next_rounded, app.player.next),
                    btn(
                      q?.repeat == Repeat.one
                          ? Icons.repeat_one_rounded
                          : Icons.repeat_rounded,
                      app.player.cycleRepeat,
                      on: (q?.repeat ?? Repeat.off) != Repeat.off,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  tab(_Tab.upNext, s.upNextTab),
                  const SizedBox(width: 8),
                  tab(_Tab.equalizer, s.equalizer),
                  const SizedBox(width: 8),
                  tab(_Tab.playback, s.playbackCard),
                ],
              ),
              const SizedBox(height: 14),
              switch (_tab) {
                _Tab.upNext => const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: UpNextSection(title: false, coverSize: 30),
                ),
                _Tab.equalizer => EqualizerPanel(
                  equalizer: app.equalizer,
                  strings: s,
                ),
                _Tab.playback => const PlaybackCard(),
              },
            ],
          ),
        );
      },
    );
  }

  static const _time = TextStyle(color: Color(0xFF999999), fontSize: 12);
}
