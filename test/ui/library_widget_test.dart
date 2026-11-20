import 'dart:io';

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/app_scope.dart';
import 'package:lafleurmusic/l10n/strings.dart';
import 'package:lafleurmusic/library/covers.dart';
import 'package:lafleurmusic/library/db.dart';
import 'package:lafleurmusic/library/models.dart';
import 'package:lafleurmusic/player/player.dart';
import 'package:lafleurmusic/theme/colors.dart';
import 'package:lafleurmusic/theme/lafleur_theme.dart';
import 'package:lafleurmusic/ui/library_screen.dart';
import 'package:lafleurmusic/ui/track_list.dart';

import 'fake_player.dart';
import 'fonts.dart';

Track t(
  String title,
  int no, {
  String artist = 'Johnny',
  bool missing = false,
  int min = 4,
}) => Track(
  path: '/m/Studio Lafleur/$no $title.flac',
  folderId: 1,
  title: title,
  artist: artist,
  album: 'Studio Lafleur',
  trackNo: no,
  durationMs: min * 60000,
  hasCover: true,
  mtime: 1,
  size: 1,
  missing: missing,
);

final other = Track(
  path: '/m/Night/1.flac',
  folderId: 1,
  title: 'Nightcall',
  artist: 'Kavinsky',
  album: 'Night Drive',
  trackNo: 1,
  durationMs: 1,
  hasCover: true,
  mtime: 1,
  size: 1,
);

final demo = [
  t('Ocean Drive', 1),
  t('Lafleur Surf', 2, artist: 'LAFLEURSTUDIO'),
  t('Golden Hour', 3, artist: 'Divers'),
  t('Night Swim', 4, artist: 'Kavinsky'),
  t('Paradise Club', 5, artist: 'Divers'),
  t('Sunset Tape', 6, artist: 'LAFLEURSTUDIO'),
  t('Palm Waves', 7),
  t('Late Bloom', 8, artist: 'Divers'),
  t('Studio 9', 9, artist: 'LAFLEURSTUDIO'),
];

Future<(LibraryDb, FakePlayer)> pump(
  WidgetTester tester,
  List<Track> tracks, {
  Brightness mode = Brightness.dark,
}) async {
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
  await tester.runAsync(() => db.upsertTracks(tracks));
  final player = FakePlayer();
  final covers = Covers(
    cacheDir: Directory.systemTemp.createTempSync('c'),
    embedded: (_) async => null,
  );
  await tester.pumpWidget(
    AppScope(
      db: db,
      player: player,
      covers: covers,
      strings: Strings.of(const Locale('fr')),
      child: MaterialApp(
        theme: lafleurTheme(mode),
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
  return (db, player);
}

void main() {
  setUpAll(loadFonts);

  testWidgets('un seul clic : joue la playlist à partir de ce morceau', (
    tester,
  ) async {
    final (_, player) = await pump(tester, demo);
    await tester.tap(find.text('Golden Hour'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(player.lastIndex, 2);
    expect(player.lastTracks!.length, 9);
    expect(player.lastTracks![player.lastIndex!].title, 'Golden Hour');
  });

  testWidgets('Aléatoire : lance en aléatoire en une fois', (tester) async {
    final (_, player) = await pump(tester, demo);
    await tester.tap(find.text('Aléatoire'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(player.calls, ['play']);
    expect(player.lastShuffle, isTrue);
  });

  testWidgets(
    'après une recherche, un clic sur un morceau rend l’espace au lecteur',
    (tester) async {
      final (_, player) = await pump(tester, demo);
      await tester.tap(find.byKey(const Key('search')));
      await tester.enterText(find.byKey(const Key('search')), 'surf');
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      await tester.tap(find.text('Lafleur Surf').last);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(player.calls, ['play', 'toggle']);
    },
  );

  testWidgets(
    'espace : lecture / pause ; flèches : morceau suivant / précédent',
    (tester) async {
      final (_, player) = await pump(tester, demo);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      expect(player.calls, ['toggle', 'next', 'previous']);
    },
  );

  testWidgets('Cmd+F : recherche, puis la saisie ne pilote plus le lecteur', (
    tester,
  ) async {
    final (_, player) = await pump(tester, demo);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(player.calls, isEmpty);
  });

  testWidgets('morceau absent (NAS débranché) : grisé et non jouable', (
    tester,
  ) async {
    final (_, player) = await pump(tester, [
      t('Ocean Drive', 1, missing: true),
      t('Palm Waves', 2),
    ]);
    await tester.tap(find.text('Ocean Drive'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(player.calls, isEmpty);
    expect(find.textContaining('NAS introuvable'), findsOneWidget);
  });

  for (final (mode, sfx) in goldenModes) {
    testWidgets(inMode(mode, 'vue en colonnes comme la maquette 2'), (
      tester,
    ) async {
      final (_, player) = await pump(tester, demo, mode: mode);
      player.queue = null;
      await player.playTracks(demo, 1);
      player.show(
        PlayerState(
          track: demo[1],
          position: const Duration(seconds: 93),
          duration: const Duration(seconds: 245),
          playing: true,
        ),
      );
      await tester.pump();
      await precacheAssets(tester, ['assets/fleur-tile.png', ...logos]);
      await expectLater(
        find.byType(LibraryScreen),
        matchesGoldenFile('goldens/2-colonnes$sfx.png'),
      );
    }, tags: ['golden']);
  }
  testWidgets(
    'clair : ▶︎ du lecteur se voit (icône claire sur le rond foncé)',
    (tester) async {
      await pump(tester, demo, mode: Brightness.light);
      final round = tester.widget<Container>(
        find.descendant(
          of: find.byKey(const Key('playpause')),
          matching: find.byType(Container),
        ),
      );
      final icon = tester.widget<Icon>(
        find.descendant(
          of: find.byKey(const Key('playpause')),
          matching: find.byType(Icon),
        ),
      );
      expect(
        (round.decoration! as BoxDecoration).color,
        LafleurColors.light.text,
      );
      expect(icon.color, LafleurColors.light.bg);
    },
  );

  testWidgets('Artistes : liste des noms, puis leurs morceaux', (tester) async {
    await pump(tester, demo);
    await tester.tap(find.text('Artistes'));
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(find.text('Kavinsky'), findsOneWidget);
    await tester.tap(find.text('Kavinsky'));
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(find.text('Night Swim'), findsOneWidget);
    expect(find.text('Ocean Drive'), findsNothing);
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
  }

  testWidgets('un simple clic joue toujours, sans attendre', (tester) async {
    final (_, player) = await pump(tester, demo);
    await tester.tap(find.text('Night Swim'));
    await tester.pump();
    expect(player.calls, ['play']);
  });

  Finder inList(String text) =>
      find.descendant(of: find.byType(TrackList), matching: find.text(text));

  testWidgets('Morceaux : étiquette BIBLIOTHÈQUE, pas ALBUM', (tester) async {
    await pump(tester, [...demo, other]);
    await tester.tap(find.text('Morceaux').first);
    await settle(tester);
    expect(inList('BIBLIOTHÈQUE'), findsOneWidget);
    expect(inList('ALBUM'), findsNothing);
  });

  testWidgets('un album : étiquette ALBUM', (tester) async {
    await pump(tester, demo);
    expect(inList('ALBUM'), findsOneWidget);
  });
}
