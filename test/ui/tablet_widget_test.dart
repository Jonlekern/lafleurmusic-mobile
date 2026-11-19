import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/ui/coverflow_screen.dart';
import 'package:lafleurmusic/ui/library_screen.dart';
import 'package:lafleurmusic/ui/now_panel.dart';
import 'package:lafleurmusic/ui/phone/accounts_screen.dart';
import 'package:lafleurmusic/ui/phone/on_device_screen.dart';
import 'package:lafleurmusic/ui/phone/phone_shell.dart';
import 'package:lafleurmusic/ui/phone/playlist_screen.dart';
import 'package:lafleurmusic/ui/sidebar.dart';
import 'package:lafleurmusic/ui/tablet.dart';
import 'package:lafleurmusic/ui/track_list.dart';

import 'fonts.dart';
import 'keep_fixture.dart';
import 'phone/keep_screen_test.dart'
    show confirmRemoval, done, longPress, pathsOf;
import 'phone/playlist_screen_test.dart' show pumpPlaylists;

/// La tablette (ou le téléphone) sur la bibliothèque du serveur : [w] × [h], sans barre d'état.
Future<KeepFixture> pumpTablet(
  WidgetTester tester,
  double w,
  double h, {
  TargetPlatform platform = TargetPlatform.iOS,
}) async {
  debugDefaultTargetPlatformOverride = platform;
  final f = await pumpPlaylists(tester, home: const AdaptiveHome());
  tester.view.physicalSize = Size(w, h);
  tester.view.padding = FakeViewPadding.zero;
  tester.view.viewPadding = FakeViewPadding.zero;
  await tester.pump();
  await done(tester);
  return f;
}

