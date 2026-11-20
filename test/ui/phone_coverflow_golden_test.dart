// Pixel comparison: run on macOS only (CI job goldens), see dart_test.yaml.
@Tags(['golden'])
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/library/models.dart';
import 'package:lafleurmusic/ui/coverflow_screen.dart';

import 'package:lafleurmusic/demo/demo_library.dart';
import 'package:lafleurmusic/demo/demo_offline.dart';

import 'fonts.dart';
import 'keep_fixture.dart';
import 'phone_fixture.dart';

Track _album(String name) => Track(
  path: 'subsonic://demo/$name/1',
  folderId: 0,
  accountId: 'demo',
  remoteId: '$name/1',
  title: name,
  artist: 'Demo',
  album: name,
  trackNo: 1,
  durationMs: 200000,
  hasCover: false,
  mtime: 1,
  size: 1,
);

/// Maquette 2, écran 5 : téléphone couché = Cover Flow, 844 × 390, sur un iPhone.
void main() {
  setUpAll(() async {
    await loadFonts();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  for (final (mode, sfx) in goldenModes) {
    testWidgets(inMode(mode, '5 Téléphone couché = Cover Flow'), (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await pumpKeep(
        tester,
        brightness: mode,
        images: true,
        extra: [
          for (final n in ['Palm', 'Tools']) _album(n),
        ],
        seed: (db) async {
          await seedKeepDemo(db);
          // Studio Lafleur est gardé en entier (maquette : « ⬇ sur l'iPhone »)
          await seedKept(db, [
            for (final t in DemoLibrary.remote)
              if (t.album == 'Studio Lafleur') t.path,
          ], 400000000);
        },
      );
      landscapeSize(tester);
      await tester.pump();
      await settle(tester);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(CoverflowScreen), findsOneWidget);
      await expectLater(
        find.byType(CoverflowScreen),
        matchesGoldenFile('goldens/phone-5-coverflow$sfx.png'),
      );
      await tester.pumpWidget(const SizedBox());
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
