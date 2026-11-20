// Pixel comparison: run on macOS only (CI job goldens), see dart_test.yaml.
@Tags(['golden'])
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/demo/demo_library.dart';
import 'package:lafleurmusic/library/db.dart';
import 'package:lafleurmusic/library/playlist_store.dart';
import 'package:lafleurmusic/sources/subsonic.dart';
import 'package:lafleurmusic/ui/phone/add_to_playlist_sheet.dart';
import 'package:lafleurmusic/ui/phone/now_screen.dart';

import '../sources/fake_playlist_servers.dart';
import 'fonts.dart';
import 'phone_fixture.dart';

/// Maquette 15, écrans A (« + » dans le lecteur), B (cocher plusieurs playlists), C (donner un nom).
void main() {
  setUpAll(() async {
    await loadFonts();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  Future<void> seed(LibraryDb db, dynamic accounts) async {
    final list = await accounts.watch().first as List;
    final nav = list.first.id as String;
    final tracks = DemoLibrary.studio;
    await db.replacePlaylists(nav, [
      (id: 'p1', name: 'Road Trip', paths: [for (final t in tracks) t.path]),
      (
        id: 'p2',
        name: 'Été 2026',
        paths: [for (final t in tracks.take(3)) t.path],
      ),
      (
        id: 'p3',
        name: 'Calme',
        paths: [for (final t in tracks.take(6)) t.path],
      ),
    ]);
  }

  PlaylistStore make(LibraryDb db) => PlaylistStore(
    db,
    sourceOf: (id) async => SubsonicSource(
      accountId: id,
      base: Uri.parse('https://music.example.com'),
      user: 'u',
      password: 'p',
      client: FakeNavidrome().client(),
      salt: () => 'abc',
    ),
  );

  for (final (mode, sfx) in goldenModes) {
    testWidgets(inMode(mode, 'A « + » à côté du titre'), (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await pumpPhone(
        tester,
        brightness: mode,
        images: true,
        home: const NowScreen(),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(NowScreen),
        matchesGoldenFile('goldens/playlist-a-plus$sfx.png'),
      );
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets(inMode(mode, 'B cocher plusieurs playlists'), (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      late PlaylistStore store;
      await pumpPhone(
        tester,
        brightness: mode,
        images: true,
        home: Builder(
          builder: (ctx) => Scaffold(
            body: TextButton(
              onPressed: () => showAddToPlaylist(ctx, [DemoLibrary.playing]),
              child: const Text('go'),
            ),
          ),
        ),
        playlists: (db) => store = make(db),
        seed: seed,
      );
      await tester.runAsync(() async {
        final sport = await store.create('Sport');
        await store.add(sport, [for (final t in DemoLibrary.studio) t.path]);
      });
      await tester.tap(find.text('go'));
      await settle(tester);
      await tester.pumpAndSettle();
      await settle(tester);
      await tester.tap(find.text('Road Trip'));
      await tester.tap(find.text('Été 2026'));
      await tester.pump();
      await expectLater(
        find.byType(AddToPlaylistScreen),
        matchesGoldenFile('goldens/playlist-b-cocher$sfx.png'),
      );
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets(inMode(mode, 'C donner un nom'), (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await pumpPhone(
        tester,
        brightness: mode,
        images: true,
        home: Builder(
          builder: (ctx) => Scaffold(
            body: TextButton(
              onPressed: () => showAddToPlaylist(ctx, [DemoLibrary.playing]),
              child: const Text('go'),
            ),
          ),
        ),
        playlists: make,
        seed: seed,
      );
      await tester.tap(find.text('go'));
      await settle(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('addNew')));
      await tester.pumpAndSettle();
      await settle(tester);
      await tester.enterText(
        find.byKey(const Key('newPlaylistName')),
        'Soirée',
      );
      await tester.pump();
      await expectLater(
        find.byType(Navigator).first,
        matchesGoldenFile('goldens/playlist-c-nom$sfx.png'),
      );
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
