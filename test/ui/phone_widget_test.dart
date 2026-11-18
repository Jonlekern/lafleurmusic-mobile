import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/demo/demo_library.dart';
import 'package:lafleurmusic/ui/equalizer_panel.dart';
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

  test('moins de 900 px : téléphone ; sinon les colonnes du Mac', () {
    expect(AdaptiveHome.isPhone(const Size(390, 844)), isTrue);
    expect(AdaptiveHome.isPhone(const Size(899, 600)), isTrue);
    expect(AdaptiveHome.isPhone(const Size(900, 600)), isFalse);
    expect(AdaptiveHome.isPhone(const Size(1440, 900)), isFalse);
  });
}
