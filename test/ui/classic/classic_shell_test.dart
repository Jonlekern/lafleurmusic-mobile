import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/app_scope.dart';
import 'package:lafleurmusic/demo/demo_library.dart';
import 'package:lafleurmusic/l10n/strings.dart';
import 'package:lafleurmusic/library/models.dart';
import 'package:lafleurmusic/player/player.dart';
import 'package:lafleurmusic/ui/classic/classic_menu.dart';
import 'package:lafleurmusic/ui/classic/classic_now.dart';
import 'package:lafleurmusic/ui/classic/classic_shell.dart';
import 'package:lafleurmusic/ui/classic/click_wheel.dart';
import 'package:lafleurmusic/ui/coverflow_screen.dart';
import 'package:lafleurmusic/ui/phone/accounts_screen.dart';
import 'package:lafleurmusic/ui/phone/album_screen.dart';
import 'package:lafleurmusic/ui/phone/home_screen.dart';
import 'package:lafleurmusic/ui/phone/mini_player.dart';
import 'package:lafleurmusic/ui/phone/now_screen.dart';
import 'package:lafleurmusic/ui/phone/phone_shell.dart';

import '../fonts.dart';
import '../keep_fixture.dart';
import '../phone_fixture.dart';

/// La ligne choisie (rose) de la liste affichée.
String selected(WidgetTester tester) => tester
    .widgetList<ClassicRow>(find.byType(ClassicRow))
    .singleWhere((r) => r.selected)
    .label;

ClassicRow row(WidgetTester tester, String label) => tester
    .widgetList<ClassicRow>(find.byType(ClassicRow))
    .singleWhere((r) => r.label == label);

ClickWheel wheel(WidgetTester tester) =>
    tester.widget<ClickWheel>(find.byType(ClickWheel));

/// [n] crans de molette (+ = descendre), puis une image.
Future<void> rotate(WidgetTester tester, int n) async {
  for (var i = 0; i < n.abs(); i++) {
    wheel(tester).onRotate(n.sign);
  }
  await tester.pump();
}

/// Appuie sur une zone de la molette, au doigt.
Future<void> press(WidgetTester tester, String zone) async {
  final box = tester.getRect(find.byType(ClickWheel));
  final c = box.center, r = box.width / 2;
  final at = switch (zone) {
    'select' => c,
    'menu' => c + Offset(0, -r * .8),
    'next' => c + Offset(r * .8, 0),
    'previous' => c + Offset(-r * .8, 0),
    'play' => c + Offset(0, r * .8),
    _ => throw ArgumentError(zone),
  };
  await tester.tapAt(at);
  await settle(tester);
}

/// Descend ou monte à la molette jusqu'à la ligne [label].
Future<void> rotateTo(WidgetTester tester, String label) async {
  for (var i = 0; i < 50 && selected(tester) != label; i++) {
    await rotate(tester, 1);
  }
  for (var i = 0; i < 50 && selected(tester) != label; i++) {
    await rotate(tester, -1);
  }
  expect(selected(tester), label);
}

Track _big(int i, {String album = 'Big', String? title}) => Track(
  path: 'demo://$album/$i',
  folderId: 1,
  title: title ?? 'Song ${i.toString().padLeft(4, '0')}',
  artist: 'Big',
  album: album,
  trackNo: i + 1,
  durationMs: 200000,
  hasCover: false,
  mtime: 1,
  size: 1,
);

