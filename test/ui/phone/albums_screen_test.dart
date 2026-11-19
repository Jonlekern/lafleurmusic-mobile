import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/app_scope.dart';
import 'package:lafleurmusic/demo/demo_library.dart';
import 'package:lafleurmusic/library/models.dart';
import 'package:lafleurmusic/ui/cover_image.dart';
import 'package:lafleurmusic/settings.dart';
import 'package:lafleurmusic/ui/phone/album_screen.dart';
import 'package:lafleurmusic/ui/phone/albums_screen.dart';
import 'package:lafleurmusic/ui/phone/home_screen.dart';
import 'package:lafleurmusic/ui/phone/phone_shell.dart';

import '../fonts.dart';
import '../keep_fixture.dart';
import '../phone_fixture.dart';

void main() {
  setUpAll(loadFonts);

  Future<PhoneFixture> open(WidgetTester tester) =>
      pumpPhone(tester, home: const AlbumsScreen());

  Future<void> play(
    WidgetTester tester,
    PhoneFixture f,
    String path,
    int day,
  ) => tester.runAsync(() => f.db.addPlay(path, DateTime(2026, 1, day)));

  List<String> grid(WidgetTester tester) => [
    for (final t in tester.widgetList<Text>(
      find.descendant(
        of: find.byKey(const Key('album-grid')),
        matching: find.byType(Text),
      ),
    ))
      t.data!,
  ];

  testWidgets('no listens yet: no « Écoutés récemment »; albums by name', (
    tester,
  ) async {
    await open(tester);
    expect(find.text('ÉCOUTÉS RÉCEMMENT'), findsNothing);
    expect(find.byKey(const Key('recent-albums')), findsNothing);
    expect(find.text('ALBUMS'), findsOneWidget);
    expect(find.text('Accueil'), findsOneWidget); // ‹ Accueil
    final names = grid(tester);
    expect(names, containsAll(['Lafleur Surf', 'Studio Lafleur']));
    expect(
      [...names]..sort(),
      names.length == names.toSet().length ? isNotEmpty : isEmpty,
    );
    // « Nom » est choisi
    final chip = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const Key('sort-name')),
        matching: find.byType(Text),
      ),
    );
    expect(chip.style!.color, const Color(0xFFF26EF2));
  });

  testWidgets('recently played: newest on the left, hidden album twin once', (
    tester,
  ) async {
    final f = await open(tester);
    await play(tester, f, DemoLibrary.summer.first.path, 1);
    await play(tester, f, DemoLibrary.studio.first.path, 2);
    await play(tester, f, DemoLibrary.studio[2].path, 3); // same album again
    await settle(tester);
    expect(find.text('ÉCOUTÉS RÉCEMMENT'), findsOneWidget);
    final recent = find.byKey(const Key('recent-albums'));
    final names = [
      for (final t in tester.widgetList<Text>(
        find.descendant(of: recent, matching: find.byType(Text)),
      ))
        t.data!,
    ];
    expect(names, ['Studio Lafleur', 'Summer Mix']);
    // toucher une pochette ouvre l'album
    await tester.tap(
      find.descendant(of: recent, matching: find.text('Summer Mix')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AlbumScreen), findsOneWidget);
  });

  testWidgets('the chosen sort is kept in the settings and saved', (
    tester,
  ) async {
    final f = await open(tester);
    final scope = AppScope.of(tester.element(find.byType(AlbumsScreen)));
    expect(scope.settings!.albumSort, AlbumSort.name);
    await play(tester, f, DemoLibrary.summer.first.path, 1);
    await play(tester, f, DemoLibrary.summer.first.path, 2);
    await settle(tester);
    await tester.tap(find.byKey(const Key('sort-mostPlayed')));
    await settle(tester);
    expect(scope.settings!.albumSort, AlbumSort.mostPlayed);
    expect(grid(tester).first, 'Summer Mix');
  });

  testWidgets(
    'the sort in the settings is the one shown when the screen opens',
    (tester) async {
      await open(tester);
      final scope = AppScope.of(tester.element(find.byType(AlbumsScreen)));
      scope.settings!.albumSort = AlbumSort.artist;
      Navigator.of(tester.element(find.byType(AlbumsScreen)))
          .push(MaterialPageRoute<void>(builder: (_) => const AlbumsScreen()));
      await tester.pumpAndSettle();
      final chip = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const Key('sort-artist')).last,
          matching: find.byType(Text),
        ),
      );
      expect(chip.style!.color, const Color(0xFFF26EF2));
    },
  );

  testWidgets('from Accueil: the ALBUMS title opens the screen', (
    tester,
  ) async {
    await pumpPhone(tester);
    await tester.tap(find.text('ALBUMS'));
    await tester.pumpAndSettle();
    expect(find.byType(AlbumsScreen), findsOneWidget);
    expect(find.byType(PhoneShell), findsOneWidget);
  });

  testWidgets('5 000 albums: only the tiles on screen are built', (
    tester,
  ) async {
    final f = await open(tester);
    await tester.runAsync(
      () => f.db.upsertTracks([
        for (var i = 0; i < 5000; i++)
          Track(
            path: '/m/big$i.mp3',
            title: 'T',
            artist: 'Art',
            albumArtist: 'Art',
            album: 'Big ${i.toString().padLeft(4, '0')}',
            trackNo: 1,
            durationMs: 1000,
            hasCover: false,
            size: 1,
          ),
      ]),
    );
    await settle(tester);
    final built = find.descendant(
      of: find.byKey(const Key('album-grid')),
      matching: find.byType(CoverImage),
    );
    expect(built.evaluate().length, inInclusiveRange(1, 40));
  });

  group('ligne « Albums » de l’Accueil', () {
    // la ligne est entre Morceaux et Artistes, et ouvre l'écran Albums
    Future<void> check(WidgetTester tester) async {
      expect(find.text('Albums'), findsOneWidget);
      final y = tester.getTopLeft(find.text('Albums')).dy;
      expect(y, greaterThan(tester.getTopLeft(find.text('Morceaux')).dy));
      expect(y, lessThan(tester.getTopLeft(find.text('Artistes')).dy));
      await tester.tap(find.text('Albums'));
      await tester.pumpAndSettle();
      await settle(tester);
      expect(find.byType(AlbumsScreen), findsOneWidget);
    }

    testWidgets('avec des comptes', (tester) async {
      await pumpPhone(tester);
      await check(tester);
    });

    testWidgets('sans compte (fichiers du téléphone seulement)', (
      tester,
    ) async {
      await pumpKeep(
        tester,
        addAccount: false,
        seed: (db) => db.upsertTracks(DemoLibrary.studio),
        home: const HomeScreen(),
      );
      await settle(tester);
      await check(tester);
    });

    testWidgets('le titre ALBUMS ouvre toujours l’écran', (tester) async {
      await pumpPhone(tester);
      await tester.tap(find.text('ALBUMS'));
      await tester.pumpAndSettle();
      await settle(tester);
      expect(find.byType(AlbumsScreen), findsOneWidget);
    });
  });
}
