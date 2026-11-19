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
import 'package:lafleurmusic/player/queue.dart';
import 'package:lafleurmusic/theme/lafleur_theme.dart';
import 'package:lafleurmusic/ui/queue_toast.dart';

import 'fake_player.dart';
import 'fonts.dart';

Future<List<String>> pumpToast(
  WidgetTester tester, {
  Locale locale = const Locale('fr'),
  FakePlayer? player,
  List<Track>? enqueue,
}) async {
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
  final calls = <String>[];
  await tester.pumpWidget(
    AppScope(
      db: db,
      player: player ?? FakePlayer(),
      covers: Covers(
        cacheDir: Directory.systemTemp.createTempSync('c'),
        embedded: (_) async => null,
      ),
      strings: Strings.of(locale),
      child: MaterialApp(
        theme: lafleurTheme(),
        home: Builder(
          builder: (ctx) => Scaffold(
            body: TextButton(
              onPressed: () => enqueue != null
                  ? enqueueWithToast(ctx, enqueue)
                  : showQueueToast(
                      ctx,
                      count: 2,
                      onUndo: () => calls.add('undo'),
                      onShowQueue: () => calls.add('queue'),
                    ),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    ),
  );
  return calls;
}

void main() {
  setUpAll(loadFonts);

  testWidgets('la bulle : texte, Annuler, Voir la file', (tester) async {
    await pumpToast(tester);
    await tester.tap(find.text('go'));
    await tester.pump();
    expect(find.text('✓ Ajouté à la file'), findsOneWidget);
    expect(find.text('Annuler'), findsOneWidget);
    expect(find.text('Voir la file'), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 5));
  });

  testWidgets('en anglais', (tester) async {
    await pumpToast(tester, locale: const Locale('en'));
    await tester.tap(find.text('go'));
    await tester.pump();
    expect(find.text('✓ Added to queue'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);
    expect(find.text('View queue'), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 5));
  });

  testWidgets('elle part seule après 4 s, pas avant', (tester) async {
    await pumpToast(tester);
    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 3900));
    expect(find.byKey(const Key('queueToast')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const Key('queueToast')), findsNothing);
  });

  testWidgets('Annuler : l’appel, et la bulle part', (tester) async {
    final calls = await pumpToast(tester);
    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.tap(find.text('Annuler'));
    await tester.pump();
    expect(calls, ['undo']);
    expect(find.byKey(const Key('queueToast')), findsNothing);
    await tester.pump(
      const Duration(seconds: 5),
    ); // le minuteur ne rappelle rien
    expect(calls, ['undo']);
  });

  testWidgets('Voir la file : l’appel, et la bulle part', (tester) async {
    final calls = await pumpToast(tester);
    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.tap(find.text('Voir la file'));
    await tester.pump();
    expect(calls, ['queue']);
    expect(find.byKey(const Key('queueToast')), findsNothing);
  });

  testWidgets('une 2e bulle remplace la 1re et repart à 4 s', (tester) async {
    await pumpToast(tester);
    await tester.tap(find.text('go'));
    await tester.pump(const Duration(seconds: 3));
    await tester.tap(find.text('go'));
    await tester.pump();
    expect(find.byKey(const Key('queueToast')), findsOneWidget);
    await tester.pump(
      const Duration(seconds: 3),
    ); // 3 s après la 2e : encore là
    expect(find.byKey(const Key('queueToast')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1100));
    expect(find.byKey(const Key('queueToast')), findsNothing);
  });

  const song = Track(
    path: '/m/x.mp3',
    accountId: 'local',
    remoteId: '',
    title: 'X',
    artist: 'A',
    album: 'B',
    durationMs: 1000,
    hasCover: false,
    size: 1,
  );

  testWidgets('file vide : le morceau démarre, pas de bulle', (tester) async {
    final p = FakePlayer();
    await pumpToast(tester, player: p, enqueue: [song]);
    await tester.tap(find.text('go'));
    await tester.pump();
    expect(p.calls, contains('enqueue'));
    expect(find.byKey(const Key('queueToast')), findsNothing);
  });

  testWidgets('file qui joue : la bulle', (tester) async {
    final p = FakePlayer()..queue = PlayQueue<Track>([song], index: 0);
    await pumpToast(tester, player: p, enqueue: [song]);
    await tester.tap(find.text('go'));
    await tester.pump();
    expect(find.byKey(const Key('queueToast')), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 5));
  });
}
