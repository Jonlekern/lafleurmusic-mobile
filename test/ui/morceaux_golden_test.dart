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
import 'package:lafleurmusic/library/covers.dart';
import 'package:lafleurmusic/library/db.dart';
import 'package:lafleurmusic/library/models.dart';
import 'package:lafleurmusic/theme/lafleur_theme.dart';
import 'package:lafleurmusic/ui/library_screen.dart';

import 'fake_player.dart';
import 'fonts.dart';

/// Pochettes déjà prêtes sur le disque (une couleur par album).
class ReadyCovers extends Covers {
  ReadyCovers(this.files) : super(cacheDir: Directory.systemTemp);
  final Map<String, File> files;
  @override
  Future<File?> get(String trackPath, int size) async => files[trackPath];
}

void main() {
  setUpAll(loadFonts);

  testWidgets('Morceaux : mosaïque de 4 pochettes, étiquette BIBLIOTHÈQUE', (
    tester,
  ) async {
    desktopSize(tester);
    final dir = Directory.systemTemp.createTempSync('mz');
    const albums = [
      ('Studio Lafleur', (110, 30, 34)),
      ('Night Drive', (40, 60, 120)),
      ('Summer Mix', (220, 170, 40)),
      ('Lafleur Surf', (80, 140, 100)),
      ('Roadtrip', (160, 155, 165)),
    ];
    const titles = [
      'A-punk',
      'Aberdeen',
      'Addicted',
      'Afraid To Feel',
      'Afters',
      'Ain’t No Rest',
      'Alive',
      'All Night',
    ];
    final tracks = <Track>[];
    final files = <String, File>{};
    for (var i = 0; i < titles.length; i++) {
      final (album, c) = albums[i % albums.length];
      final path = '/m/$i.flac';
      tracks.add(
        Track(
          path: path,
          folderId: 1,
          title: titles[i],
          artist: 'Artiste ${i + 1}',
          album: album,
          trackNo: i + 1,
          durationMs: 180000,
          hasCover: true,
          mtime: 1,
          size: 1,
        ),
      );
      final f = File('${dir.path}/$i.jpg')
        ..writeAsBytesSync(
          img.encodeJpg(
            img.Image(width: 300, height: 300)
              ..clear(img.ColorRgb8(c.$1, c.$2, c.$3)),
          ),
        );
      files[path] = f;
    }
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
    await tester.runAsync(() => db.upsertTracks(tracks));
    await tester.pumpWidget(
      AppScope(
        db: db,
        player: FakePlayer(),
        covers: ReadyCovers(files),
        strings: Strings.of(const Locale('fr')),
        child: MaterialApp(
          theme: lafleurTheme(),
          home: const LibraryScreen(tablet: false),
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    await tester.tap(find.text('Morceaux').first);
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    final ctx = tester.element(find.byType(Scaffold).first);
    await tester.runAsync(() async {
      for (final f in files.values) {
        await precacheImage(FileImage(f), ctx);
      }
    });
    await precacheAssets(tester, [
      'assets/fleur-tile.png',
      'assets/logo-texte-grand.png',
    ]);
    await expectLater(
      find.byType(LibraryScreen),
      matchesGoldenFile('goldens/2b-morceaux.png'),
    );
    dir.deleteSync(recursive: true);
  });
}
