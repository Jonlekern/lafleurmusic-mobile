// Pixel comparison: run on macOS only (CI job goldens), see dart_test.yaml.
@Tags(['golden'])
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/demo/demo_offline.dart';
import 'package:lafleurmusic/ui/classic/classic_now.dart';
import 'package:lafleurmusic/ui/classic/classic_shell.dart';
import 'package:lafleurmusic/ui/classic/click_wheel.dart';
import 'package:lafleurmusic/ui/phone/accounts_screen.dart';
import 'package:lafleurmusic/ui/phone/phone_shell.dart';

import '../fonts.dart';
import '../phone_fixture.dart';

/// Maquette 6 A : le Mode Classic à 390 × 844, sur un iPhone (« Sur mon iPhone »).
void main() {
  setUpAll(loadFonts);

  Future<void> start(WidgetTester tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    // comme sur le téléphone : « Sur mon iPhone » s'ouvre (un téléchargeur)
    await pumpPhone(
      tester,
      images: true,
      home: const ClassicShell(),
      downloader: DemoDownloader(),
    );
  }

  Future<void> rotate(WidgetTester tester, int n) async {
    for (var i = 0; i < n; i++) {
      tester.widget<ClickWheel>(find.byType(ClickWheel)).onRotate(1);
    }
    await tester.pump();
  }

  Future<void> shot(String name) => expectLater(
    find.byType(PhoneShell),
    matchesGoldenFile('goldens/$name.png'),
  );

  testWidgets('6 A : le menu, Albums choisi', (tester) async {
    await start(tester);
    await rotate(tester, 2);
    await shot('6a-classic-menu');
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('6 A : Morceaux, la liste défilée jusqu\'à la ligne choisie', (
    tester,
  ) async {
    await start(tester);
    await tester.tap(find.text('Morceaux'));
    await settle(tester);
    await rotate(tester, 9);
    await shot('6a-classic-morceaux');
    debugDefaultTargetPlatformOverride = null;
  });

  // Maquette 12 : En cours en Mode Classic et le choix du mode
  Future<void> openNow(WidgetTester tester) async {
    await start(tester);
    for (var i = 0; i < 7; i++) {
      tester.widget<ClickWheel>(find.byType(ClickWheel)).onRotate(1);
    }
    await tester.pump();
    final c = tester.getCenter(find.byType(ClickWheel));
    await tester.tapAt(c);
    await settle(tester);
    await tester.pumpAndSettle();
    expect(find.byType(ClassicNow), findsOneWidget);
  }

  testWidgets('12 A : En cours, tourner = volume', (tester) async {
    await openNow(tester);
    await shot('12a-classic-now');
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('12 B : après un appui au milieu, avancer', (tester) async {
    await openNow(tester);
    await tester.tapAt(tester.getCenter(find.byType(ClickWheel)));
    await tester.pump();
    await shot('12b-classic-scrub');
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('12 C : Réglages › AFFICHAGE, Mode Classic choisi', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await pumpPhone(
      tester,
      images: true,
      home: const AccountsScreen(),
      classicMode: ValueNotifier(true),
    );
    await expectLater(
      find.byType(AccountsScreen),
      matchesGoldenFile('goldens/12c-classic-setting.png'),
    );
    debugDefaultTargetPlatformOverride = null;
  });
}
