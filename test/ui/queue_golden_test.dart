// Pixel comparison: run on macOS only (CI job goldens), see dart_test.yaml.
@Tags(['golden'])
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Overlay;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/demo/demo_library.dart';
import 'package:lafleurmusic/ui/phone/album_screen.dart';
import 'package:lafleurmusic/ui/phone/mini_player.dart';
import 'package:lafleurmusic/ui/phone/phone_shell.dart';
import 'package:lafleurmusic/ui/queue_toast.dart';

import 'fonts.dart';
import 'phone_fixture.dart';

/// Maquette 13 (file et bibliothèque), écran A : glisser à droite = Ajouter à la file, et la bulle.
void main() {
  setUpAll(() async {
    await loadFonts();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  testWidgets('A Album : bandeau « Ajouter à la file » et la bulle', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await pumpPhone(tester, images: true);
    await tester.tap(find.text('Studio Lafleur'));
    await tester.pumpAndSettle();
    await settle(tester);
    final g = await tester.startGesture(
      tester.getCenter(find.text('Night Swim')),
    );
    for (var i = 0; i < 8; i++) {
      await g.moveBy(const Offset(25, 0));
      await tester.pump();
    }
    // la bulle de l'ajout précédent, comme sur la maquette (le doigt est encore posé)
    showQueueToast(
      tester.element(find.byType(AlbumScreen)),
      count: 1,
      onUndo: () {},
      onShowQueue: () {},
    );
    await tester.pump();
    await expectLater(
      find.byType(PhoneShell),
      matchesGoldenFile('goldens/queue-a-glisser-droite.png'),
    );
    await g.cancel();
    await tester.pumpAndSettle(const Duration(seconds: 5));
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('C À suivre : « Vider » et la fenêtre « Vider tes ajouts ? »', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final f = await pumpPhone(tester, images: true);
    // la maquette : deux ajouts
    f.player.queue!.enqueue([DemoLibrary.tracks.first]);
    await tester.tap(find.byType(MiniPlayer));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vider'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(Overlay).first,
      matchesGoldenFile('goldens/queue-c-vider.png'),
    );
    debugDefaultTargetPlatformOverride = null;
  });
}
