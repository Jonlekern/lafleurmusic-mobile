// Pixel comparison: run on macOS only (CI job goldens), see dart_test.yaml.
@Tags(['golden'])
library;

import 'dart:io';

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lafleurmusic/app_scope.dart';
import 'package:lafleurmusic/l10n/strings.dart';
import 'package:lafleurmusic/library/db.dart';
import 'package:lafleurmusic/library/models.dart';
import 'package:lafleurmusic/player/player.dart';
import 'package:lafleurmusic/player/queue.dart';
import 'package:lafleurmusic/theme/lafleur_theme.dart';
import 'package:lafleurmusic/ui/library_screen.dart';

import 'fake_player.dart';
import 'fonts.dart';
import 'morceaux_golden_test.dart' show ReadyCovers;

void main() {
  setUpAll(loadFonts);

  for (final (mode, sfx) in goldenModes) {
    testWidgets(inMode(mode, 'maquette 8a : À suivre avec deux ajouts'), (
      tester,
    ) async {
      desktopSize(tester);
      final dir = Directory.systemTemp.createTempSync('un');
      const names = [
        ('Ocean Drive', 'Johnny'),
        ('Lafleur Surf', 'LAFLEURSTUDIO'),
        ('Golden Hour', 'Divers'),
        ('Night Swim', 'Kavinsky'),
        ('Paradise Club', 'Divers'),
        ('Sunset Tape', 'Divers'),
        ('Palm Waves', 'Johnny'),
        ('Late Bloom', 'Divers'),
        ('Studio 9', 'LAFLEURSTUDIO'),
      ];
      File cover(String n, (int, int, int) c) =>
          File('${dir.path}/$n.jpg')..writeAsBytesSync(
            img.encodeJpg(
              img.Image(width: 300, height: 300)
                ..clear(img.ColorRgb8(c.$1, c.$2, c.$3)),
            ),
          );
      final green = cover('green', (93, 138, 95));
      final blue = cover('blue', (44, 62, 122));
      final tracks = [
        for (final (i, (title, artist)) in names.indexed)
          Track(
            path: '/m/s/${i + 1}.flac',
            folderId: 1,
            title: title,
            artist: artist,
            album: 'Studio Lafleur',
            trackNo: i + 1,
            durationMs: 220000 + i * 7000,
            hasCover: true,
            mtime: 1,
            size: 1,
          ),
      ];
      final nightcall = Track(
        path: '/m/n/1.flac',
        folderId: 1,
        title: 'Nightcall',
        artist: 'Kavinsky',
        album: 'Night Drive',
        trackNo: 1,
        durationMs: 258000,
        hasCover: true,
        mtime: 1,
        size: 1,
      );
      final files = {
        for (final t in tracks) t.path: green,
        nightcall.path: blue,
      };
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
      await tester.runAsync(() => db.upsertTracks([...tracks, nightcall]));
      final player = FakePlayer();
      final q = PlayQueue(tracks, index: 1)..enqueue([nightcall, tracks[5]]);
      player.queue = q;
      player.current = PlayerState(track: tracks[1], playing: true);
      await tester.pumpWidget(
        AppScope(
          db: db,
          player: player,
          covers: ReadyCovers(files),
          strings: Strings.of(const Locale('fr')),
          child: MaterialApp(
            theme: lafleurTheme(mode),
            home: const LibraryScreen(tablet: false),
          ),
        ),
      );
      Future<void> settle() async {
        for (var i = 0; i < 5; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
        }
      }

      await settle();
      await tester.tap(find.text('Studio Lafleur').first);
      await settle();
      final ctx = tester.element(find.byType(Scaffold).first);
      await tester.runAsync(() async {
        for (final f in {green, blue}) {
          await precacheImage(FileImage(f), ctx);
        }
      });
      await precacheAssets(tester, ['assets/fleur-tile.png', ...logos]);
      await tester.pump();
      await expectLater(
        find.byType(LibraryScreen),
        matchesGoldenFile('goldens/8a-a-suivre$sfx.png'),
      );
      dir.deleteSync(recursive: true);
    });
  }
}
