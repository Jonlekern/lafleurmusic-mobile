import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../theme/colors.dart';

/// Carte « Lecture » sous l'égaliseur (maquette 9b) : Volume égal, Fondu enchaîné (1 à 10 s).
class PlaybackCard extends StatefulWidget {
  const PlaybackCard({super.key});
  @override
  State<PlaybackCard> createState() => _PlaybackCardState();
}

class _PlaybackCardState extends State<PlaybackCard> {
  double? _dragging; // valeur du curseur pendant qu'on le glisse

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.strings;
    final set = app.settings;
    if (set == null) return const SizedBox.shrink();
    void save() => app.saveSettings?.call();
    final seconds = (_dragging ?? set.crossfadeSeconds.toDouble()).round();

    Widget option({
      required Key key,
      required bool on,
      required String title,
      required String hint,
      required ValueChanged<bool> onChanged,
      Widget? trailing,
      bool top = false,
    }) => Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: top
            ? const Border(top: BorderSide(color: Color(0xFF222222)))
            : null,
      ),
      child: Row(
        children: [
          Switch(
            key: key,
            value: on,
            onChanged: onChanged,
            activeThumbColor: Colors.white,
            activeTrackColor: LafleurColors.pink,
            inactiveThumbColor: Colors.white,
            inactiveTrackColor: const Color(0xFF444444),
            trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(
                  hint,
                  style: const TextStyle(
                    color: LafleurColors.sub,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(26, 22, 26, 12),
      decoration: BoxDecoration(
        color: LafleurColors.panel,
        border: Border.all(color: LafleurColors.line),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            s.playbackCard,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
          ),
          option(
            key: const Key('equal-volume'),
            on: set.equalVolume,
            title: s.equalVolume,
            hint: s.equalVolumeHint,
            onChanged: (v) {
              setState(() => set.equalVolume = v);
              app.loudness?.enabled = v;
              save();
            },
          ),
          option(
            key: const Key('crossfade'),
            top: true,
            on: set.crossfade,
            title: s.crossfadeLabel,
            hint: s.crossfadeHint,
            onChanged: (v) {
              setState(() => set.crossfade = v);
              app.player.setCrossfade(v ? set.crossfadeSeconds : null);
              save();
            },
            trailing: Opacity(
              opacity: set.crossfade ? 1 : 0.45,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 170,
                    child: SliderTheme(
                      data: const SliderThemeData(
                        trackHeight: 4,
                        activeTrackColor: LafleurColors.pink,
                        inactiveTrackColor: Color(0xFF444444),
                        thumbColor: Colors.white,
                        overlayShape: RoundSliderOverlayShape(
                          overlayRadius: 12,
                        ),
                      ),
                      child: Slider(
                        min: 1,
                        max: 10,
                        divisions: 9,
                        value: seconds.toDouble(),
                        onChanged: set.crossfade
                            ? (v) => setState(() => _dragging = v)
                            : null,
                        onChangeEnd: (v) {
                          setState(() {
                            _dragging = null;
                            set.crossfadeSeconds = v.round();
                          });
                          app.player.setCrossfade(set.crossfadeSeconds);
                          save();
                        },
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 40,
                    child: Text(
                      s.seconds(seconds),
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
