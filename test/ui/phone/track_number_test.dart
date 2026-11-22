import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/library/models.dart';
import 'package:lafleurmusic/ui/phone/album_screen.dart';

import '../fonts.dart';
import '../keep_fixture.dart';

List<Track> _tracks(List<int> nos) => [
  for (final n in nos)
    Track(
      path: '/t/$n.mp3',
      title: 'Titre $n',
      artist: 'Artiste',
      album: 'Album',
      trackNo: n,
      durationMs: 180000,
      hasCover: false,
      size: 1,
    ),
];

Future<void> _pump(WidgetTester tester, double scale, List<int> nos) =>
    pumpKeep(
      tester,
      addAccount: false,
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: Scaffold(
            body: SingleChildScrollView(
              child: PhoneTrackRows(tracks: _tracks(nos)),
            ),
          ),
        ),
      ),
    );

Finder _no(String n) => find.text(n);

void main() {
  setUpAll(loadFonts);

  testWidgets('texte ×1,6 : chaque numéro tient sur une ligne, rien de coupé', (
    tester,
  ) async {
    await _pump(tester, 1.6, [9, 13, 15, 120]);
    final oneLine = tester.getSize(_no('9')).height;
    for (final n in ['9', '13', '15', '120']) {
      final box = tester.renderObject<RenderBox>(_no(n));
      expect(box.size.height, oneLine, reason: '« $n » sur une seule ligne');
      final para = tester.renderObject<RenderParagraph>(_no(n));
      expect(para.didExceedMaxLines, isFalse, reason: n);
      expect(
        para.getMaxIntrinsicWidth(double.infinity),
        lessThanOrEqualTo(box.size.width),
        reason: '« $n » entier dans sa colonne',
      );
    }
    // une même colonne : tous les numéros finissent au même bord droit
    final rights = {
      for (final n in ['9', '13', '15', '120'])
        tester.getTopRight(_no(n)).dx.roundToDouble(),
    };
    expect(rights.length, 1);
    // et le plus large (120) a de la place
    expect(tester.getSize(_no('120')).width, greaterThan(20));
  });

  testWidgets('texte normal : la colonne fait au moins 20 points', (
    tester,
  ) async {
    await _pump(tester, 1.0, [1, 2, 9]);
    for (final n in ['1', '2', '9']) {
      expect(tester.getSize(_no(n)).width, 20, reason: n);
    }
  });
}
