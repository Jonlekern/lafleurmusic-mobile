import 'package:mpv_audio_kit/mpv_audio_kit.dart'
    show AudioEffect, EqualizerEffect, EqualizerWidthType, StereotoolsEffect;

import 'dart:typed_data';

import 'equalizer.dart';

/// Égaliseur → filtres mpv : une cloche d'une octave par bande non nulle ; OFF ou tout à 0 → aucun filtre.
List<AudioEffect> equalizerEffects(Equalizer eq) => [
  if (eq.enabled)
    for (var i = 0; i < Equalizer.bands.length; i++)
      if (eq.gains[i] != 0)
        EqualizerEffect(
          frequency: Equalizer.bands[i].toDouble(),
          width: 1,
          widthType: EqualizerWidthType.o,
          gain: eq.gains[i],
        ),
];

/// Tous les effets envoyés à mpv : égaliseur + balance (mpv remplace la liste entière à chaque envoi).
List<AudioEffect> audioEffects(Equalizer eq, double balance) => [
  ...equalizerEffects(eq),
  if (balance != 0) StereotoolsEffect(balanceOut: balance.clamp(-1.0, 1.0)),
];

/// Bandes du spectre (0–1) → 19 barres du visualiseur Winamp : le max de chaque groupe.
List<double> spectrumBars(List<double> bands, [int n = 19]) {
  if (bands.isEmpty) return List.filled(n, 0.0);
  return [
    for (var i = 0; i < n; i++)
      () {
        final a = i * bands.length ~/ n;
        final b = ((i + 1) * bands.length ~/ n).clamp(a + 1, bands.length);
        var m = 0.0;
        for (var j = a; j < b; j++) {
          if (bands[j] > m) m = bands[j];
        }
        return m.clamp(0.0, 1.0);
      }(),
  ];
}

/// Échantillons (entrelacés par canal) → n points mono entre −1 et 1 pour l'oscilloscope.
List<double> wavePoints(Float32List samples, int channels, [int n = 76]) {
  final ch = channels < 1 ? 1 : channels;
  final frames = samples.length ~/ ch;
  if (frames == 0) return List.filled(n, 0.0);
  return [
    for (var i = 0; i < n; i++)
      () {
        final f = i * frames ~/ n;
        var sum = 0.0;
        for (var c = 0; c < ch; c++) {
          sum += samples[f * ch + c];
        }
        return (sum / ch).clamp(-1.0, 1.0);
      }(),
  ];
}
