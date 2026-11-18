import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/l10n/strings.dart';

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
  test('textes de la maquette 2', () {
    final fr = Strings.of(const Locale('fr'));
    expect(fr.minutes(36), '36 min');
    expect(fr.upNext, 'À SUIVRE');
  });
}
