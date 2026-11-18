import 'dart:io';

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lafleurmusic/app_scope.dart';
import 'package:lafleurmusic/l10n/strings.dart';
import 'package:lafleurmusic/library/db.dart';
import 'package:lafleurmusic/library/models.dart';
import 'package:lafleurmusic/theme/lafleur_theme.dart';
import 'package:lafleurmusic/ui/top_screen.dart';

import 'fake_player.dart';
import 'fonts.dart';
import 'morceaux_golden_test.dart' show ReadyCovers;

const rows = [
  ('Lafleur Surf', 'LAFLEURSTUDIO', 'Studio Lafleur', 87, (140, 31, 42)),
  ('Nightcall', 'Kavinsky', 'Night Drive', 64, (44, 62, 122)),
  ('Ocean Drive', 'Johnny', 'Studio Lafleur', 58, (93, 138, 95)),
  ('Aberdeen', 'Cage The Elephant', 'Indie Rock Playlist', 51, (201, 162, 107)),
  ('Golden Hour', 'Divers', 'Studio Lafleur', 44, (93, 138, 95)),
  ('Summer Breeze', 'Zerb', 'Summer Mix', 39, (216, 176, 64)),
  ('Odd Look', 'Kavinsky', 'Night Drive', 33, (44, 62, 122)),
  ('Palm Waves', 'Johnny', 'Studio Lafleur', 27, (93, 138, 95)),
  ('Sunset Tape', 'Divers', 'Studio Lafleur', 21, (93, 138, 95)),
  (
    "Ain't No Rest",
    'Cage The Elephant',
    'Indie Rock Playlist',
    18,
    (201, 162, 107),
  ),
];

late FakePlayer player;

Future<Map<String, File>> pump(
  WidgetTester tester, {
  bool empty = false,
}) async {
  desktopSize(tester);
  final dir = Directory.systemTemp.createTempSync('top');
  addTearDown(() => dir.deleteSync(recursive: true));
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
  final files = <String, File>{};
  await tester.runAsync(() async {
    for (final (i, (title, artist, album, n, c)) in rows.indexed) {
      final path = '/m/$i.flac';
      await db.upsertTrack(
        Track(
          path: path,
          folderId: 1,
          title: title,
          artist: artist,
          album: album,
          durationMs: 200000,
          hasCover: true,
          mtime: 1,
          size: 1,
        ),
      );
      files[path] = File('${dir.path}/$i.jpg')
        ..writeAsBytesSync(
          img.encodeJpg(
            img.Image(width: 120, height: 120)
              ..clear(img.ColorRgb8(c.$1, c.$2, c.$3)),
          ),
        );
      if (empty) continue;
      for (var k = 0; k < n; k++) {
        await db.addPlay(path, DateTime(2026, 1, 1, 0, 0, i));
      }
    }
  });
  player = FakePlayer();
  await tester.pumpWidget(
    AppScope(
      db: db,
      player: player,
      covers: ReadyCovers(files),
      strings: Strings.of(const Locale('fr')),
      child: MaterialApp(
        theme: lafleurTheme(),
        home: const Scaffold(body: TopScreen()),
      ),
    ),
  );
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
  return files;
}

void main() {
  setUpAll(loadFonts);

  testWidgets('classement et nombres d’écoutes', (tester) async {
    await pump(tester);
    expect(find.text('Les plus écoutés'), findsOneWidget);
    expect(find.text('TOP 100'), findsOneWidget);
    expect(
      find.text(
        'Une écoute compte quand tu as écouté la moitié du morceau (ou 4 min).',
      ),
      findsOneWidget,
    );
    expect(find.text('87'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Lafleur Surf')).dy <
          tester.getTopLeft(find.text('Nightcall')).dy,
      isTrue,
    );
  });

  testWidgets('clic → joue la liste à partir de ce morceau', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Nightcall'));
    expect(player.lastIndex, 1);
    expect(player.lastTracks!.first.title, 'Lafleur Surf');
  });

  testWidgets('clic droit → menu du morceau', (tester) async {
    await pump(tester);
    final g = await tester.startGesture(
      tester.getCenter(find.text('Nightcall')),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await g.up();
    await tester.pumpAndSettle();
    expect(find.text('Lire ensuite'), findsOneWidget);
  });

  testWidgets('rien encore', (tester) async {
    await pump(tester, empty: true);
    expect(
      find.text('Rien encore : écoute un peu de musique.'),
      findsOneWidget,
    );
  });

  testWidgets('maquette 9a', (tester) async {
    await pump(tester);
    // laisse les pochettes se décoder (hors horloge simulée)
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    await expectLater(
      find.byType(TopScreen),
      matchesGoldenFile('goldens/9a-top-100.png'),
    );
  });
}
