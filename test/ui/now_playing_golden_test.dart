// Pixel comparison: run on macOS only (CI job goldens), see dart_test.yaml.
@Tags(['golden'])
library;

import 'dart:io';

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/app_scope.dart';
import 'package:lafleurmusic/l10n/strings.dart';
import 'package:lafleurmusic/library/covers.dart';
import 'package:lafleurmusic/library/db.dart';
import 'package:lafleurmusic/library/models.dart';
import 'package:lafleurmusic/player/equalizer.dart';
import 'package:lafleurmusic/player/player.dart';
import 'package:lafleurmusic/theme/lafleur_theme.dart';
import 'package:lafleurmusic/ui/now_playing_screen.dart';

import 'fake_player.dart';
import 'fonts.dart';

void main() {
  setUpAll(loadFonts);

  for (final (mode, sfx) in goldenModes) {
    testWidgets(inMode(mode, 'En cours + égaliseur comme la maquette 4'), (
      tester,
    ) async {
      desktopSize(tester);
      final db = LibraryDb(
        DatabaseConnection(
          NativeDatabase.memory(),
          closeStreamsSynchronously: true,
        ),
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(db.close);
      });
      final tracks = [
        for (var i = 1; i <= 9; i++)
          Track(
            path: '/m/$i.flac',
            folderId: 1,
            title: i == 2 ? 'Lafleur Surf' : 'T$i',
            artist: 'LAFLEURSTUDIO',
            album: 'Studio Lafleur',
            trackNo: i,
            durationMs: 245000,
            hasCover: true,
            mtime: 1,
            size: 1,
          ),
      ];
      final player = FakePlayer();
      await player.playTracks(tracks, 1);
      player.current = PlayerState(
        track: tracks[1],
        position: const Duration(seconds: 93),
        duration: const Duration(seconds: 245),
        playing: true,
      );
      final eq = ValueNotifier(Equalizer.named('bass').copyWith(enabled: true));
      await tester.pumpWidget(
        AppScope(
          db: db,
          player: player,
          equalizer: eq,
          covers: Covers(
            cacheDir: Directory.systemTemp.createTempSync('np'),
            embedded: (_) async => null,
          ),
          strings: Strings.of(const Locale('fr')),
          child: MaterialApp(
            theme: lafleurTheme(mode),
            home: const NowPlayingScreen(),
          ),
        ),
      );
      await tester.pump();
      await precacheAssets(tester, ['assets/fleur-tile.png', ...logos]);
      expect(find.text('2 sur 9 · Studio Lafleur'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(NowPlayingScreen),
        matchesGoldenFile('goldens/4-en-cours-egaliseur$sfx.png'),
      );
    });
  }
}
