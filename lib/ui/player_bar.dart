import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../player/player.dart';
import '../player/queue.dart';
import '../theme/colors.dart';
import '../theme/widgets.dart';
import 'cover_image.dart';
import 'coverflow_screen.dart';
import 'now_playing_screen.dart';
import 'format.dart';

/// Barre de lecture du bas (maquette 2).
class PlayerBar extends StatefulWidget {
  const PlayerBar({super.key, this.eqOpen = false});
  final bool eqOpen; // sur l'écran En cours : la puce EQ est allumée
  @override
  State<PlayerBar> createState() => _PlayerBarState();
}

class _PlayerBarState extends State<PlayerBar> {
  double _volume = 80;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.strings;
    // iPad debout (< 900 px) : les côtés se resserrent, le Cover Flow reste dans la barre de côté
    final narrow = MediaQuery.sizeOf(context).width < 900;
    return Container(
      height: 84,
      decoration: const BoxDecoration(
        color: LafleurColors.bar,
        border: Border(top: BorderSide(color: LafleurColors.line)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: StreamBuilder<PlayerState>(
        stream: app.player.state,
        initialData: app.player.current,
        builder: (context, snap) {
          final st = snap.data ?? const PlayerState();
          final q = app.player.queue;
          final t = st.track;
          final total = st.duration.inMilliseconds;
          final f = total > 0
              ? (st.position.inMilliseconds / total).clamp(0.0, 1.0)
              : 0.0;
          return Row(
            children: [
              SizedBox(
                width: narrow ? 200 : 300,
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: widget.eqOpen
                          ? null
                          : () => openNowPlaying(context),
                      child: CoverImage(trackPath: t?.path, size: 54),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t?.title ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            t == null
                                ? ''
                                : (t.artist.isEmpty
                                      ? s.unknownArtist
                                      : t.artist),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: LafleurColors.sub,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _Btn(
                          Icons.shuffle_rounded,
                          on: q?.shuffle ?? false,
                          onTap: app.player.toggleShuffle,
                        ),
                        _Btn(
                          Icons.skip_previous_rounded,
                          onTap: app.player.previous,
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          child: InkWell(
                            key: const Key('playpause'),
                            onTap: app.player.toggle,
                            customBorder: const CircleBorder(),
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: const BoxDecoration(
                                color: LafleurColors.text,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                st.playing
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                color: LafleurColors.ink,
                              ),
                            ),
                          ),
                        ),
                        _Btn(Icons.skip_next_rounded, onTap: app.player.next),
                        _Btn(
                          q?.repeat == Repeat.one
                              ? Icons.repeat_one_rounded
                              : Icons.repeat_rounded,
                          on: (q?.repeat ?? Repeat.off) != Repeat.off,
                          onTap: app.player.cycleRepeat,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      width: 560,
                      child: Row(
                        children: [
                          Text(
                            clock(st.position),
                            style: const TextStyle(
                              color: LafleurColors.sub,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: LayoutBuilder(
                              builder: (_, c) => GestureDetector(
                                onTapDown: (d) => total > 0
                                    ? app.player.seek(
                                        Duration(
                                          milliseconds:
                                              (d.localPosition.dx /
                                                      c.maxWidth *
                                                      total)
                                                  .round(),
                                        ),
                                      )
                                    : null,
                                child: SizedBox(
                                  height: 14,
                                  child: Stack(
                                    alignment: Alignment.centerLeft,
                                    children: [
                                      Container(
                                        height: 5,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF3D3D3D),
                                          borderRadius: BorderRadius.circular(
                                            3,
                                          ),
                                        ),
                                      ),
                                      Container(
                                        height: 5,
                                        width: c.maxWidth * f,
                                        decoration: BoxDecoration(
                                          color: LafleurColors.pink,
                                          borderRadius: BorderRadius.circular(
                                            3,
                                          ),
                                        ),
                                      ),
                                      Positioned(
                                        left: (c.maxWidth * f - 6.5).clamp(
                                          0,
                                          c.maxWidth - 13,
                                        ),
                                        child: Container(
                                          width: 13,
                                          height: 13,
                                          decoration: const BoxDecoration(
                                            color: LafleurColors.text,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            '-${clock(st.duration - st.position)}',
                            style: const TextStyle(
                              color: LafleurColors.sub,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // au moins 300 (comme la partie gauche)
              ConstrainedBox(
                constraints: BoxConstraints(minWidth: narrow ? 0 : 300),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    ValueListenableBuilder(
                      valueListenable: app.equalizer,
                      builder: (_, eq, _) => LafleurChip(
                        label: 'EQ',
                        on: widget.eqOpen || eq.enabled,
                        onPressed: widget.eqOpen
                            ? null
                            : () => openNowPlaying(context),
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (!narrow) ...[
                      LafleurChip(
                        label: s.coverFlow,
                        onPressed: () => openCoverflow(context),
                      ),
                      const SizedBox(width: 12),
                    ],
                    const Icon(
                      Icons.volume_up_rounded,
                      size: 18,
                      color: LafleurColors.sub,
                    ),
                    SizedBox(
                      width: narrow ? 70 : 90,
                      child: SliderTheme(
                        data: const SliderThemeData(
                          trackHeight: 3,
                          thumbShape: RoundSliderThumbShape(
                            enabledThumbRadius: 6,
                          ),
                          overlayShape: RoundSliderOverlayShape(
                            overlayRadius: 10,
                          ),
                        ),
                        child: Slider(
                          value: _volume,
                          max: 100,
                          activeColor: LafleurColors.text,
                          inactiveColor: const Color(0xFF3D3D3D),
                          onChanged: (v) {
                            setState(() => _volume = v);
                            app.player.setVolume(v);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Btn extends StatelessWidget {
  const _Btn(this.icon, {this.on = false, required this.onTap});
  final IconData icon;
  final bool on;
  final Future<void> Function() onTap;
  @override
  Widget build(BuildContext context) => IconButton(
    onPressed: onTap,
    icon: Icon(
      icon,
      size: 20,
      color: on ? LafleurColors.pink : LafleurColors.text,
    ),
  );
}
