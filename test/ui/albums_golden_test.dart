// Pixel comparison: run on macOS only (CI job goldens), see dart_test.yaml.
@Tags(['golden'])
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/demo/demo_library.dart';
import 'package:lafleurmusic/ui/phone/albums_screen.dart';

import 'fonts.dart';
import 'phone_fixture.dart';

/// Maquette 13 (file et bibliothèque), écran B : « Écoutés récemment », puis les albums triés.
void main() {
  setUpAll(() async {
    await loadFonts();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  testWidgets('B Albums : écoutés récemment et tri « Ajout récent »', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    final f = await pumpPhone(tester, images: true, home: const AlbumsScreen());
    final plays = [
      DemoLibrary.studio.first.path,
      DemoLibrary.surf.first.path,
      DemoLibrary.summer.first.path,
    ];
    for (final (i, p) in plays.indexed) {
      await tester.runAsync(() => f.db.addPlay(p, DateTime(2026, 1, 1 + i)));
    }
    await settle(tester);
    await tester.tap(find.byKey(const Key('sort-recent')));
    await settle(tester);
    await expectLater(
      find.byType(AlbumsScreen),
      matchesGoldenFile('goldens/albums-b-tri-recents.png'),
    );
    debugDefaultTargetPlatformOverride = null;
  });
}
