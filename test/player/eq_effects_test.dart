import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/player/eq_effects.dart';
import 'package:lafleurmusic/player/equalizer.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart'
    show EqualizerEffect, EqualizerWidthType, StereotoolsEffect;

import 'dart:typed_data';

void main() {
  test('OFF : aucun effet', () {
    expect(equalizerEffects(Equalizer.named('bass')), isEmpty);
  });
  test('Basses : une bande en cloche d’une octave par bande non nulle', () {
    final fx = equalizerEffects(Equalizer.named('bass').copyWith(enabled: true))
        .cast<EqualizerEffect>();
    expect(fx.map((e) => e.frequency), [31, 62, 125, 250]);
    expect(fx.map((e) => e.gain), [6, 5, 4, 2]);
    expect(
      fx.every((e) => e.width == 1 && e.widthType == EqualizerWidthType.o),
      isTrue,
    );
  });
  test('Plat ON : aucun effet (son d’origine)', () {
    expect(
      equalizerEffects(Equalizer.named('flat').copyWith(enabled: true)),
      isEmpty,
    );
  });

  test('EQ Rock + balance : les deux ensemble, l’un n’efface pas l’autre', () {
    final fx = audioEffects(
      Equalizer.named('rock').copyWith(enabled: true),
      0.5,
    );
    expect(fx.whereType<EqualizerEffect>().length, 10);
    expect(fx.whereType<StereotoolsEffect>().single.balanceOut, 0.5);
  });

  test('balance au centre et EQ OFF : aucun effet', () {
    expect(audioEffects(Equalizer.named('rock'), 0), isEmpty);
  });

  test('balance bornée à −1…1', () {
    expect(
      audioEffects(
        Equalizer.named('flat'),
        3,
      ).whereType<StereotoolsEffect>().single.balanceOut,
      1,
    );
  });

  test('spectre : 64 bandes → 19 barres (le max de chaque groupe)', () {
    final bands = List<double>.generate(64, (i) => i == 10 ? 0.9 : 0.1);
    final bars = spectrumBars(bands);
    expect(bars.length, 19);
    expect(bars.reduce((a, b) => a > b ? a : b), 0.9);
    expect(spectrumBars(const []), List.filled(19, 0.0));
  });

  test('vague : stéréo mélangée en mono, 76 points entre −1 et 1', () {
    final samples = Float32List.fromList([
      for (var i = 0; i < 400; i++) i.isEven ? 1.0 : -1.0,
    ]);
    final w = wavePoints(samples, 2);
    expect(w.length, 76);
    expect(w.every((v) => v == 0), isTrue); // gauche +1, droite −1 → 0
    expect(wavePoints(Float32List(0), 2), List.filled(76, 0.0));
  });
}
