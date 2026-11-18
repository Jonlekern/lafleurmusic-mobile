import 'dart:io';

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/app_scope.dart';
import 'package:lafleurmusic/l10n/strings.dart';
import 'package:lafleurmusic/library/covers.dart';
import 'package:lafleurmusic/library/db.dart';
import 'package:lafleurmusic/player/loudness.dart';
import 'package:lafleurmusic/settings.dart';
import 'package:lafleurmusic/theme/lafleur_theme.dart';
import 'package:lafleurmusic/ui/playback_card.dart';

import 'fake_player.dart';
import 'fonts.dart';

void main() {
  late AppSettings settings;
  late int saves;
  late LoudnessService loud;

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
      loud.dispose();
      await tester.runAsync(db.close);
    });
    settings = AppSettings();
    saves = 0;
    final player = FakePlayer();
    loud = LoudnessService(db, player, measure: (_) async => null);
    await tester.pumpWidget(
      AppScope(
        db: db,
        player: player,
        covers: Covers(
          cacheDir: Directory.systemTemp.createTempSync('c'),
          embedded: (_) async => null,
        ),
        strings: Strings.of(const Locale('fr')),
        settings: settings,
        saveSettings: () => saves++,
        loudness: loud,
        child: MaterialApp(
          theme: lafleurTheme(),
          home: const Scaffold(
            body: SizedBox(width: 790, child: PlaybackCard()),
          ),
        ),
      ),
    );
  }

  testWidgets('textes de la maquette 9b, éteints au départ', (tester) async {
    await pump(tester);
    expect(find.text('Lecture'), findsOneWidget);
    expect(find.text('Volume égal'), findsOneWidget);
    expect(
      find.text(
        'Tous les morceaux au même niveau sonore (ReplayGain). Mesuré une fois par morceau, puis gardé.',
      ),
      findsOneWidget,
    );
    expect(find.text('Fondu enchaîné'), findsOneWidget);
    expect(
      find.text("La fin d'un morceau se fond dans le début du suivant."),
      findsOneWidget,
    );
    expect(find.text('5 s'), findsOneWidget);
    expect(
      tester.widget<Slider>(find.byType(Slider)).onChanged,
      isNull,
    ); // grisé
  });

  testWidgets('Volume égal allumé : réglage enregistré, service actif', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('equal-volume')));
    await tester.pump();
    expect(settings.equalVolume, isTrue);
    expect(loud.enabled, isTrue);
    expect(saves, 1);
  });

  testWidgets('Fondu enchaîné allumé puis 8 s', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('crossfade')));
    await tester.pump();
    expect(settings.crossfade, isTrue);
    final slider = tester.widget<Slider>(find.byType(Slider));
    slider.onChanged!(8);
    slider.onChangeEnd!(8);
    await tester.pump();
    expect(settings.crossfadeSeconds, 8);
    expect(find.text('8 s'), findsOneWidget);
    expect(saves, 2);
  });
}
