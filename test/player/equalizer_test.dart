import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/player/equalizer.dart';

void main() {
  test('10 bandes de 31 Hz à 16 kHz', () {
    expect(Equalizer.bands, [
      31,
      62,
      125,
      250,
      500,
      1000,
      2000,
      4000,
      8000,
      16000,
    ]);
  });
  test('préréglage Basses', () {
    expect(Equalizer.named('bass').gains, [6, 5, 4, 2, 0, 0, 0, 0, 0, 0]);
    expect(Equalizer.named('flat').gains, List.filled(10, 0.0));
  });
  test('toucher une bande passe sur « Mon réglage », bornée à ±12 dB', () {
    final e = Equalizer.named('rock').withGain(0, 20);
    expect(e.gains.first, 12);
    expect(e.preset, 'custom');
    expect(Equalizer.named('flat').withGain(3, -30).gains[3], -12);
  });
  test('aller-retour JSON', () {
    final e = Equalizer.named('vocal').copyWith(enabled: true);
    final back = Equalizer.fromJson(e.toJson());
    expect(back.gains, e.gains);
    expect(back.enabled, true);
    expect(back.preset, 'vocal');
  });
  test('JSON cassé : Plat, OFF', () {
    final e = Equalizer.fromJson({'gains': 'x'});
    expect(e.enabled, false);
    expect(e.gains, List.filled(10, 0.0));
  });
}