/// Un test sur une tablette : la plateforme simulée est remise à zéro à la fin.
void tabletTest(String name, Future<void> Function(WidgetTester) body) =>
    testWidgets(name, (tester) async {
      try {
        await body(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

/// Une ligne de la liste du milieu (En cours à droite montre aussi des titres).
Finder inList(String title) =>
    find.descendant(of: find.byType(TrackList), matching: find.text(title));

void main() {
  setUpAll(loadFonts);

  test('isTablet : plus petit côté ≥ 600 sur Android et iOS', () {
    for (final p in [TargetPlatform.android, TargetPlatform.iOS]) {
      expect(isTablet(const Size(1024, 768), p), isTrue);
      expect(isTablet(const Size(768, 1024), p), isTrue);
      expect(isTablet(const Size(390, 844), p), isFalse);
      expect(
        isTablet(const Size(932, 430), p),
        isFalse,
      ); // gros téléphone couché
    }
    expect(isTablet(const Size(1440, 900), TargetPlatform.macOS), isFalse);
  });

  test('orientations : quatre sur tablette, trois sur téléphone', () {
    expect(orientationsFor(const Size(768, 1024)), hasLength(4));
    expect(orientationsFor(const Size(390, 844)), mobileOrientations);
  });

  group('colonnes ou téléphone', () {
    for (final (w, h) in [(1024.0, 768.0), (768.0, 1024.0)]) {
      tabletTest('${w.toInt()} × ${h.toInt()} : les colonnes du Mac', (
        tester,
      ) async {
        await pumpTablet(tester, w, h);
        expect(find.byType(LibraryScreen), findsOneWidget);
        expect(find.byType(Sidebar), findsOneWidget);
        expect(find.byType(PhoneShell), findsNothing);
        expect(find.byType(CoverflowScreen), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }

    tabletTest('couchée : En cours à droite, pas de Cover Flow du téléphone', (
      tester,
    ) async {
      await pumpTablet(tester, 1024, 768);
      expect(find.byType(NowPanel), findsOneWidget);
      expect(find.byType(CoverflowScreen), findsNothing);
    });

    tabletTest('390 × 844 : le téléphone', (tester) async {
      await pumpTablet(tester, 390, 844);
      expect(find.byType(PhoneShell), findsOneWidget);
      expect(find.byType(LibraryScreen), findsNothing);
    });

    tabletTest('téléphone couché, même 932 px : le téléphone', (tester) async {
      await pumpTablet(tester, 932, 430);
      expect(find.byType(PhoneShell), findsOneWidget);
      expect(find.byType(LibraryScreen), findsNothing);
    });

    tabletTest('Cover Flow de la barre de côté : celui du Mac', (tester) async {
      await pumpTablet(tester, 1024, 768);
      await tester.tap(
        find.descendant(
          of: find.byType(Sidebar),
          matching: find.text('Cover Flow'),
        ),
      );
      await done(tester);
      expect(find.byType(CoverflowScreen), findsOneWidget);
      expect(
        tester.widget<CoverflowScreen>(find.byType(CoverflowScreen)).phone,
        isFalse,
      );
    });
  });

  group('barre de côté de la tablette', () {
    tabletTest('« Comptes » ouvre les comptes', (tester) async {
      await pumpTablet(tester, 1024, 768);
      await tester.tap(
        find.descendant(
          of: find.byType(Sidebar),
          matching: find.text('Comptes'),
        ),
      );
      await done(tester);
      expect(find.byType(AccountsScreen), findsOneWidget);
    });

    tabletTest('« Sur mon iPad » ouvre les copies gardées', (tester) async {
      await pumpTablet(tester, 768, 1024);
      await tester.tap(find.text('Sur mon iPad'));
      await done(tester);
      expect(find.byType(OnDeviceScreen), findsOneWidget);
    });

    tabletTest('Android : « Sur ma tablette »', (tester) async {
      await pumpTablet(tester, 1024, 768, platform: TargetPlatform.android);
      expect(find.text('Sur ma tablette'), findsOneWidget);
      expect(find.text('Sur mon iPad'), findsNothing);
    });

    tabletTest('PLAYLISTS DU SERVEUR sous les albums, une playlist s’ouvre', (
      tester,
    ) async {
      await pumpTablet(tester, 1024, 768);
      final list = find.byType(Sidebar);
      final head = find.descendant(
        of: list,
        matching: find.text('PLAYLISTS DU SERVEUR'),
      );
      await tester.ensureVisible(head);
      await tester.pump();
      expect(head, findsOneWidget);
      expect(
        tester.getTopLeft(head).dy,
        greaterThan(
          tester
              .getTopLeft(
                find.descendant(of: list, matching: find.text('Summer Mix')),
              )
              .dy,
        ),
      );
      final soiree = find.descendant(of: list, matching: find.text('Soirée'));
      await tester.ensureVisible(soiree);
      await tester.pump();
      await tester.tap(soiree);
      await done(tester);
      expect(find.byType(PlaylistScreen), findsOneWidget);
    });

    tabletTest('sur un Mac : ni Comptes ni Sur mon iPad', (tester) async {
      await pumpTablet(tester, 1440, 900, platform: TargetPlatform.macOS);
      expect(find.byType(LibraryScreen), findsOneWidget);
      expect(find.text('Comptes'), findsNothing);
      expect(find.text('Sur mon iPad'), findsNothing);
    });
  });

  group('Garder / Retirer depuis la tablette', () {
    tabletTest('appui long sur un album de la barre : Garder sur mon iPad', (
      tester,
    ) async {
      final f = await pumpTablet(tester, 1024, 768);
      await longPress(
        tester,
        find.descendant(
          of: find.byType(Sidebar),
          matching: find.text('Studio Lafleur'),
        ),
      );
      expect(find.text('Garder sur mon iPad'), findsOneWidget);
      await tester.tap(find.text('Garder sur mon iPad'));
      await done(tester);
      expect(f.downloader.kept, [pathsOf('Studio Lafleur')]);
    });

    tabletTest(
      'Retirer : la fenêtre de confirmation, puis les copies partent',
      (tester) async {
        final f = await pumpTablet(tester, 1024, 768);
        await longPress(
          tester,
          find.descendant(
            of: find.byType(Sidebar),
            matching: find.text('Lafleur Surf'),
          ),
        );
        expect(find.text('Retirer de l’iPad'), findsOneWidget);
        await tester.tap(find.text('Retirer de l’iPad'));
        await done(tester);
        expect(find.text('Retirer de l’iPad ?'), findsOneWidget);
        expect(f.downloader.forgotten, isEmpty);
        await confirmRemoval(tester);
        expect(f.downloader.forgotten, [pathsOf('Lafleur Surf')]);
      },
    );

    tabletTest('appui long sur un morceau de la liste : Garder', (
      tester,
    ) async {
      final f = await pumpTablet(tester, 1024, 768);
      await tester.tap(
        find.descendant(
          of: find.byType(Sidebar),
          matching: find.text('Studio Lafleur'),
        ),
      );
      await done(tester);
      await longPress(tester, inList('Golden Hour'));
      expect(find.text('Garder sur mon iPad'), findsOneWidget);
      await tester.tap(find.text('Garder sur mon iPad'));
      await done(tester);
      expect(f.downloader.kept.single, hasLength(1));
    });

    tabletTest('appui long sur un morceau gardé : Retirer, avec la question', (
      tester,
    ) async {
      final f = await pumpTablet(tester, 1024, 768);
      await longPress(tester, inList('Surf Radio')); // l'album gardé est ouvert
      await tester.tap(find.text('Retirer de l’iPad'));
      await done(tester);
      expect(find.text('Retirer de l’iPad ?'), findsOneWidget);
      expect(f.downloader.forgotten, isEmpty);
      await confirmRemoval(tester);
      expect(f.downloader.forgotten.single, hasLength(1));
    });

    tabletTest('Android : « Garder sur ma tablette »', (tester) async {
      await pumpTablet(tester, 1024, 768, platform: TargetPlatform.android);
      await longPress(
        tester,
        find.descendant(
          of: find.byType(Sidebar),
          matching: find.text('Studio Lafleur'),
        ),
      );
      expect(find.text('Garder sur ma tablette'), findsOneWidget);
    });

    tabletTest('appui long sur une playlist du serveur : sa feuille', (
      tester,
    ) async {
      await pumpTablet(tester, 1024, 768);
      final soiree = find.descendant(
        of: find.byType(Sidebar),
        matching: find.text('Soirée'),
      );
      await tester.ensureVisible(soiree);
      await tester.pump();
      await tester.longPress(soiree);
      await done(tester);
      expect(find.text('Garder sur mon iPad'), findsOneWidget);
    });
  });
}
