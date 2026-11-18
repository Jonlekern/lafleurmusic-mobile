import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../player/equalizer.dart';
import '../theme/colors.dart';
import '../theme/widgets.dart';

/// Panneau d'égaliseur (maquette 4) : ON / OFF, préréglages, 10 curseurs verticaux.
class EqualizerPanel extends StatelessWidget {
  const EqualizerPanel({
    super.key,
    required this.equalizer,
    required this.strings,
  });
  final ValueNotifier<Equalizer> equalizer;
  final Strings strings;

  static String _freq(int hz) => hz >= 1000 ? '${hz ~/ 1000}k' : '$hz';

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Equalizer>(
    valueListenable: equalizer,
    builder: (context, eq, _) => Container(
      padding: const EdgeInsets.fromLTRB(26, 22, 26, 22),
      decoration: BoxDecoration(
        color: LafleurColors.panel,
        border: Border.all(color: LafleurColors.line),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                strings.equalizer,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                ),
              ),
              const SizedBox(width: 24),
              LafleurChip(
                label: eq.enabled ? 'ON' : 'OFF',
                on: eq.enabled,
                onPressed: () =>
                    equalizer.value = eq.copyWith(enabled: !eq.enabled),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final k in [...Equalizer.presets.keys, 'custom'])
                      LafleurChip(
                        label: k == 'custom'
                            ? '＋ ${strings.presetName(k)}'
                            : strings.presetName(k),
                        on: eq.preset == k,
                        onPressed: k == 'custom'
                            ? () => equalizer.value = eq.copyWith(
                                preset: 'custom',
                                enabled: true,
                              )
                            : () =>
                                  equalizer.value = Equalizer.named(k)
                                      .copyWith(enabled: true),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 0; i < Equalizer.bands.length; i++)
                Column(
                  children: [
                    _Band(
                      key: Key('band-$i'),
                      gain: eq.gains[i],
                      active: eq.enabled,
                      onChanged: (db) => equalizer.value = eq
                          .withGain(i, db)
                          .copyWith(enabled: true),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _freq(Equalizer.bands[i]),
                      style: const TextStyle(
                        color: LafleurColors.sub,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    ),
  );
}

/// Curseur vertical : rose du bas jusqu'au bouton blanc ; ±12 dB sur 230 px.
class _Band extends StatelessWidget {
  const _Band({
    super.key,
    required this.gain,
    required this.active,
    required this.onChanged,
  });
  final double gain;
  final bool active;
  final void Function(double db) onChanged;

  static const h = 230.0;

  double _dbAt(double y) => ((h / 2 - y) / (h / 2) * Equalizer.maxDb).clamp(
    -Equalizer.maxDb,
    Equalizer.maxDb,
  );

  @override
  Widget build(BuildContext context) {
    final f =
        (gain + Equalizer.maxDb) / (2 * Equalizer.maxDb); // 0 en bas, 1 en haut
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragStart: (d) => onChanged(_dbAt(d.localPosition.dy)),
      onVerticalDragUpdate: (d) => onChanged(_dbAt(d.localPosition.dy)),
      onTapDown: (d) => onChanged(_dbAt(d.localPosition.dy)),
      child: SizedBox(
        width: 30,
        height: h,
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            Container(
              width: 6,
              decoration: BoxDecoration(
                color: const Color(0xFF333333),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            Container(
              width: 6,
              height: h * f,
              decoration: BoxDecoration(
                color: active ? LafleurColors.pink : const Color(0xFF666666),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            Positioned(
              bottom: (h * f - 10).clamp(0, h - 20),
              child: Container(
                width: 20,
                height: 20,
                decoration: const BoxDecoration(
                  color: LafleurColors.text,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
