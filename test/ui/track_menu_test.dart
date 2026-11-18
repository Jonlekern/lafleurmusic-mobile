import 'dart:io';

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/app_scope.dart';
import 'package:lafleurmusic/l10n/strings.dart';
import 'package:lafleurmusic/library/covers.dart';
import 'package:lafleurmusic/library/db.dart';
import 'package:lafleurmusic/library/models.dart';
import 'package:lafleurmusic/theme/lafleur_theme.dart';
import 'package:lafleurmusic/ui/track_list.dart';
import 'package:lafleurmusic/ui/track_menu.dart';

import 'fake_player.dart';
import 'fonts.dart';

Track t(String title, int no) => Track(
  path: '/m/Studio Lafleur/$no $title.flac',
  folderId: 1,
  title: title,
  artist: 'Divers',
  album: 'Studio Lafleur',
  trackNo: no,
  durationMs: 240000,
  hasCover: true,
  mtime: 1,
  size: 1,
);

final album = [
  for (final (i, n) in [
    'Ocean Drive',
    'Lafleur Surf',
    'Golden Hour',
    'Night Swim',
    'Paradise Club',
    'Sunset Tape',
    'Palm Waves',
    'Late Bloom',
    'Studio 9',
  ].indexed)
    t(n, i + 1),
];

late FakePlayer player;

Future<void> pump(WidgetTester tester) async {
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
  await tester.runAsync(() => db.upsertTracks(album));
  player = FakePlayer();
  await tester.pumpWidget(
    AppScope(
      db: db,
      player: player,
      covers: Covers(
        cacheDir: Directory.systemTemp.createTempSync('c'),
        embedded: (_) async => null,
      ),
      strings: Strings.of(const Locale('fr')),
      child: MaterialApp(
        theme: lafleurTheme(),
        home: Scaffold(
          body: TrackList(
            title: 'Studio Lafleur',
            tracks: album,
            isAlbum: true,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> rightClick(WidgetTester tester, String text) async {
  final g = await tester.startGesture(
    tester.getCenter(find.text(text)),
    kind: PointerDeviceKind.mouse,
    buttons: kSecondaryMouseButton,
  );
  await g.up();
  await tester.pumpAndSettle();
}

/// Laisse passer les requêtes de la base (hors horloge simulée), puis redessine.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets(
    'clic droit : Lire ensuite et Ajouter à la file, Lire ensuite → playNext',
    (tester) async {
      await pump(tester);
      await rightClick(tester, 'Sunset Tape');
      expect(find.text('Lire ensuite'), findsOneWidget);
      expect(find.text('Ajouter à la file'), findsOneWidget);
      expect(find.text('Supprimer le morceau…'), findsNothing);
      expect(find.text('Remplacer par…'), findsNothing);
      await tester.tap(find.text('Lire ensuite'));
      await tester.pumpAndSettle();
      expect(player.calls, ['playNext']);
      expect(player.lastAdded!.single.title, 'Sunset Tape');
    },
  );

  testWidgets('Ajouter à la file → enqueue', (tester) async {
    await pump(tester);
    await rightClick(tester, 'Sunset Tape');
    await tester.tap(find.text('Ajouter à la file'));
    await tester.pumpAndSettle();
    expect(player.calls, ['enqueue']);
  });

  testWidgets('clic droit sur un album : tous ses morceaux à la file', (
    tester,
  ) async {
    await pump(tester);
    final ctx = tester.element(find.text('Ocean Drive'));
    final done = showTracksMenu(ctx, const Offset(300, 300), () async => album);
    await tester.pumpAndSettle();
    expect(find.text('Supprimer le morceau…'), findsNothing);
    await tester.tap(find.text('Ajouter à la file'));
    await tester.pumpAndSettle();
    await done;
    expect(player.calls, ['enqueue']);
    expect(player.lastAdded!.length, 9);
  });
}
