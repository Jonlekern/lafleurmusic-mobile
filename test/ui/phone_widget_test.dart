import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lafleurmusic/ui/coverflow_screen.dart';
import 'package:lafleurmusic/ui/cover_image.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/demo/demo_library.dart';
import 'package:flutter/foundation.dart';
import 'package:lafleurmusic/player/player.dart';
import 'package:lafleurmusic/ui/equalizer_panel.dart';
import 'package:lafleurmusic/ui/library_screen.dart';
import 'package:lafleurmusic/ui/phone/album_screen.dart';
import 'package:lafleurmusic/ui/phone/home_screen.dart';
import 'package:lafleurmusic/ui/phone/mini_player.dart';
import 'package:lafleurmusic/ui/phone/now_screen.dart';
import 'package:lafleurmusic/ui/phone/phone_shell.dart';
import 'package:lafleurmusic/ui/playback_card.dart';

import 'fonts.dart';
import 'phone_fixture.dart';

Future<void> openStudio(WidgetTester tester) async {
  await tester.tap(find.text('Studio Lafleur'));
  await tester.pumpAndSettle();
  await settle(tester);
}

void main() {
  setUpAll(loadFonts);

  testWidgets('Accueil : barre de côté du Mac empilée, puces des comptes', (
    tester,
  ) async {
    await pumpPhone(tester);
    expect(find.byType(HomeScreen), findsOneWidget);
    for (final t in [
      'Tout',
      'Navidrome',
      'Jellyfin',
      'Rechercher',
      'BIBLIOTHÈQUE',
      'Cover Flow',
      'Morceaux',
      'Artistes',
      'Genres',
      'Top 100',
      'ALBUMS',
      'Studio Lafleur',
      'Summer Mix',
    ]) {
      expect(find.text(t), findsWidgets, reason: t);
    }
    expect(find.byType(MiniPlayer), findsOneWidget);
  });

  testWidgets('toucher « Studio Lafleur » ouvre l’album', (tester) async {
    await pumpPhone(tester);
    await openStudio(tester);
    expect(find.byType(AlbumScreen), findsOneWidget);
    expect(find.text('Albums'), findsOneWidget); // ‹ Albums
    expect(find.text('9 morceaux · 36 min'), findsOneWidget);
    expect(find.text('Night Swim'), findsOneWidget);
    expect(find.byType(MiniPlayer), findsOneWidget);
  });

  testWidgets('toucher une ligne joue l’album à partir d’elle', (tester) async {
    final f = await pumpPhone(tester);
    await openStudio(tester);
    await tester.tap(find.text('Golden Hour'));
    await tester.pump();
    expect(f.player.calls, contains('play'));
    expect(f.player.lastTracks!.map((t) => t.title), [
      for (final t in DemoLibrary.studio) t.title,
    ]);
    expect(f.player.lastIndex, 2);
  });

  testWidgets('glisser « Night Swim » vers la gauche : Lire ensuite', (
    tester,
  ) async {
    final f = await pumpPhone(tester);
    await openStudio(tester);
    final g = await tester.startGesture(
      tester.getCenter(find.text('Night Swim')),
    );
    for (var i = 0; i < 6; i++) {
      await g.moveBy(const Offset(-25, 0));
      await tester.pump();
    }
    expect(find.text('← Lire ensuite'), findsOneWidget); // bandeau rose
    await g.up();
    await tester.pumpAndSettle();
    expect(f.player.calls, contains('playNext'));
    expect(f.player.lastAdded!.single.title, 'Night Swim');
    expect(f.player.calls, isNot(contains('play'))); // pas lancé
  });

  testWidgets('un petit glissement ne fait rien', (tester) async {
    final f = await pumpPhone(tester);
    await openStudio(tester);
    await tester.drag(find.text('Night Swim'), const Offset(-30, 0));
    await tester.pumpAndSettle();
    expect(f.player.calls, isNot(contains('playNext')));
  });

  testWidgets('appui long : feuille Lire ensuite / Ajouter à la file', (
    tester,
  ) async {
    final f = await pumpPhone(tester);
    await openStudio(tester);
    await tester.longPress(find.text('Sunset Tape'));
    await tester.pumpAndSettle();
    expect(find.text('Lire ensuite'), findsOneWidget);
    expect(find.text('Ajouter à la file'), findsOneWidget);
    expect(find.text('Garder sur mon iPhone'), findsNothing); // plan 2
    expect(find.text('Sélectionner…'), findsNothing); // plan 2
    await tester.tap(find.text('Ajouter à la file'));
    await tester.pumpAndSettle();
    expect(f.player.calls, contains('enqueue'));
    expect(f.player.lastAdded!.single.title, 'Sunset Tape');
    expect(find.text('Ajouter à la file'), findsNothing); // feuille fermée

    await tester.longPress(find.text('Paradise Club'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lire ensuite'));
    await tester.pumpAndSettle();
    expect(f.player.calls.last, 'playNext');
    expect(f.player.lastAdded!.single.title, 'Paradise Club');
  });

  testWidgets('toucher le mini-lecteur ouvre En cours', (tester) async {
    await pumpPhone(tester);
    await tester.tap(find.byType(MiniPlayer));
    await tester.pumpAndSettle();
    expect(find.byType(NowScreen), findsOneWidget);
    expect(find.text('LAFLEURSTUDIO · Studio Lafleur'), findsOneWidget);
    expect(find.text('1:33'), findsOneWidget);
    expect(find.text('−2:32'), findsOneWidget);
    expect(find.byType(MiniPlayer), findsNothing);
  });

  testWidgets('mini-lecteur : pause et suivant', (tester) async {
    final f = await pumpPhone(tester);
    await tester.tap(find.byKey(const Key('mini-toggle')));
    await tester.tap(find.byKey(const Key('mini-next')));
    expect(f.player.calls, ['toggle', 'next']);
    expect(find.byType(NowScreen), findsNothing);
  });

  testWidgets('En cours : onglets À suivre / Égaliseur / Lecture', (
    tester,
  ) async {
    await pumpPhone(tester);
    await tester.tap(find.byType(MiniPlayer));
    await tester.pumpAndSettle();
    expect(find.text('AJOUTÉS PAR TOI'), findsOneWidget);
    expect(find.text('Nightcall'), findsOneWidget);

    await tester.tap(find.text('Égaliseur'));
    await tester.pumpAndSettle();
    expect(find.byType(EqualizerPanel), findsOneWidget);
    expect(find.text('AJOUTÉS PAR TOI'), findsNothing);

    await tester.tap(find.text('Lecture'));
    await tester.pumpAndSettle();
    expect(find.byType(PlaybackCard), findsOneWidget);
    expect(find.text('Fondu enchaîné'), findsOneWidget);
    expect(tester.takeException(), isNull); // rien ne déborde à 390 px

    await tester.tap(find.text('À suivre'));
    await tester.pumpAndSettle();
    expect(find.text('Nightcall'), findsOneWidget);
  });

  testWidgets('En cours : lecture / pause au gros bouton rose', (tester) async {
    final f = await pumpPhone(tester);
    await tester.tap(find.byType(MiniPlayer));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('now-toggle')));
    expect(f.player.calls, ['toggle']);
  });

  testWidgets('glisser depuis le bord gauche : retour', (tester) async {
    await pumpPhone(tester);
    await openStudio(tester);
    expect(find.byType(AlbumScreen), findsOneWidget);
    // depuis le bord gauche (x = 5), jusqu'aux trois quarts de l'écran
    await tester.dragFrom(const Offset(5, 400), const Offset(300, 0));
    await tester.pumpAndSettle();
    expect(find.byType(AlbumScreen), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('bouton retour d’Android : retour', (tester) async {
    await pumpPhone(tester);
    await openStudio(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(AlbumScreen), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('« ‹ Albums » revient à l’Accueil', (tester) async {
    await pumpPhone(tester);
    await openStudio(tester);
    await tester.tap(find.text('Albums'));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(AlbumScreen), findsNothing);
  });

  testWidgets('Morceaux, Artistes, Genres, Top 100 s’ouvrent', (tester) async {
    await pumpPhone(tester);
    await tester.tap(find.text('Morceaux'));
    await tester.pumpAndSettle();
    await settle(tester);
    expect(find.text('Heatwave'), findsOneWidget);
    await tester.tap(find.text('Accueil'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Artistes'));
    await tester.pumpAndSettle();
    await settle(tester);
    await tester.tap(find.text('Kavinsky'));
    await tester.pumpAndSettle();
    await settle(tester);
    expect(find.text('Night Swim'), findsOneWidget);
    expect(find.text('Artistes'), findsOneWidget); // ‹ Artistes
  });

  testWidgets('Rechercher : résultats sous le champ', (tester) async {
    final f = await pumpPhone(tester);
    await tester.enterText(find.byType(TextField), 'heat');
    await settle(tester);
    expect(find.text('Heatwave'), findsOneWidget);
    expect(find.text('BIBLIOTHÈQUE'), findsNothing);
    await tester.tap(find.text('Heatwave'));
    await tester.pump();
    expect(f.player.lastTracks!.single.title, 'Heatwave');
  });

  test(
    'Android, iOS : toujours le téléphone ; ordinateur : colonnes dès 900 px',
    () {
      for (final p in [TargetPlatform.android, TargetPlatform.iOS]) {
        expect(AdaptiveHome.isPhone(const Size(390, 844), p), isTrue);
        expect(AdaptiveHome.isPhone(const Size(1440, 900), p), isTrue);
        expect(AdaptiveHome.isPhone(const Size(844, 390), p), isTrue);
      }
      for (final p in [
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
      ]) {
        expect(AdaptiveHome.isPhone(const Size(899, 600), p), isTrue);
        expect(AdaptiveHome.isPhone(const Size(900, 600), p), isFalse);
        expect(AdaptiveHome.isPhone(const Size(1440, 900), p), isFalse);
      }
    },
  );

  Future<void> pumpWide(WidgetTester tester, TargetPlatform platform) async {
    debugDefaultTargetPlatformOverride = platform;
    await pumpPhone(tester, home: const AdaptiveHome());
    tester.view.physicalSize = const Size(1440, 900);
    await settle(tester);
  }

  testWidgets('iPhone à 1440 px : toujours le téléphone', (tester) async {
    await pumpWide(tester, TargetPlatform.iOS);
    expect(find.byType(PhoneShell), findsOneWidget);
    expect(find.byType(LibraryScreen), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Mac à 1440 px : les colonnes', (tester) async {
    await pumpWide(tester, TargetPlatform.macOS);
    expect(find.byType(LibraryScreen), findsOneWidget);
    expect(find.byType(PhoneShell), findsNothing);
    await tester.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });

  group('Cover Flow couché', () {
    // Johnny : « couché sur l'Accueil → Cover Flow, relevé → retour au même endroit ;
    // couché pendant la lecture sur En cours : rien ne bascule »
    Future<void> turn(WidgetTester tester, {required bool landscape}) async {
      if (landscape) {
        landscapeSize(tester);
      } else {
        phoneSize(tester);
      }
      await tester.pump();
      await settle(tester);
    }

    testWidgets(
      'Accueil couché : Cover Flow sur l’album en cours, relevé : retour',
      (tester) async {
        await pumpPhone(tester);
        expect(find.byType(CoverflowScreen), findsNothing);
        await turn(tester, landscape: true);
        expect(find.byType(CoverflowScreen), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(CoverflowScreen),
            matching: find.text('Studio Lafleur'),
          ),
          findsOneWidget,
        ); // l'album du morceau en cours, au centre
        expect(find.text('Album · 9 morceaux'), findsOneWidget);
        await turn(tester, landscape: false);
        expect(find.byType(CoverflowScreen), findsNothing);
        expect(find.byType(HomeScreen), findsOneWidget);
      },
    );

    testWidgets('relevé : on retrouve l’écran d’avant (l’album ouvert)', (
      tester,
    ) async {
      await pumpPhone(tester);
      await openStudio(tester);
      await turn(tester, landscape: true);
      expect(find.byType(CoverflowScreen), findsOneWidget);
      await turn(tester, landscape: false);
      expect(find.byType(CoverflowScreen), findsNothing);
      expect(find.byType(AlbumScreen), findsOneWidget);
      expect(find.text('Night Swim'), findsOneWidget);
    });

    testWidgets('couché, le Cover Flow part de l’album ouvert en dernier', (
      tester,
    ) async {
      final f = await pumpPhone(tester);
      f.player.current =
          const PlayerState(); // rien en cours : le dernier album ouvert
      await tester.tap(find.text('Summer Mix'));
      await tester.pumpAndSettle();
      await settle(tester);
      await tester.tap(find.text('Albums'));
      await tester.pumpAndSettle();
      await turn(tester, landscape: true);
      final flow = tester.widget<CoverflowScreen>(find.byType(CoverflowScreen));
      expect(flow.albums[flow.initial].name, 'Summer Mix');
    });

    testWidgets(
      'En cours : couché, rien ne bascule, et le téléphone reste debout',
      (tester) async {
        final orientations = <Object?>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'SystemChrome.setPreferredOrientations') {
              orientations.add(call.arguments);
            }
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        await pumpPhone(tester);
        await tester.tap(find.byType(MiniPlayer));
        await tester.pumpAndSettle();
        expect(find.byType(NowScreen), findsOneWidget);
        expect(orientations.last, ['DeviceOrientation.portraitUp']);
        await turn(tester, landscape: true);
        expect(find.byType(NowScreen), findsOneWidget);
        expect(find.byType(CoverflowScreen), findsNothing);
        // on quitte En cours : toutes les orientations reviennent, donc le Cover Flow couché
        await tester.tap(find.byIcon(Icons.keyboard_arrow_down_rounded));
        await tester.pumpAndSettle();
        expect(orientations.last, hasLength(3));
        expect(find.byType(CoverflowScreen), findsOneWidget);
      },
    );

    testWidgets('Lecture joue l’album du centre', (tester) async {
      final f = await pumpPhone(tester);
      await turn(tester, landscape: true);
      await tester.tap(find.text('Lecture'));
      await settle(tester);
      expect(f.player.calls, contains('play'));
      expect(f.player.lastTracks!.map((t) => t.album).toSet(), {
        DemoLibrary.playing.album,
      });
    });

    testWidgets('toucher la pochette du centre la joue', (tester) async {
      final f = await pumpPhone(tester);
      await turn(tester, landscape: true);
      final flow = tester.widget<CoverflowScreen>(find.byType(CoverflowScreen));
      final centre = flow.albums[flow.initial].coverTrackPath;
      await tester.tap(
        find
            .byWidgetPredicate((w) => w is CoverImage && w.trackPath == centre)
            .first,
      );
      await settle(tester);
      expect(f.player.lastTracks!.map((t) => t.album).toSet(), {
        DemoLibrary.playing.album,
      });
    });

    testWidgets('glisser le doigt défile, toucher une voisine la centre', (
      tester,
    ) async {
      await pumpPhone(tester);
      await turn(tester, landscape: true);
      final inFlow = find.descendant(
        of: find.byType(CoverflowScreen),
        matching: find.text('Studio Lafleur'),
      );
      expect(inFlow, findsOneWidget);
      await tester.dragFrom(const Offset(420, 120), const Offset(-160, 0));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(inFlow, findsNothing);
    });

    testWidgets('« Ouvrir l’album » ouvre l’album, relevé on y est', (
      tester,
    ) async {
      await pumpPhone(tester);
      await turn(tester, landscape: true);
      await tester.tap(find.text('Ouvrir l’album'));
      await tester.pumpAndSettle();
      await settle(tester);
      expect(find.byType(AlbumScreen), findsOneWidget);
      expect(
        find.byType(CoverflowScreen),
        findsNothing,
      ); // l'album s'affiche couché
      await turn(tester, landscape: false);
      expect(find.byType(AlbumScreen), findsOneWidget);
      // couché de nouveau : Cover Flow de nouveau
      await turn(tester, landscape: true);
      expect(find.byType(CoverflowScreen), findsOneWidget);
    });

    testWidgets(
      '« ‹ Albums » depuis l’album ouvert du Cover Flow : Cover Flow',
      (tester) async {
        await pumpPhone(tester);
        await turn(tester, landscape: true);
        await tester.tap(find.text('Ouvrir l’album'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Albums'));
        await tester.pumpAndSettle();
        expect(find.byType(CoverflowScreen), findsOneWidget);
      },
    );

    testWidgets(
      'sur Mac, fenêtre large et basse : pas de Cover Flow du téléphone',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        await pumpPhone(tester);
        await turn(tester, landscape: true);
        expect(find.byType(CoverflowScreen), findsNothing);
        await tester.pumpWidget(const SizedBox());
        debugDefaultTargetPlatformOverride = null;
      },
    );
  });
}