void main() {
  setUpAll(loadFonts);

  testWidgets('le menu, dans l\'ordre, la première ligne choisie', (
    tester,
  ) async {
    await pumpPhone(tester, home: const ClassicShell());
    expect(find.text('MUSIQUE'), findsOneWidget);
    expect(selected(tester), 'Cover Flow');
    // chaque cran descend d'une ligne, dans l'ordre du menu
    final order = [selected(tester)];
    for (var i = 0; i < 8; i++) {
      await rotate(tester, 1);
      order.add(selected(tester));
    }
    expect(order, [
      'Cover Flow',
      'Artistes',
      'Albums',
      'Morceaux',
      'Playlists',
      'Top 100',
      'Sur mon téléphone', // Android dans les tests
      'En cours',
      'Réglages',
    ]);
    // maquette : pas de mini-lecteur ; le même cadre que le mode normal
    expect(find.byType(MiniPlayer), findsNothing);
    expect(find.byType(PhoneShell), findsOneWidget);
  });

  testWidgets('sur iPhone : « Sur mon iPhone »', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await pumpPhone(tester, home: const ClassicShell());
    expect(find.text('Sur mon iPhone'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'à la molette : Albums → album → morceau joué ; MENU remonte, rien à la racine',
    (tester) async {
      final fx = await pumpPhone(tester, home: const ClassicShell());
      await rotate(tester, 2);
      expect(selected(tester), 'Albums');
      await press(tester, 'select');
      expect(find.text('ALBUMS'), findsOneWidget);
      expect(selected(tester), 'Lafleur Surf'); // la première
      await rotateTo(tester, 'Studio Lafleur');
      await press(tester, 'select');
      expect(find.text('STUDIO LAFLEUR'), findsOneWidget);
      expect(selected(tester), 'Ocean Drive');
      await rotate(tester, 2);
      expect(selected(tester), 'Golden Hour');
      await press(tester, 'select');
      expect(fx.player.calls, ['play']);
      expect(
        fx.player.lastTracks!.map((t) => t.title),
        DemoLibrary.studio.map((t) => t.title),
      );
      expect(fx.player.lastIndex, 2);
      // comme l'iPod : En cours s'ouvre ; MENU revient à la liste
      await tester.pumpAndSettle();
      expect(find.byType(ClassicNow), findsOneWidget);
      await press(tester, 'menu');
      await tester.pumpAndSettle();
      expect(find.text('STUDIO LAFLEUR'), findsOneWidget);
      expect(selected(tester), 'Golden Hour');

      await press(tester, 'menu');
      expect(find.text('ALBUMS'), findsOneWidget);
      expect(selected(tester), 'Studio Lafleur'); // la ligne retrouvée
      await press(tester, 'menu');
      expect(find.text('MUSIQUE'), findsOneWidget);
      expect(selected(tester), 'Albums');
      await press(tester, 'menu'); // à la racine : rien
      expect(find.text('MUSIQUE'), findsOneWidget);
      expect(selected(tester), 'Albums');
      expect(fx.player.calls, ['play']);
    },
  );

  testWidgets('tourner le doigt sur l\'anneau déplace la ligne choisie', (
    tester,
  ) async {
    await pumpPhone(tester, home: const ClassicShell());
    final box = tester.getRect(find.byType(ClickWheel));
    final c = box.center, r = box.width / 2 * .75;
    Offset at(double deg) =>
        c +
        Offset(math.cos(deg * math.pi / 180), math.sin(deg * math.pi / 180)) *
            r;
    // 45° dans le sens des aiguilles (3 crans), par pas de 5°
    final g = await tester.startGesture(at(-90));
    for (var d = -85.0; d <= -45; d += 5) {
      await g.moveTo(at(d));
    }
    await g.up();
    await tester.pump();
    expect(selected(tester), 'Morceaux');
    // 15° dans l'autre sens : un cran vers le haut
    final g2 = await tester.startGesture(at(0));
    for (var d = -5.0; d >= -15; d -= 5) {
      await g2.moveTo(at(d));
    }
    await g2.up();
    await tester.pump();
    expect(selected(tester), 'Albums');
  });

  testWidgets(
    'la molette ne sort pas de la liste (ni avant le début, ni après la fin)',
    (tester) async {
      await pumpPhone(tester, home: const ClassicShell());
      await rotate(tester, -3);
      expect(selected(tester), 'Cover Flow');
      await rotate(tester, 30);
      expect(selected(tester), 'Réglages');
    },
  );

  testWidgets('un toucher sur une ligne la choisit et l\'ouvre', (
    tester,
  ) async {
    final fx = await pumpPhone(tester, home: const ClassicShell());
    await tester.tap(find.text('Morceaux'));
    await settle(tester);
    expect(find.text('MORCEAUX'), findsOneWidget);
    await tester.tap(find.text('Heatwave'));
    await settle(tester);
    expect(selected(tester), 'Heatwave');
    expect(fx.player.calls, ['play']);
    expect(fx.player.lastTracks![fx.player.lastIndex!].title, 'Heatwave');
  });

  testWidgets(
    'VoiceOver / TalkBack : chaque ligne est un bouton, la choisie le dit',
    (tester) async {
      final h = tester.ensureSemantics();
      await pumpPhone(tester, home: const ClassicShell());
      await rotate(tester, 2);
      expect(
        tester.getSemantics(find.text('Albums')),
        isSemantics(
          label: 'Albums',
          isButton: true,
          isSelected: true,
          hasTapAction: true,
        ),
      );
      expect(
        tester.getSemantics(find.text('Morceaux')),
        isSemantics(
          label: 'Morceaux',
          isButton: true,
          isSelected: false,
          hasTapAction: true,
        ),
      );
      h.dispose();
    },
  );

  testWidgets('Artistes → un artiste → ses morceaux', (tester) async {
    final fx = await pumpPhone(tester, home: const ClassicShell());
    await tester.tap(find.text('Artistes'));
    await settle(tester);
    expect(find.text('ARTISTES'), findsOneWidget);
    await rotateTo(tester, 'Kavinsky');
    await press(tester, 'select');
    expect(find.text('KAVINSKY'), findsOneWidget);
    expect(selected(tester), 'Night Swim');
    await press(tester, 'select');
    expect(fx.player.lastTracks!.single.title, 'Night Swim');
  });

  testWidgets('Top 100 vide : le texte du mode normal', (tester) async {
    await pumpPhone(tester, home: const ClassicShell());
    await tester.tap(find.text('Top 100'));
    await settle(tester);
    expect(find.text('TOP 100'), findsOneWidget);
    expect(
      find.text('Rien encore : écoute un peu de musique.'),
      findsOneWidget,
    );
    await press(tester, 'select'); // rien à choisir : rien ne casse
    await press(tester, 'menu');
    expect(find.text('MUSIQUE'), findsOneWidget);
  });

  testWidgets(
    '⏮ ⏭ ▶︎❙❙ commandent le lecteur, à la racine comme dans une liste',
    (tester) async {
      final fx = await pumpPhone(tester, home: const ClassicShell());
      await press(tester, 'play');
      await press(tester, 'next');
      await tester.tap(find.text('Albums'));
      await settle(tester);
      await press(tester, 'previous');
      expect(fx.player.calls, ['toggle', 'next', 'previous']);
      expect(find.text('ALBUMS'), findsOneWidget); // la liste n'a pas bougé
    },
  );

  testWidgets('En cours (Classic), Réglages, Cover Flow', (tester) async {
    await pumpPhone(tester, home: const ClassicShell());
    await rotateTo(tester, 'En cours');
    await press(tester, 'select');
    await tester.pumpAndSettle();
    expect(find.byType(ClassicNow), findsOneWidget);
    expect(find.byType(NowScreen), findsNothing);
    Navigator.of(tester.element(find.byType(ClassicNow))).pop();
    await tester.pumpAndSettle();

    await rotateTo(tester, 'Réglages');
    await press(tester, 'select');
    await tester.pumpAndSettle();
    expect(find.byType(AccountsScreen), findsOneWidget);
    Navigator.of(tester.element(find.byType(AccountsScreen))).pop();
    await tester.pumpAndSettle();

    await rotateTo(tester, 'Cover Flow');
    await press(tester, 'select');
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CoverflowScreen), findsOneWidget);
  });

  // Johnny 20.11 : ouvert depuis le menu, le Cover Flow n'avait aucune sortie sur iPhone
  // (pas de molette, pas de retour) : bloqué, impossible de rejoindre Réglages.
  testWidgets(
    'Cover Flow du menu : « ‹ Retour » ramène au menu et à la molette',
    (tester) async {
      await pumpPhone(tester, home: const ClassicShell());
      await rotateTo(tester, 'Cover Flow');
      await press(tester, 'select');
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CoverflowScreen), findsOneWidget);
      expect(find.textContaining('Échap'), findsNothing);
      await tester.tap(find.text('Retour'));
      await tester.pumpAndSettle();
      expect(find.byType(CoverflowScreen), findsNothing);
      expect(find.byType(ClickWheel), findsOneWidget);
      await rotateTo(tester, 'Réglages');
      await press(tester, 'select');
      await tester.pumpAndSettle();
      expect(find.byType(AccountsScreen), findsOneWidget);
    },
  );

  testWidgets('Android : retour remonte d\'un niveau', (tester) async {
    await pumpPhone(tester, home: const ClassicShell());
    await tester.tap(find.text('Albums'));
    await settle(tester);
    expect(find.text('ALBUMS'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('MUSIQUE'), findsOneWidget);
    expect(selected(tester), 'Albums');
  });

  group('point 3 : 5 000 morceaux', () {
    testWidgets(
      'la ligne choisie suit la molette et reste visible ; la liste ne construit que l\'écran',
      (tester) async {
        final fx = await pumpPhone(tester, home: const ClassicShell());
        await tester.runAsync(
          () => fx.db.upsertTracks([for (var i = 0; i < 5000; i++) _big(i)]),
        );
        await settle(tester);
        await tester.tap(find.text('Morceaux'));
        await settle(tester);
        expect(find.text('MORCEAUX'), findsOneWidget);

        final list = find.descendant(
          of: find.byType(ClassicMenu),
          matching: find.byType(ListView),
        );
        Rect visible() {
          final view = tester.getRect(list);
          final row = tester.getRect(
            find.byWidgetPredicate((w) => w is ClassicRow && w.selected),
          );
          expect(row.top, greaterThanOrEqualTo(view.top - .5));
          expect(row.bottom, lessThanOrEqualTo(view.bottom + .5));
          // seulement les lignes à l'écran (et un peu autour), jamais les 5 013
          expect(
            find.byType(ClassicRow, skipOffstage: false).evaluate().length,
            lessThan(40),
          );
          return row;
        }

        // la liste du mode normal (mêmes requêtes), pour savoir quelle ligne attendre
        final all = (await tester.runAsync(
          () => fx.db.watchAllTracks().first,
        ))!;
        expect(all.length, 5013);
        // un cran, une image : 300 fois ; chaque cran choisit la ligne suivante
        for (var i = 1; i <= 300; i++) {
          await rotate(tester, 1);
          visible();
          expect(selected(tester), all[i].title);
        }
        // un tour très rapide : beaucoup de crans entre deux images
        for (var i = 0; i < 15; i++) {
          await rotate(tester, 240);
          visible();
          expect(selected(tester), all[300 + 240 * (i + 1)].title);
        }
        // la fin de la liste, puis tout en haut
        await rotate(tester, 5000);
        expect(selected(tester), all.last.title);
        expect(visible().bottom, closeTo(tester.getRect(list).bottom, .5));
        await rotate(tester, -6000);
        expect(selected(tester), all.first.title);
        expect(visible().top, closeTo(tester.getRect(list).top, .5));
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('point 5 : téléphone couché', () {
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
      'couché : le Cover Flow du mode normal ; relevé : le menu, au même endroit',
      (tester) async {
        await pumpPhone(tester, home: const ClassicShell());
        await tester.tap(find.text('Albums'));
        await settle(tester);
        await rotate(tester, 1);
        await turn(tester, landscape: true);
        final flow = tester.widget<CoverflowScreen>(
          find.byType(CoverflowScreen),
        );
        expect(flow.phone, isTrue);
        expect(flow.albums.map((a) => a.name), [
          'Lafleur Surf',
          'Studio Lafleur',
          'Summer Mix',
        ]);
        expect(flow.initial, 1); // l'album en cours, comme le mode normal
        await turn(tester, landscape: false);
        expect(find.byType(CoverflowScreen), findsNothing);
        expect(find.text('ALBUMS'), findsOneWidget);
        expect(selected(tester), 'Studio Lafleur');
      },
    );

    testWidgets('en passant par AdaptiveHome (le réglage sur Classic)', (
      tester,
    ) async {
      await pumpPhone(
        tester,
        home: const AdaptiveHome(),
        classicMode: ValueNotifier(true),
      );
      expect(find.byType(ClassicMenu), findsOneWidget);
      await turn(tester, landscape: true);
      expect(find.byType(CoverflowScreen), findsOneWidget);
      await turn(tester, landscape: false);
      expect(find.byType(CoverflowScreen), findsNothing);
      expect(find.byType(ClassicMenu), findsOneWidget);
    });

    testWidgets(
      'couché, « Ouvrir l’album » : relevé, l’album dans le menu (pas l’écran du mode normal)',
      (tester) async {
        await pumpPhone(tester, home: const ClassicShell());
        await tester.tap(find.text('Artistes'));
        await settle(tester);
        await turn(tester, landscape: true);
        await tester.tap(find.text('Ouvrir l’album'));
        await tester.pumpAndSettle();
        await settle(tester);
        expect(find.byType(AlbumScreen), findsNothing);
        // le Cover Flow reste jusqu'au redressement
        expect(find.byType(CoverflowScreen), findsOneWidget);
        await turn(tester, landscape: false);
        expect(find.byType(CoverflowScreen), findsNothing);
        expect(find.byType(AlbumScreen), findsNothing);
        expect(find.byType(MiniPlayer), findsNothing);
        expect(find.text('STUDIO LAFLEUR'), findsOneWidget);
        expect(selected(tester), 'Ocean Drive');
        // MENU revient où on était
        await press(tester, 'menu');
        expect(find.text('ARTISTES'), findsOneWidget);
      },
    );

    testWidgets(
      'couché, « Ouvrir l’album » depuis Réglages : relevé, l’album dans le menu',
      (tester) async {
        await pumpPhone(tester, home: const ClassicShell());
        await rotateTo(tester, 'Réglages');
        await press(tester, 'select');
        await tester.pumpAndSettle();
        expect(find.byType(AccountsScreen), findsOneWidget);
        await turn(tester, landscape: true);
        await tester.tap(find.text('Ouvrir l’album'));
        await tester.pumpAndSettle();
        await settle(tester);
        await turn(tester, landscape: false);
        await tester.pumpAndSettle();
        expect(find.byType(AccountsScreen), findsNothing);
        expect(find.text('STUDIO LAFLEUR'), findsOneWidget);
      },
    );

    testWidgets('mode normal : « Ouvrir l’album » ouvre l’album, comme avant', (
      tester,
    ) async {
      await pumpPhone(tester);
      await turn(tester, landscape: true);
      await tester.tap(find.text('Ouvrir l’album'));
      await tester.pumpAndSettle();
      await settle(tester);
      expect(find.byType(AlbumScreen), findsOneWidget);
      expect(find.byType(CoverflowScreen), findsNothing);
    });

    testWidgets(
      'retour d’Android sous le Cover Flow : rien dans une liste, quitte à la racine',
      (tester) async {
        final pops = <String>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'SystemNavigator.pop') pops.add(call.method);
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        await pumpPhone(tester, home: const ClassicShell());
        await tester.tap(find.text('Albums'));
        await settle(tester);
        await turn(tester, landscape: true);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(pops, isEmpty); // l'appli ne part pas
        expect(find.byType(CoverflowScreen), findsOneWidget);
        await turn(tester, landscape: false);
        // rien défait sans qu'on le voie
        expect(find.text('ALBUMS'), findsOneWidget);
        // un album ouvert depuis le Cover Flow : pas la racine non plus
        await press(tester, 'menu');
        expect(find.text('MUSIQUE'), findsOneWidget);
        await turn(tester, landscape: true);
        await tester.tap(find.text('Ouvrir l’album'));
        await tester.pumpAndSettle();
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(pops, isEmpty);
        await turn(tester, landscape: false);
        expect(find.text('STUDIO LAFLEUR'), findsOneWidget);
        // à la racine : comme le mode normal sur l'Accueil, l'appli passe en arrière-plan
        await press(tester, 'menu');
        await turn(tester, landscape: true);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(pops, ['SystemNavigator.pop']);
      },
    );
  });

  group('« En cours » sans morceau', () {
    testWidgets('estompée, sans effet ; active dès qu’un morceau joue', (
      tester,
    ) async {
      final h = tester.ensureSemantics();
      final fx = await pumpPhone(tester, home: const ClassicShell());
      fx.player.show(const PlayerState());
      await tester.pump(); // l'annonce du lecteur
      await tester.pump(); // l'image qui suit
      expect(row(tester, 'En cours').dim, isTrue);
      expect(row(tester, 'En cours').onTap, isNull);
      expect(
        tester.getSemantics(find.text('En cours')),
        isSemantics(label: 'En cours', isButton: false, hasTapAction: false),
      );
      await rotateTo(tester, 'En cours');
      await press(tester, 'select');
      await tester.pumpAndSettle();
      expect(find.byType(ClassicNow), findsNothing);

      fx.player.show(
        PlayerState(
          track: DemoLibrary.playing,
          duration: Duration(milliseconds: DemoLibrary.playing.durationMs),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(row(tester, 'En cours').dim, isFalse);
      await press(tester, 'select');
      await tester.pumpAndSettle();
      expect(find.byType(ClassicNow), findsOneWidget);
      h.dispose();
    });
  });

  testWidgets('lecteur d’écran : la molette dit la ligne choisie', (
    tester,
  ) async {
    final h = tester.ensureSemantics();
    await pumpPhone(tester, home: const ClassicShell());
    expect(
      tester.getSemantics(find.byType(ClickWheel)),
      isSemantics(label: 'Molette', value: 'Cover Flow'),
    );
    await rotate(tester, 2);
    expect(
      tester.getSemantics(find.byType(ClickWheel)),
      isSemantics(label: 'Molette', value: 'Albums'),
    );
    h.dispose();
  });

  testWidgets('le réglage change l\'écran à chaud, sans toucher au lecteur', (
    tester,
  ) async {
    final mode = ValueNotifier(false);
    final fx = await pumpPhone(
      tester,
      home: const AdaptiveHome(),
      classicMode: mode,
    );
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(ClassicMenu), findsNothing);
    mode.value = true;
    await settle(tester);
    expect(find.byType(ClassicMenu), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
    mode.value = false;
    await settle(tester);
    expect(find.byType(HomeScreen), findsOneWidget);
    // rien pour la lecture ; seul le volume revient à fond en mode normal
    expect(fx.player.calls, ['volume']);
    expect(fx.player.volume, 100);
  });

  testWidgets(
    'petit téléphone (320 × 568) : rien ne déborde, la molette entière',
    (tester) async {
      await pumpPhone(tester, home: const ClassicShell());
      tester.view.physicalSize = const Size(320, 568);
      const pad = FakeViewPadding(top: 20);
      tester.view.padding = pad;
      tester.view.viewPadding = pad;
      await tester.pump();
      await settle(tester);
      expect(tester.takeException(), isNull);
      final w = tester.getRect(find.byType(ClickWheel));
      expect(w.bottom, lessThanOrEqualTo(568));
      expect(w.left, greaterThanOrEqualTo(0));
      expect(w.right, lessThanOrEqualTo(320));
      expect(w.width, greaterThan(150)); // encore une vraie molette
      // la liste montre toujours plusieurs lignes, et la molette marche
      expect(find.text('Albums').hitTestable(), findsOneWidget);
      await press(tester, 'select');
      expect(find.byType(CoverflowScreen), findsOneWidget);
    },
  );

  group('suivis', () {
    testWidgets('la langue change : le menu et les titres suivent', (
      tester,
    ) async {
      await pumpPhone(tester, home: const ClassicShell());
      await tester.tap(find.text('Artistes'));
      await settle(tester);
      expect(find.text('ARTISTES'), findsOneWidget);
      final old = tester.widget<AppScope>(find.byType(AppScope));
      await tester.pumpWidget(
        AppScope(
          db: old.db,
          player: old.player,
          covers: old.covers,
          strings: Strings.of(const Locale('en')),
          equalizer: old.equalizer,
          settings: old.settings,
          saveSettings: old.saveSettings,
          accounts: old.accounts,
          child: old.child,
        ),
      );
      await settle(tester);
      expect(find.text('ARTISTS'), findsOneWidget);
      await press(tester, 'menu');
      expect(find.text('MUSIC'), findsOneWidget);
      expect(selected(tester), 'Artists');
      for (final l in ['Cover Flow', 'Albums', 'Songs', 'On my phone']) {
        expect(find.text(l), findsOneWidget, reason: l);
      }
    });

    testWidgets(
      '« Sur mon téléphone » sans copies possibles : grisée, sans effet',
      (tester) async {
        await pumpPhone(
          tester,
          home: const ClassicShell(),
        ); // sans téléchargeur
        expect(row(tester, 'Sur mon téléphone').dim, isTrue);
        expect(row(tester, 'Albums').dim, isFalse);
        await tester.tap(find.text('Sur mon téléphone'));
        await settle(tester);
        expect(find.text('MUSIQUE'), findsOneWidget);
      },
    );

    testWidgets(
      'la liste change pendant qu\'on la parcourt : le même morceau reste choisi et visible',
      (tester) async {
        final fx = await pumpPhone(tester, home: const ClassicShell());
        await tester.tap(find.text('Morceaux'));
        await settle(tester);
        await rotateTo(tester, 'Ocean Drive');
        await tester.runAsync(
          () => fx.db.upsertTracks([
            for (var i = 0; i < 20; i++) _big(i, album: 'Aaa', title: 'Aaa $i'),
          ]),
        );
        await settle(tester);
        expect(selected(tester), 'Ocean Drive');
        final list = tester.getRect(
          find.descendant(
            of: find.byType(ClassicMenu),
            matching: find.byType(ListView),
          ),
        );
        final r = tester.getRect(
          find.byWidgetPredicate((w) => w is ClassicRow && w.selected),
        );
        expect(r.top, greaterThanOrEqualTo(list.top - .5));
        expect(r.bottom, lessThanOrEqualTo(list.bottom + .5));
        // il disparaît : la ligne au même rang (bornée)
        await tester.runAsync(
          () => fx.db.deletePaths([DemoLibrary.studio[0].path]),
        );
        await settle(tester);
        expect(selected(tester), isNot('Ocean Drive'));
      },
    );

    testWidgets(
      'pas sur le téléphone : grisé comme en mode normal, et le dire',
      (tester) async {
        final fx = await pumpKeep(tester, home: const ClassicShell());
        await tester.tap(find.text('Albums'));
        await settle(tester);
        await rotateTo(tester, 'Studio Lafleur');
        await press(tester, 'select');
        expect(row(tester, 'Night Swim').playable, isFalse);
        expect(row(tester, 'Ocean Drive').playable, isTrue);
        final grey = tester.widget<Text>(find.text('Night Swim'));
        expect(grey.style?.color, const Color(0xFF555555));
        await rotateTo(tester, 'Night Swim');
        // choisie : rose, comme la ligne choisie du mode normal
        expect(
          tester.widget<Text>(find.text('Night Swim')).style?.color,
          isNot(const Color(0xFF555555)),
        );
        await press(tester, 'select');
        expect(fx.player.calls, isNot(contains('play')));
        expect(
          find.text("Pas sur l'iPhone : rien à jouer hors ligne."),
          findsNothing,
        ); // Android dans les tests
        expect(
          find.text('Pas sur le téléphone : rien à jouer hors ligne.'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'VoiceOver / TalkBack : « pas sur le téléphone » dit avant de toucher',
      (tester) async {
        final h = tester.ensureSemantics();
        await pumpKeep(tester, home: const ClassicShell());
        await tester.tap(find.text('Albums'));
        await settle(tester);
        await rotateTo(tester, 'Studio Lafleur');
        await press(tester, 'select');
        expect(
          tester.getSemantics(find.text('Night Swim')),
          isSemantics(
            label: 'Night Swim',
            hint: 'Kavinsky · pas sur le téléphone',
            isButton: true,
            hasTapAction: true,
          ),
        );
        expect(
          tester.getSemantics(find.text('Ocean Drive')),
          isSemantics(label: 'Ocean Drive', hint: '', isButton: true),
        );
        h.dispose();
      },
    );

    testWidgets('une ligne sans effet (grisée) n\'est pas un bouton', (
      tester,
    ) async {
      final h = tester.ensureSemantics();
      await pumpPhone(tester, home: const ClassicShell()); // sans téléchargeur
      expect(
        tester.getSemantics(find.text('Sur mon téléphone')),
        isSemantics(
          label: 'Sur mon téléphone',
          isButton: false,
          hasTapAction: false,
        ),
      );
      h.dispose();
    });
  });
}
