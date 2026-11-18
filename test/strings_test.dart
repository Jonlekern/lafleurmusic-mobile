import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/l10n/strings.dart';
import 'package:lafleurmusic/sources/source.dart';

void main() {
  test('français si la langue commence par fr', () {
    expect(Strings.of(const Locale('fr')).whereIsMusic, 'Où est ta musique ?');
    expect(Strings.of(const Locale('fr', 'CH')).nSongs(9), '9 morceaux');
  });
  test('anglais sinon', () {
    expect(Strings.of(const Locale('en')).whereIsMusic, 'Where is your music?');
    expect(Strings.of(const Locale('de')).whereIsMusic, 'Where is your music?');
    expect(Strings.of(const Locale('en')).nSongs(9), '9 songs');
  });
  test('Tester : certificat refusé, rappel du réseau local (iPhone)', () {
    final fr = Strings.of(const Locale('fr'));
    final en = Strings.of(const Locale('en'));
    expect(
      fr.testResult(TestResult.certificateRejected),
      'Certificat refusé (https)',
    );
    expect(
      en.testResult(TestResult.certificateRejected),
      'Certificate rejected (https)',
    );
    expect(
      fr.localNetworkHint,
      "Vérifie aussi que l'accès au réseau local est autorisé dans Réglages → LAFLEURMUSIC.",
    );
    expect(en.localNetworkHint, contains('local network access'));
  });
  test('textes de la maquette 2', () {
    final fr = Strings.of(const Locale('fr'));
    expect(fr.minutes(36), '36 min');
    expect(fr.upNext, 'À SUIVRE');
  });
}
