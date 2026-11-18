import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/library/db.dart';
import 'package:lafleurmusic/library/models.dart';
import 'package:lafleurmusic/library/play_counter.dart';
import 'package:lafleurmusic/player/player.dart';

Track t(String path, {bool missing = false, int ms = 300000}) => Track(
  path: path,
  folderId: 1,
  title: path,
  artist: 'a',
  album: 'A',
  durationMs: ms,
  hasCover: false,
  mtime: 1,
  size: 1,
  missing: missing,
);

void main() {
  late LibraryDb db;
  setUp(() => db = LibraryDb(NativeDatabase.memory()));
  tearDown(() => db.close());

  test(
    'Top : plus écoutés d’abord, égalité → écouté le plus récemment',
    () async {
      await db.upsertTracks([
        t('/a'),
        t('/b'),
        t('/c'),
        t('/gone', missing: true),
      ]);
      await db.addPlay('/a', DateTime(2026, 1, 1));
      await db.addPlay('/b', DateTime(2026, 1, 2));
      await db.addPlay('/c', DateTime(2026, 1, 1));
      await db.addPlay('/c', DateTime(2026, 1, 3));
      await db.addPlay('/gone', DateTime(2026, 1, 4));
      final top = await db.watchTop(100).first;
      expect(
        [for (final r in top) (r.$1.path, r.$2)],
        [('/c', 2), ('/b', 1), ('/a', 1)],
      );
    },
  );

  test('movePlays transfère, deletePaths efface compteur et mesure', () async {
    await db.upsertTracks([t('/a'), t('/b')]);
    await db.addPlay('/a', DateTime(2026));
    await db.addPlay('/a', DateTime(2026));
    await db.movePlays('/a', '/b');
    expect((await db.watchTop(10).first).single.$2, 2);
    await db.setLoudness('/b', -12.5, 1);
    expect(await db.loudnessOf('/b', 1), -12.5);
    expect(await db.loudnessOf('/b', 2), isNull); // fichier modifié
    await db.deletePaths(['/b']);
    expect(await db.watchTop(10).first, isEmpty);
    expect(await db.loudnessOf('/b', 1), isNull);
  });

  test('mesure « non mesurable » gardée (lufs null)', () async {
    await db.setLoudness('/x', null, 3);
    expect(await db.hasLoudness('/x', 3), isTrue);
    expect(await db.loudnessOf('/x', 3), isNull);
    expect(await db.hasLoudness('/x', 4), isFalse);
  });

  group('compteur d’écoutes', () {
    late StreamController<PlayerState> ctrl;
    late PlayCounter counter;
    setUp(() async {
      ctrl = StreamController<PlayerState>();
      counter = PlayCounter(ctrl.stream, db, now: () => DateTime(2026, 10, 17));
      await db.upsertTracks([t('/a'), t('/long', ms: 720000)]);
    });
    tearDown(() => counter.dispose());

    Future<int> plays(String p) async {
      await Future<void>.delayed(Duration.zero);
      final top = await db.watchTop(10).first;
      return top.where((r) => r.$1.path == p).map((r) => r.$2).firstOrNull ?? 0;
    }

    PlayerState s(Track tr, int seconds, {int dur = 300}) => PlayerState(
      track: tr,
      position: Duration(seconds: seconds),
      duration: Duration(seconds: dur),
      playing: true,
    );

    test('3 min sur 5 → +1', () async {
      ctrl.add(s(t('/a'), 10));
      ctrl.add(s(t('/a'), 180));
      expect(await plays('/a'), 1);
    });
    test('4 min sur 12 → +1', () async {
      ctrl
        ..add(s(t('/long'), 5, dur: 720))
        ..add(s(t('/long'), 240, dur: 720));
      expect(await plays('/long'), 1);
    });
    test('1 min sur 5 → 0', () async {
      ctrl.add(s(t('/a'), 60));
      expect(await plays('/a'), 0);
    });
    test('aller-retour au-delà du seuil → toujours 1', () async {
      ctrl
        ..add(s(t('/a'), 5))
        ..add(s(t('/a'), 180))
        ..add(s(t('/a'), 120))
        ..add(s(t('/a'), 200));
      expect(await plays('/a'), 1);
    });
    test('1er état d’un nouveau morceau avec la position de l’ancien : pas d’écoute', () async {
      ctrl
        ..add(s(t('/a'), 5))
        ..add(s(t('/a'), 280)) // A écouté 4:40 → +1
        ..add(
          s(t('/long'), 280, dur: 720),
        ) // Suivant : B arrive avec la position de A
        ..add(s(t('/long'), 1, dur: 720))
        ..add(s(t('/long'), 30, dur: 720));
      expect(await plays('/long'), 0);
      ctrl.add(s(t('/long'), 245, dur: 720));
      expect(await plays('/long'), 1);
    });
    test('rejoué depuis le début → 2', () async {
      ctrl
        ..add(s(t('/a'), 5))
        ..add(s(t('/a'), 180))
        ..add(s(t('/a'), 0))
        ..add(s(t('/a'), 200));
      expect(await plays('/a'), 2);
    });
  });
}
