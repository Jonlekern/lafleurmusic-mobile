// Pixel comparison: run on macOS only (CI job goldens), see dart_test.yaml.
@Tags(['golden'])
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/demo/demo_library.dart';
import 'package:lafleurmusic/library/playlist_store.dart';
import 'package:lafleurmusic/ui/phone/playlist_edit_screen.dart';
import 'package:lafleurmusic/ui/phone/playlist_screen.dart';

import 'fonts.dart';
import 'phone_fixture.dart';

/// Maquette 15, écrans D (la playlist : Ajouter · Modifier · Trier) et E (Modifier), sur une
/// playlist du téléphone, sans compte.
void main() {
  setUpAll(() async {
    await loadFonts();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  for (final (mode, sfx) in goldenModes) {
    Future<void> openRoadTrip(WidgetTester tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      ServerPlaylist? target;
      late PlaylistStore store;
      final f = await pumpPhone(
        tester,
        brightness: mode,
        images: true,
        withAccounts: false,
        home: Builder(
          builder: (ctx) => Scaffold(
            body: TextButton(
              onPressed: () => openPlaylist(ctx, target!),
              child: const Text('go'),
            ),
          ),
        ),
        playlists: (db) => store = PlaylistStore(db),
      );
      await tester.runAsync(() async {
        final ref = await store.create(
          'Road Trip',
          songs: [for (final t in DemoLibrary.studio.take(6)) t.path],
        );
        target = (await f.db.watchPlaylists().first).firstWhere(
          (p) => p.ref == ref,
        );
      });
      await tester.tap(find.text('go'));
      await settle(tester);
      await tester.pumpAndSettle();
      await settle(tester);
      await tester.pumpAndSettle();
    }

    testWidgets(inMode(mode, 'D la playlist : Ajouter · Modifier · Trier'), (
      tester,
    ) async {
      await openRoadTrip(tester);
      await expectLater(
        find.byType(PlaylistScreen),
        matchesGoldenFile('goldens/playlist-d-playlist$sfx.png'),
      );
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets(inMode(mode, 'E Modifier'), (tester) async {
      await openRoadTrip(tester);
      await tester.tap(find.byKey(const Key('plEdit')));
      await settle(tester);
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(PlaylistEditScreen),
        matchesGoldenFile('goldens/playlist-e-modifier$sfx.png'),
      );
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
