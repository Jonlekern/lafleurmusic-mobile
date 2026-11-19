import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/player/player.dart';
import 'package:lafleurmusic/settings.dart';
import 'package:lafleurmusic/ui/classic/classic_menu.dart';
import 'package:lafleurmusic/ui/classic/classic_now.dart';
import 'package:lafleurmusic/ui/classic/classic_shell.dart';
import 'package:lafleurmusic/ui/phone/accounts_screen.dart';
import 'package:lafleurmusic/ui/phone/home_screen.dart';
import 'package:lafleurmusic/ui/phone/now_screen.dart';
import 'package:lafleurmusic/ui/phone/phone_shell.dart' show AdaptiveHome;
import 'package:lafleurmusic/ui/tablet.dart';

import '../fonts.dart';
import '../phone_fixture.dart';
import 'classic_shell_test.dart' show press, rotate, rotateTo, selected;

const _scrubCaption = '◆ Tourne pour avancer dans le morceau';

/// Le Mode Classic, En cours ouvert depuis le menu.
Future<PhoneFixture> openClassic(WidgetTester tester) async {
  final fx = await pumpPhone(tester, home: const ClassicShell());
  await rotateTo(tester, 'En cours');
  await press(tester, 'select');
  await tester.pumpAndSettle();
  expect(find.byType(ClassicNow), findsOneWidget);
  return fx;
}

double volumeBar(WidgetTester tester) => tester
    .widget<FractionallySizedBox>(find.byKey(const Key('classic-now-volume')))
    .widthFactor!;

bool scrubbing(WidgetTester tester) =>
    find.byKey(const Key('classic-now-diamond')).evaluate().isNotEmpty;

