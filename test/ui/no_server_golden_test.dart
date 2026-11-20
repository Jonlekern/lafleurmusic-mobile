// Pixel comparison: run on macOS only (CI job goldens), see dart_test.yaml.
@Tags(['golden'])
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/demo/demo_offline.dart';
import 'package:lafleurmusic/ui/phone/phone_shell.dart';

import 'accounts_fixture.dart';
import 'fonts.dart';

/// Maquette 16, écrans A (premier lancement) et B (Accueil sans musique), 390 × 844, sur un iPhone.
void main() {
  setUpAll(() async {
    await loadFonts();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  Future<void> precacheLogo(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    final ctx = tester.element(find.byType(Scaffold));
    await tester.runAsync(() async {
      for (final logo in logos) {
        await precacheImage(AssetImage(logo), ctx);
      }
    });
  }

  for (final (mode, sfx) in goldenModes) {
    for (final (name, file, localOnly) in [
      ('16 A premier lancement', 'phone-16a', false),
      ('16 B Accueil sans musique', 'phone-16b', true),
    ]) {
      testWidgets(inMode(mode, name), (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        await precacheLogo(tester);
        await pumpAccounts(
          tester,
          brightness: mode,
          seed: const [],
          device: DemoDevice(),
          configure: (s) => s.localOnly = localOnly,
          home: () => const PhoneShell(),
        );
        await expectLater(
          find.byType(PhoneShell),
          matchesGoldenFile('goldens/$file$sfx.png'),
        );
        debugDefaultTargetPlatformOverride = null;
      });
    }
  }
}
