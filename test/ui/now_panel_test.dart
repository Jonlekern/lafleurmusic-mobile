import 'dart:io';

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/app_scope.dart';
import 'package:lafleurmusic/l10n/strings.dart';
import 'package:lafleurmusic/library/covers.dart';
import 'package:lafleurmusic/library/db.dart';
import 'package:lafleurmusic/library/models.dart';
import 'package:lafleurmusic/player/player.dart';
import 'package:lafleurmusic/player/queue.dart';
import 'package:lafleurmusic/theme/lafleur_theme.dart';
import 'package:lafleurmusic/ui/now_panel.dart';

import 'fake_player.dart';
import 'fonts.dart';

Track t(
  String title, {
  String artist = 'Divers',
  String album = 'Studio Lafleur',
}) => Track(
  path: '/m/$title.flac',
  folderId: 1,
  title: title,
  artist: artist,
  album: album,
  durationMs: 1,
  hasCover: false,
  mtime: 1,
  size: 1,
);

late FakePlayer player;

Future<void> pump(WidgetTester tester, {bool added = true}) async {
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
  player = FakePlayer();
  final q = PlayQueue([
    t('Lafleur Surf', artist: 'LAFLEURSTUDIO'),
    t('Golden Hour'),
    t('Night Swim', artist: 'Kavinsky'),
    t('Paradise Club'),
  ]);
  if (added) {
    q.enqueue([
      t('Nightcall', artist: 'Kavinsky', album: 'Night Drive'),
      t('Sunset Tape'),
    ]);
  }
  player.queue = q;
  player.current = PlayerState(track: q.current);
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
        home: const Scaffold(body: Row(children: [Spacer(), NowPanel()])),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('2 ajouts sous AJOUTÉS PAR TOI, puis la suite de l’album', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('AJOUTÉS PAR TOI'), findsOneWidget);
    expect(find.text("SUITE DE L'ALBUM"), findsOneWidget);
    expect(find.text('Vider'), findsOneWidget);
    double y(String s) => tester.getTopLeft(find.text(s)).dy;
    expect(y('Nightcall') < y('Sunset Tape'), isTrue);
    expect(y('Sunset Tape') < y("SUITE DE L'ALBUM"), isTrue);
    expect(y("SUITE DE L'ALBUM") < y('Golden Hour'), isTrue);
  });

  testWidgets('✕ retire la ligne (sa place dans la file)', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('upnext-remove-2'))); // Sunset Tape
    await tester.pump();
    expect(player.calls, ['remove']);
    expect(find.text('Sunset Tape'), findsNothing);
  });

  testWidgets('glisser le 2e ajout en tête → moveUpcoming', (tester) async {
    await pump(tester);
    final from = tester.getCenter(find.byKey(const Key('upnext-grip-2')));
    final to = tester.getCenter(find.text('Nightcall'));
    final g = await tester.startGesture(from);
    await g.moveBy(const Offset(0, -5));
    await tester.pump();
    await g.moveTo(to - const Offset(0, 10));
    await tester.pump();
    await g.up();
    await tester.pump();
    expect(player.calls, ['move 2 1']);
    expect(player.queue!.added.first.title, 'Sunset Tape');
  });

  testWidgets('Vider → clearAdded', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Vider'));
    await tester.pump();
    expect(player.calls, ['clearAdded']);
    expect(find.text('AJOUTÉS PAR TOI'), findsNothing);
  });

  testWidgets('sans ajouts : ni AJOUTÉS ni Vider', (tester) async {
    await pump(tester, added: false);
    expect(find.text('AJOUTÉS PAR TOI'), findsNothing);
    expect(find.text('Vider'), findsNothing);
    expect(find.text('Golden Hour'), findsOneWidget);
  });
}
