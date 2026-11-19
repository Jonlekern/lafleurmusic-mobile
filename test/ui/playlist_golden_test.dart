// Pixel comparison: run on macOS only (CI job goldens), see dart_test.yaml.
@Tags(['golden'])
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/ui/phone/phone_shell.dart';

import 'fonts.dart';
import 'phone/playlist_screen_test.dart' show openSoiree, pumpPlaylists;
import 'phone_fixture.dart';

/// Maquette 7 (playlists du serveur), 390 × 844 sur un iPhone, données de la démo : écran 10 (Accueil,
/// sous les albums) et écran 11 (« Soirée »).
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

  testWidgets('10 Accueil : playlists du serveur', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await pumpPlaylists(tester, images: true);
    await done(tester);
    await tester.scrollUntilVisible(
      find.text('Chill du dimanche'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await done(tester);
    await expectLater(
      find.byType(PhoneShell),
      matchesGoldenFile('goldens/phone-10.png'),
    );
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('11 Une playlist du serveur', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await pumpPlaylists(tester, images: true);
    await done(tester);
    await openSoiree(tester);
    await expectLater(
      find.byType(PhoneShell),
      matchesGoldenFile('goldens/phone-11.png'),
    );
    debugDefaultTargetPlatformOverride = null;
  });
}
