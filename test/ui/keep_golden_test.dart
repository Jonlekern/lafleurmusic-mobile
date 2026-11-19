// Pixel comparison: run on macOS only (CI job goldens), see dart_test.yaml.
@Tags(['golden'])
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/ui/phone/keep_screen.dart';
import 'package:lafleurmusic/ui/phone/phone_shell.dart';

import 'fonts.dart';
import 'keep_fixture.dart';
import 'phone_fixture.dart';

/// Garder hors ligne, 390 × 844 sur un iPhone : écran 8 de la maquette 2 ; Accueil (⬇ rose), album aux
/// morceaux grisés et feuille d'appui long de la maquette 1. Mêmes données que le mode démo.
void main() {
  setUpAll(() async {
    await loadFonts();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  Future<void> done(WidgetTester tester) async {
    await tester.pumpAndSettle();
    await settle(tester);
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester) async {
    await tester.ensureVisible(
      find.text('Studio Lafleur'),
    ); // sous le mini-lecteur sinon
    await tester.pump();
    await tester.tap(find.text('Studio Lafleur'));
    await done(tester);
  }

  testWidgets('8 Sélectionner → Garder sur mon iPhone', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await pumpKeep(
      tester,
      images: true,
      home: const KeepScreen(preselect: {'Studio Lafleur', 'Summer Mix'}),
    );
    await done(tester);
    await expectLater(
      find.byType(KeepScreen),
      matchesGoldenFile('goldens/phone-8.png'),
    );
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('1 Accueil, ⬇ rose après « Lafleur Surf »', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await pumpKeep(tester, images: true);
    await done(tester);
    await expectLater(
      find.byType(PhoneShell),
      matchesGoldenFile('goldens/phone-1-gardes.png'),
    );
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('2 Album, ⬇ rond et « Night Swim » grisé', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await pumpKeep(tester, images: true);
    await open(tester);
    await expectLater(
      find.byType(PhoneShell),
      matchesGoldenFile('goldens/phone-2-grise.png'),
    );
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('4 Appui long sur « Night Swim »', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await pumpKeep(tester, images: true);
    await open(tester);
    await tester.longPress(find.text('Night Swim'));
    await done(tester);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/phone-4.png'),
    );
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('12 Retirer du téléphone : confirmation', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await pumpKeep(tester, images: true);
    await tester.tap(find.text('Lafleur Surf').first);
    await done(tester);
    await tester.tap(find.byIcon(Icons.more_horiz_rounded));
    await done(tester);
    await tester.tap(find.text('Retirer du téléphone'));
    await done(tester);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/phone-12.png'),
    );
    debugDefaultTargetPlatformOverride = null;
  });
}
