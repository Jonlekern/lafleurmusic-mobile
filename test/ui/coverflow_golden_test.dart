import 'dart:io';

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lafleurmusic/app_scope.dart';
import 'package:lafleurmusic/l10n/strings.dart';
import 'package:lafleurmusic/library/covers.dart';
import 'package:lafleurmusic/library/db.dart';
import 'package:lafleurmusic/library/models.dart';
import 'package:lafleurmusic/theme/lafleur_theme.dart';
import 'package:lafleurmusic/ui/cover_image.dart';
import 'package:lafleurmusic/ui/coverflow_screen.dart';

import 'fake_player.dart';
import 'fonts.dart';

const colors = [
  (244, 239, 230),
  (18, 18, 18),
  (12, 12, 12),
  (110, 30, 34),
  (160, 155, 165),
  (30, 30, 30),
  (80, 140, 100),
];
final names = [
  'Roadtrip',
  'Summer Mix',
  'Lafleur Surf',
  'Studio Lafleur',
  'Night Drive',
  'Tools',
  'Palm',
];

Future<FakePlayer> pump(WidgetTester tester, {int count = 7}) async {
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
  final albums = [
    for (var i = 0; i < count; i++)
      Album(
        name: names[i % 7],
        trackCount: 9,
        durationMs: 1,
        coverTrackPath: '/m/$i.flac',
      ),
  ];
  await tester.runAsync(
    () => db.upsertTracks([
      Track(
        path: '/m/3.flac',
        folderId: 1,
        title: 'Ocean Drive',
        artist: 'J',
        album: 'Studio Lafleur',
        durationMs: 1,
        hasCover: true,
        mtime: 1,
        size: 1,
      ),
    ]),
  );
  final covers = Covers(
    cacheDir: Directory.systemTemp.createTempSync('cf'),
    embedded: (p) async {
      final i = int.parse(p.split('/').last.split('.').first) % 7;
      final c = colors[i];
      return Uint8List.fromList(
        img.encodePng(
          img.Image(width: 300, height: 300)
            ..clear(img.ColorRgb8(c.$1, c.$2, c.$3)),
        ),
      );
    },
  );
  final player = FakePlayer();
  await tester.pumpWidget(
    AppScope(
      db: db,
      player: player,
      covers: covers,
      strings: Strings.of(const Locale('fr')),
      child: MaterialApp(
        theme: lafleurTheme(),
        home: CoverflowScreen(albums: albums, initial: count > 3 ? 3 : 0),
      ),
    ),
  );
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    await tester.pump();
  }
  return player;
}

void main() {
  setUpAll(loadFonts);

  testWidgets('Cover Flow comme la maquette 3', (tester) async {
    await pump(tester);
    await precacheAssets(tester, ['assets/logo-texte-grand.png']);
    expect(find.text('Studio Lafleur'), findsOneWidget);
    await expectLater(
      find.byType(CoverflowScreen),
      matchesGoldenFile('goldens/3-coverflow.png'),
    );
  }, tags: ['golden']);

  testWidgets('flèche droite : album suivant', (tester) async {
    await pump(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Night Drive'), findsOneWidget);
  });

  testWidgets('Entrée : joue l’album du centre', (tester) async {
    final player = await pump(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(player.lastTracks?.single.title, 'Ocean Drive');
  });

  testWidgets('un seul album : pas de plantage', (tester) async {
    await pump(tester, count: 1);
    expect(tester.takeException(), isNull);
    expect(find.text('Roadtrip'), findsOneWidget);
  });

  Future<void> wheel(WidgetTester tester, List<double> deltas) async {
    final center = tester.getCenter(find.byType(CoverflowScreen));
    for (final d in deltas) {
      tester.binding.handlePointerEvent(
        PointerScrollEvent(position: center, scrollDelta: Offset(0, d)),
      );
      await tester.pump(const Duration(milliseconds: 30));
    }
  }

  testWidgets('un cran de molette : album suivant, tout de suite', (
    tester,
  ) async {
    await pump(tester);
    await wheel(tester, [40]);
    await tester.pump(
      const Duration(milliseconds: 300),
    ); // fin de l'animation, sans attendre l'arrêt de la molette
    expect(find.text('Night Drive'), findsOneWidget);
  });

  testWidgets('trois crans rapides : trois albums plus loin', (tester) async {
    await pump(tester);
    await wheel(tester, [40, 40, 40]);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Palm'), findsOneWidget);
  });

  testWidgets('molette vers le haut : album précédent', (tester) async {
    await pump(tester);
    await wheel(tester, [-40]);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Lafleur Surf'), findsOneWidget);
  });

  testWidgets('frôler la molette (quelques pixels) : on ne bouge pas', (
    tester,
  ) async {
    await pump(tester);
    await wheel(tester, [4, 4]);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Studio Lafleur'), findsOneWidget);
  });

  Future<void> slowPan(WidgetTester tester, Offset step) async {
    final center = tester.getCenter(find.byType(CoverflowScreen));
    final p = TestPointer(1, PointerDeviceKind.trackpad);
    tester.binding.handlePointerEvent(p.panZoomStart(center));
    var pan = Offset.zero;
    for (var i = 0; i < 30; i++) {
      pan += step;
      tester.binding.handlePointerEvent(p.panZoomUpdate(center, pan: pan));
      await tester.pump(const Duration(milliseconds: 60));
    }
    tester.binding.handlePointerEvent(p.panZoomEnd());
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('trackpad glissé lentement : on avance quand même', (
    tester,
  ) async {
    await pump(tester);
    await slowPan(tester, const Offset(-7, 0)); // ~1,2 album en 30 petits pas
    expect(find.text('Night Drive'), findsOneWidget);
  });

  testWidgets('trackpad à la verticale : défile aussi', (tester) async {
    await pump(tester);
    await slowPan(tester, const Offset(0, -7));
    expect(find.text('Night Drive'), findsOneWidget);
  });

  // hauteur à l'écran du bord le plus grand d'une pochette (perspective comprise)
  double shownHeight(WidgetTester tester, String path) {
    final box = tester.renderObject<RenderBox>(
      find
          .byWidgetPredicate((w) => w is CoverImage && w.trackPath == path)
          .first,
    );
    final s = box.size;
    double edge(double x) =>
        (box.localToGlobal(Offset(x, s.height)) -
                box.localToGlobal(Offset(x, 0)))
            .dy;
    return [edge(0), edge(s.width)].reduce((a, b) => a > b ? a : b);
  }

  testWidgets(
    'pochettes de côté plus petites que celle du centre (maquette 3)',
    (tester) async {
      await pump(tester);
      final centre = shownHeight(tester, '/m/3.flac');
      expect(shownHeight(tester, '/m/4.flac'), lessThan(centre));
      expect(shownHeight(tester, '/m/2.flac'), lessThan(centre));
    },
  );
}
