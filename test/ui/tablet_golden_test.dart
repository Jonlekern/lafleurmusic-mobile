// Pixel comparison: run on macOS only (CI job goldens), see dart_test.yaml.
@Tags(['golden'])
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/ui/library_screen.dart';
import 'package:lafleurmusic/ui/phone/phone_shell.dart';

import 'fonts.dart';
import 'phone/keep_screen_test.dart' show done;
import 'phone/playlist_screen_test.dart' show pumpPlaylists;

/// Tablette (plan 3, tâche 7) : les colonnes du Mac sur un iPad, données de la démo (serveur, deux comptes,
/// une playlist gardée) : debout 768 × 1024 et couché 1024 × 768.
void main() {
  setUpAll(() async {
    await loadFonts();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  for (final (mode, sfx) in goldenModes) {
    Future<void> shot(WidgetTester tester, Size size, String name) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        await pumpPlaylists(
          tester,
          brightness: mode,
          images: true,
          home: const AdaptiveHome(),
        );
        tester.view.physicalSize = size;
        tester.view.padding = FakeViewPadding.zero;
        tester.view.viewPadding = FakeViewPadding.zero;
        await tester.pump();
        await done(tester);
        await expectLater(
          find.byType(LibraryScreen),
          matchesGoldenFile('goldens/$name$sfx.png'),
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    }

    testWidgets(inMode(mode, 'iPad debout'), (tester) async {
      await shot(tester, const Size(768, 1024), 'tablet-debout');
    });

    testWidgets(inMode(mode, 'iPad couché'), (tester) async {
      await shot(tester, const Size(1024, 768), 'tablet-couche');
    });
  }
}
