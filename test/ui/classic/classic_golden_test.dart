// Pixel comparison: run on macOS only (CI job goldens), see dart_test.yaml.
@Tags(['golden'])
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/demo/demo_offline.dart';
import 'package:lafleurmusic/ui/classic/classic_shell.dart';
import 'package:lafleurmusic/ui/classic/click_wheel.dart';
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
}
