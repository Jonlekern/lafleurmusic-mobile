// Vérification jetable des briques (plan 1, tâche 0) : lecture mpv et tags TagLib sur le Mac.
import 'dart:async';
import 'dart:io';

import 'package:flutter_taglib/flutter_taglib.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';
import 'package:lafleurmusic/player/loudness_probe.dart';

const fixtures = String.fromEnvironment('FIXTURES');

/// Un seul lecteur pour les essais mpv, sans sortie son : ouvrir et fermer CoreAudio à répétition
/// fait planter mpv_audio_kit sur le Mac (voir LafleurPlayer).
Player? _quiet;
Future<Player> quietPlayer() async {
  if (_quiet == null) {
    _quiet = Player(
      configuration: const PlayerConfiguration(
        autoPlay: true,
        initialVolume: 0,
      ),
    );
    await _quiet!.setRawProperty('ao', 'null');
  }
  return _quiet!;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MpvAudioKit.ensureInitialized();

  for (final name in [
    'a.flac',
    'a.mp3',
    'a.m4a',
    'a.opus',
    'a.wv',
    'a.tta',
    'a.aiff',
  ]) {
    testWidgets('mpv lit $name', (tester) async {
      final player = await quietPlayer();
      final dur = Completer<Duration>();
      final sub = player.stream.duration.listen((d) {
        if (d > Duration.zero && !dur.isCompleted) dur.complete(d);
      });
      await player.open(Media('$fixtures/$name'));
      final d = await tester.runAsync(
        () => dur.future.timeout(const Duration(seconds: 10)),
      );
      expect(d!.inMilliseconds, inInclusiveRange(2500, 3500));
      await sub.cancel();
      await player.pause(); // pas de dispose : fermer un lecteur peut faire planter mpv_audio_kit (CoreAudio)
    });
  }

  testWidgets('mpv signale un fichier cassé', (tester) async {
    final player = await quietPlayer();
    final err = Completer<void>();
    final s1 = player.stream.error.listen((_) {
      if (!err.isCompleted) err.complete();
    });
    await player.open(Media('$fixtures/broken.flac'));
    await tester.runAsync(
      () => err.future.timeout(const Duration(seconds: 10)),
    );
    await s1.cancel();
    await player.pause(); // pas de dispose : fermer un lecteur peut faire planter mpv_audio_kit (CoreAudio)
  });

  for (final name in ['a.flac', 'a.mp3', 'a.m4a', 'a.opus', 'a.wv']) {
    testWidgets('TagLib lit $name', (tester) async {
      expect(TagLibFile.isSupported, true);
      final f = TagLibFile.open('$fixtures/$name');
      expect(f, isNotNull);
      expect(f!.title, 'Ocean_Drive');
      expect(f.artist, 'Johnny');
      expect(f.album, 'Studio_Lafleur');
      expect(f.duration.inMilliseconds, inInclusiveRange(2500, 3500));
      f.close();
    });
  }

  testWidgets('dossier support accessible', (tester) async {
    expect(Directory(fixtures).existsSync(), true);
  });

  // plan 5, tâche 1 : Corbeille et mesure EBU R128
  testWidgets('mesure EBU R128 d\'un sinus à −20 LUFS', (tester) async {
    final sw = Stopwatch()..start();
    final lufs = await tester.runAsync(
      () => measureLoudness('$fixtures/tone-20.wav'),
    );
    sw.stop();
    expect(lufs, isNotNull);
    expect(lufs!, closeTo(-20, 0.5));
    expect(sw.elapsed, lessThan(const Duration(seconds: 5)));
  });

  testWidgets('mesure d\'un fichier cassé → null', (tester) async {
    final lufs = await tester.runAsync(
      () => measureLoudness('$fixtures/broken.flac'),
    );
    expect(lufs, isNull);
  });
}