void main() {
  setUpAll(loadFonts);

  testWidgets('maquette 12 A : EN COURS, n sur m, le morceau, les temps', (
    tester,
  ) async {
    final fx = await openClassic(tester);
    expect(find.text('EN COURS'), findsOneWidget);
    final q = fx.player.queue!;
    expect(find.text('${q.position + 1} sur ${q.order.length}'), findsOne);
    expect(find.text('Lafleur Surf'), findsOneWidget);
    expect(find.text('LAFLEURSTUDIO'), findsOneWidget);
    expect(find.text('Studio Lafleur'), findsOneWidget);
    expect(find.text('1:33'), findsOneWidget);
    expect(find.text('−2:32'), findsOneWidget);
    expect(find.text(_scrubCaption), findsNothing);
    expect(scrubbing(tester), isFalse);
    // pas de mini-lecteur, pas l'En cours du mode normal
    expect(find.byType(NowScreen), findsNothing);
  });

  testWidgets('tourner = volume, par pas de 5, de 0 à 100', (tester) async {
    final fx = await openClassic(tester);
    expect(fx.player.volume, 75);
    expect(volumeBar(tester), closeTo(.75, 1e-9));
    await rotate(tester, 1);
    expect(fx.player.volume, 80);
    expect(volumeBar(tester), closeTo(.80, 1e-9));
    await rotate(tester, -3);
    expect(fx.player.volume, 65);
    await rotate(tester, 30);
    expect(fx.player.volume, 100);
    expect(volumeBar(tester), 1);
    await rotate(tester, -40);
    expect(fx.player.volume, 0);
    expect(volumeBar(tester), 0);
    // déjà au bout : le lecteur n'est plus dérangé
    final n = fx.player.calls.length;
    await rotate(tester, -1);
    expect(fx.player.calls.length, n);
    expect(fx.player.calls, isNot(contains('seek')));
  });

  testWidgets(
    'appui au milieu : avancer dans le morceau (5 s par cran), losange et texte rose',
    (tester) async {
      final fx = await openClassic(tester);
      await press(tester, 'select');
      expect(scrubbing(tester), isTrue);
      expect(find.text(_scrubCaption), findsOneWidget);
      expect(find.byKey(const Key('classic-now-volume')), findsNothing);
      await rotate(tester, 2);
      expect(fx.player.lastSeek, const Duration(seconds: 103));
      expect(find.text('1:43'), findsOneWidget); // le losange et le temps suivent
      await rotate(tester, -1);
      expect(fx.player.lastSeek, const Duration(seconds: 98));
      await rotate(tester, -100);
      expect(fx.player.lastSeek, Duration.zero);
      await rotate(tester, 200);
      expect(fx.player.lastSeek, const Duration(seconds: 245));
      expect(fx.player.volume, 75); // le volume n'a pas bougé
      expect(fx.player.calls, isNot(contains('volume')));
      // un nouvel appui : retour au volume
      await press(tester, 'select');
      expect(scrubbing(tester), isFalse);
      expect(find.text(_scrubCaption), findsNothing);
      await rotate(tester, 1);
      expect(fx.player.volume, 80);
    },
  );

  testWidgets('3 s sans toucher la molette : retour au volume', (
    tester,
  ) async {
    final fx = await openClassic(tester);
    await press(tester, 'select');
    expect(scrubbing(tester), isTrue);
    await tester.pump(const Duration(seconds: 2));
    await rotate(tester, 1); // la molette touchée : les 3 s repartent
    await tester.pump(const Duration(seconds: 2));
    expect(scrubbing(tester), isTrue);
    await tester.pump(const Duration(milliseconds: 1001));
    expect(scrubbing(tester), isFalse);
    expect(find.text(_scrubCaption), findsNothing);
    await rotate(tester, -1);
    expect(fx.player.volume, 70);
    expect(fx.player.calls.where((c) => c == 'seek').length, 1);
  });

  testWidgets('⏮ ⏭ ▶︎❙❙ commandent le lecteur ; MENU revient au menu', (
    tester,
  ) async {
    final fx = await openClassic(tester);
    await press(tester, 'previous');
    await press(tester, 'next');
    await press(tester, 'play');
    expect(fx.player.calls, ['previous', 'next', 'toggle']);
    await press(tester, 'menu');
    await tester.pumpAndSettle();
    expect(find.byType(ClassicNow), findsNothing);
    expect(find.text('MUSIQUE'), findsOneWidget);
    expect(selected(tester), 'En cours');
  });

  testWidgets('la file change : n sur m et le morceau suivent', (
    tester,
  ) async {
    final fx = await openClassic(tester);
    await fx.player.jumpTo(3);
    final q = fx.player.queue!;
    fx.player.show(
      PlayerState(
        track: q.current,
        duration: const Duration(seconds: 301),
        playing: true,
      ),
    );
    await tester.pump(); // l'annonce du lecteur
    await tester.pump(); // l'image qui suit
    expect(find.text('${q.position + 1} sur ${q.order.length}'), findsOne);
    expect(q.position, isNot(1));
    expect(find.text(q.current!.title), findsOneWidget);
    expect(find.text('−5:01'), findsOneWidget);
  });

  testWidgets('rien en cours : la carte vide, rien ne casse', (tester) async {
    final fx = await pumpPhone(tester, home: const ClassicShell());
    fx.player
      ..queue = null
      ..current = const PlayerState();
    await rotateTo(tester, 'En cours');
    await press(tester, 'select');
    await tester.pumpAndSettle();
    expect(find.text('EN COURS'), findsOneWidget);
    expect(find.textContaining(' sur '), findsNothing);
    expect(find.text('0:00'), findsOneWidget);
    // pas de morceau : rien où avancer, le milieu ne change rien
    await press(tester, 'select');
    expect(scrubbing(tester), isFalse);
    await rotate(tester, 1);
    expect(fx.player.volume, 80);
    expect(tester.takeException(), isNull);
  });

  testWidgets('petit téléphone (320 × 568) : rien ne déborde', (tester) async {
    await openClassic(tester);
    tester.view.physicalSize = const Size(320, 568);
    const pad = FakeViewPadding(top: 20);
    tester.view.padding = pad;
    tester.view.viewPadding = pad;
    await tester.pump();
    await settle(tester);
    expect(tester.takeException(), isNull);
  });

  group('choisir un morceau dans une liste', () {
    testWidgets('ouvre En cours ; MENU revient à la liste', (tester) async {
      final fx = await pumpPhone(tester, home: const ClassicShell());
      await tester.tap(find.text('Albums'));
      await settle(tester);
      await rotateTo(tester, 'Studio Lafleur');
      await press(tester, 'select');
      await rotate(tester, 2);
      await press(tester, 'select');
      await tester.pumpAndSettle();
      expect(fx.player.lastIndex, 2);
      expect(find.byType(ClassicNow), findsOneWidget);
      await press(tester, 'menu');
      await tester.pumpAndSettle();
      expect(find.byType(ClassicNow), findsNothing);
      expect(find.text('STUDIO LAFLEUR'), findsOneWidget);
      expect(selected(tester), 'Golden Hour');
    });

    testWidgets('un toucher sur la ligne aussi', (tester) async {
      await pumpPhone(tester, home: const ClassicShell());
      await tester.tap(find.text('Morceaux'));
      await settle(tester);
      await tester.tap(find.text('Heatwave'));
      await settle(tester);
      await tester.pumpAndSettle();
      expect(find.byType(ClassicNow), findsOneWidget);
    });
  });

  group('Réglages › AFFICHAGE : Mode normal / Mode Classic', () {
    const caption =
        "Mode Classic : un menu comme l'iPod et une molette à tourner du doigt. "
        'Ta musique et ta file ne changent pas.';

    testWidgets('le choix change le réglage, en premier dans AFFICHAGE', (
      tester,
    ) async {
      final mode = ValueNotifier(false);
      await pumpPhone(
        tester,
        home: const AccountsScreen(),
        classicMode: mode,
      );
      expect(find.text('AFFICHAGE'), findsOneWidget);
      expect(find.text('Mode normal'), findsOneWidget);
      expect(find.text(caption), findsOneWidget);
      // en premier : sous le titre, avant Un compte / Tout / Perso
      final head = tester.getRect(find.text('AFFICHAGE'));
      final seg = tester.getRect(find.text('Mode Classic'));
      final display = tester.getRect(find.text('Un compte'));
      expect(seg.top, greaterThan(head.bottom));
      expect(seg.bottom, lessThan(display.top));
      await tester.tap(find.text('Mode Classic'));
      await tester.pump();
      expect(mode.value, isTrue);
      await tester.tap(find.text('Mode normal'));
      await tester.pump();
      expect(mode.value, isFalse);
    });

    testWidgets('gardé : le choix revient au lancement suivant', (
      tester,
    ) async {
      // comme main.dart : le réglage suit le choix et s'enregistre
      final dir = await tester.runAsync(
        () => Directory.systemTemp.createTemp('classic'),
      );
      addTearDown(() => dir!.deleteSync(recursive: true));
      final file = File('${dir!.path}/settings.json');
      final settings = AppSettings();
      final mode = ValueNotifier(settings.classicMode);
      mode.addListener(() => settings.classicMode = mode.value);
      await pumpPhone(
        tester,
        home: const AccountsScreen(),
        classicMode: mode,
      );
      await tester.tap(find.text('Mode Classic'));
      await tester.pump();
      final loaded = await tester.runAsync(() async {
        await settings.save(file);
        return AppSettings.load(file);
      });
      expect(loaded!.classicMode, isTrue);
    });

    testWidgets('pas sur une tablette (le Mode Classic ne s\'y applique pas)', (
      tester,
    ) async {
      await pumpPhone(
        tester,
        home: const AccountsScreen(),
        classicMode: ValueNotifier(false),
      );
      setTabletMode(true);
      addTearDown(() => setTabletMode(false));
      tester.view.physicalSize = const Size(820, 1180);
      await tester.pump();
      expect(find.text('AFFICHAGE'), findsOneWidget);
      expect(find.text('Mode Classic'), findsNothing);
      expect(find.text(caption), findsNothing);
    });

    testWidgets('sans réglage (démo) : pas de choix', (tester) async {
      await pumpPhone(tester, home: const AccountsScreen());
      expect(find.text('Mode Classic'), findsNothing);
    });
  });

  // point 4 de la revue
  testWidgets(
    'Classic → normal → Classic pendant la lecture : la musique continue, la même file',
    (tester) async {
      final mode = ValueNotifier(true);
      final fx = await pumpPhone(
        tester,
        home: const AdaptiveHome(),
        classicMode: mode,
      );
      // en Mode Classic, un morceau choisi : il joue, En cours s'ouvre
      await tester.tap(find.text('Albums'));
      await settle(tester);
      await rotateTo(tester, 'Studio Lafleur');
      await press(tester, 'select');
      await rotate(tester, 3);
      await press(tester, 'select');
      await tester.pumpAndSettle();
      expect(find.byType(ClassicNow), findsOneWidget);
      final queue = fx.player.queue!;
      final order = [...queue.order];
      final pos = queue.position;
      fx.player.show(
        PlayerState(
          track: queue.current,
          position: const Duration(seconds: 61),
          duration: const Duration(seconds: 301),
          playing: true,
        ),
      );
      await tester.pump();
      final calls = [...fx.player.calls];

      Future<void> choose(String label) async {
        await tester.tap(find.text(label));
        await settle(tester);
        await tester.pumpAndSettle();
      }

      // MENU, Réglages, Mode normal
      await press(tester, 'menu');
      await tester.pumpAndSettle();
      await press(tester, 'menu');
      await press(tester, 'menu');
      await rotateTo(tester, 'Réglages');
      await press(tester, 'select');
      await tester.pumpAndSettle();
      await choose('Mode normal');
      expect(mode.value, isFalse);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(ClassicMenu), findsNothing);
      // le lecteur n'a rien reçu : toujours en lecture, même file, même endroit
      expect(fx.player.calls, calls);
      expect(identical(fx.player.queue, queue), isTrue);
      expect(queue.order, order);
      expect(queue.position, pos);
      expect(fx.player.current.playing, isTrue);
      expect(fx.player.current.position, const Duration(seconds: 61));
      // l'En cours du mode normal montre le même morceau, au même endroit
      openNow(tester.element(find.byType(HomeScreen)));
      await tester.pumpAndSettle();
      expect(find.text('Night Swim'), findsWidgets);
      expect(find.text('1:01'), findsOneWidget);
      Navigator.of(tester.element(find.byType(NowScreen))).pop();
      await tester.pumpAndSettle();

      // et retour en Mode Classic par Réglages
      await tester.tap(find.byIcon(Icons.settings_rounded));
      await tester.pumpAndSettle();
      await choose('Mode Classic');
      expect(mode.value, isTrue);
      expect(find.byType(ClassicMenu), findsOneWidget);
      expect(fx.player.calls, calls);
      expect(identical(fx.player.queue, queue), isTrue);
      expect(queue.order, order);
      expect(queue.position, pos);
      expect(fx.player.current.playing, isTrue);
      await rotateTo(tester, 'En cours');
      await press(tester, 'select');
      await tester.pumpAndSettle();
      expect(find.text('Night Swim'), findsOneWidget);
      expect(find.text('1:01'), findsOneWidget);
      expect(find.text('${pos + 1} sur ${order.length}'), findsOneWidget);
    },
  );
}
