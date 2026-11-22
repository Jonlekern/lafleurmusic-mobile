// Pixel comparison: run on macOS only (CI job goldens), see dart_test.yaml.
@Tags(['golden'])
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/ui/phone/mini_player.dart';
import 'package:lafleurmusic/ui/phone/phone_shell.dart';

import 'fonts.dart';
import 'phone_fixture.dart';

/// Maquette 1 (téléphone debout), écrans 1, 2, 3 à 390 × 844, sur un iPhone (« Sur mon iPhone ») ;
/// les mêmes en mode clair (maquette 5, suffixe -light).
void main() {
  setUpAll(() async {
    await loadFonts();
    // icônes (▶, ⏸, ⏭, ›…) : la police Material, comme sur le téléphone
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  Future<void> start(
    WidgetTester tester, [
    Brightness brightness = Brightness.dark,
  ]) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await pumpPhone(tester, images: true, brightness: brightness);
  }

  Future<void> shot(String name) => expectLater(
    find.byType(PhoneShell),
    matchesGoldenFile('goldens/$name.png'),
  );

  testWidgets('1 Accueil', (tester) async {
    await start(tester);
    await shot('phone-1');
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('2 Album, « Night Swim » glissé vers la gauche', (tester) async {
    await start(tester);
    await tester.tap(find.text('Studio Lafleur'));
    await tester.pumpAndSettle();
    await settle(tester);
    final g = await tester.startGesture(
      tester.getCenter(find.text('Night Swim')),
    );
    for (var i = 0; i < 7; i++) {
      await g.moveBy(const Offset(-20, 0));
      await tester.pump();
    }
    await shot('phone-2');
    await g.up();
    await tester.pumpAndSettle();
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('3 En cours, onglet À suivre', (tester) async {
    await start(tester);
    await tester.tap(find.text('Lafleur Surf').last); // mini-lecteur
    await tester.pumpAndSettle();
    await settle(tester);
    await shot('phone-3');
    debugDefaultTargetPlatformOverride = null;
  });

  /// Maquette 20 C : sur l'album, le doigt glisse le fil du mini-lecteur jusqu'à 2:29.
  Future<void> seekShot(WidgetTester tester, String name) async {
    await tester.tap(find.text('Studio Lafleur'));
    await tester.pumpAndSettle();
    await settle(tester);
    final mini = tester.getRect(find.byType(MiniPlayer));
    final y = mini.top + MiniPlayer.lineHeight / 2;
    // 2:29 sur 4:05
    final x = mini.left + mini.width * (149.5 / 245);
    final g = await tester.startGesture(Offset(mini.left + 40, y));
    await g.moveBy(const Offset(30, 0));
    await tester.pump();
    await g.moveTo(Offset(x, y));
    await tester.pump();
    expect(find.text('2:29'), findsOneWidget);
    await shot(name);
    await g.up();
    await tester.pumpAndSettle();
  }

  testWidgets('20 C mini-lecteur, glisser le fil', (tester) async {
    await start(tester);
    await seekShot(tester, 'phone-20c');
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('clair : 20 C mini-lecteur, glisser le fil', (tester) async {
    await start(tester, Brightness.light);
    await seekShot(tester, 'phone-20c-light');
    debugDefaultTargetPlatformOverride = null;
  });

  // mode clair (maquette 5)
  testWidgets('clair : 1 Accueil', (tester) async {
    await start(tester, Brightness.light);
    await shot('phone-1-light');
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('clair : 2 Album, « Night Swim » glissé vers la gauche', (
    tester,
  ) async {
    await start(tester, Brightness.light);
    await tester.tap(find.text('Studio Lafleur'));
    await tester.pumpAndSettle();
    await settle(tester);
    final g = await tester.startGesture(
      tester.getCenter(find.text('Night Swim')),
    );
    for (var i = 0; i < 7; i++) {
      await g.moveBy(const Offset(-20, 0));
      await tester.pump();
    }
    await shot('phone-2-light');
    await g.up();
    await tester.pumpAndSettle();
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('clair : 3 En cours, onglet À suivre', (tester) async {
    await start(tester, Brightness.light);
    await tester.tap(find.text('Lafleur Surf').last); // mini-lecteur
    await tester.pumpAndSettle();
    await settle(tester);
    await shot('phone-3-light');
    debugDefaultTargetPlatformOverride = null;
  });
}
