// Essai du lecteur sur le Mac (plan 1, tâche 5, étape 6) : un fichier illisible est signalé et la file passe au suivant.
// L'écoute réelle se vérifie à l'essai final (la sortie audio de l'environnement de test peut caler).
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lafleurmusic/library/models.dart';
import 'package:lafleurmusic/player/equalizer.dart';
import 'package:lafleurmusic/player/player.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart' show MpvAudioKit;

const fixtures = String.fromEnvironment('FIXTURES');

Track t(String name) => Track(
  path: '$fixtures/$name',
  folderId: 1,
  title: name,
  artist: '',
  album: 'A',
  durationMs: 3000,
  hasCover: false,
  mtime: 0,
  size: 0,
);

/// On ne ferme pas les lecteurs entre les essais : fermer un lecteur mpv pendant que CoreAudio publie
/// ses changements fait planter mpv_audio_kit (vu sur le Mac). On les fait taire et on les laisse.
Future<void> park(LafleurPlayer p) async {
  await p.setCrossfade(null);
  await p.setVolume(0);
  if (p.current.playing) await p.toggle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MpvAudioKit.ensureInitialized();
  // un seul lecteur pour tous les essais (le Mac n'a qu'une session « À l'écoute » par appli)
  late final shared = LafleurPlayer();

  testWidgets('fichier illisible sauté, morceaux enchaînés', (tester) async {
    final p = shared;
    await p.setVolume(0);
    final skipped = Completer<String>();
    p.skipped.listen((s) {
      if (!skipped.isCompleted) skipped.complete(s);
    });
    final reachedOpus = Completer<void>();
    p.state.listen((s) {
      if (s.track?.title == 'a.opus' && !reachedOpus.isCompleted) {
        reachedOpus.complete();
      }
    });
    await p.playTracks([t('a.wv'), t('broken.flac'), t('a.opus')], 0);
    await tester.runAsync(() async {
      expect(
        await skipped.future.timeout(const Duration(seconds: 15)),
        endsWith('broken.flac'),
      );
      await reachedOpus.future.timeout(const Duration(seconds: 15));
    });
    await park(p);
  });

  testWidgets('égaliseur Basses puis OFF pendant la lecture', (tester) async {
    final p = shared;
    await p.setVolume(0);
    await p.playTracks([t('a.flac')], 0);
    await p.setEqualizer(Equalizer.named('bass').copyWith(enabled: true));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await p.setEqualizer(Equalizer.named('bass'));
    await park(p);
  });

  testWidgets('balance + égaliseur ensemble, spectre pendant la lecture', (
    tester,
  ) async {
    final p = shared;
    await p.setVolume(0);
    await p.setEqualizer(Equalizer.named('rock').copyWith(enabled: true));
    await p.setBalance(-1);
    expect(p.balance, -1);
    final bars = Completer<List<double>>();
    final sub = p.spectrum.listen((b) {
      if (!bars.isCompleted) bars.complete(b);
    });
    await p.playTracks([t('a.flac')], 0);
    await tester.runAsync(() async {
      final b = await bars.future.timeout(const Duration(seconds: 10));
      expect(b.length, 19);
    });
    await sub.cancel();
    await park(p);
  });

  // plan 5, tâche 3 : un ajout passe avant la suite, sans rouvrir la liste
  testWidgets('Lire ensuite : l’ajout joue avant la suite de l’album', (
    tester,
  ) async {
    final p = shared;
    await p.setVolume(0);
    final seen = <String>[];
    p.state.listen((s) {
      final n = s.track?.title;
      if (n != null && (seen.isEmpty || seen.last != n)) seen.add(n);
    });
    await p.playTracks([t('a.flac'), t('a.mp3')], 0);
    await p.enqueue([t('a.wv')]);
    await p.playNext([t('a.opus')]);
    expect(p.queue!.order.map((x) => x.title), [
      'a.flac',
      'a.opus',
      'a.wv',
      'a.mp3',
    ]);
    await tester.runAsync(() async {
      await p.next();
      await Future<void>.delayed(const Duration(milliseconds: 600));
      await p.next();
      await Future<void>.delayed(const Duration(milliseconds: 600));
      await p.next();
      await Future<void>.delayed(const Duration(milliseconds: 600));
    });
    expect(seen, ['a.flac', 'a.opus', 'a.wv', 'a.mp3']);
    expect(p.queue!.order.map((x) => x.title), ['a.flac', 'a.mp3']);
    await park(p);
  });

  // plan 5, tâche 10 : fondu enchaîné réel (le son se vérifie à l'oreille à l'essai final)
  testWidgets('fondu enchaîné : a.flac → a.mp3 sans erreur', (tester) async {
    final p = shared;
    await p.setVolume(40);
    await p.setCrossfade(1);
    final errors = <String>[];
    p.skipped.listen(errors.add);
    final reached = Completer<Duration>();
    p.state.listen((s) {
      if (s.track?.title == 'a.mp3' && !reached.isCompleted) {
        reached.complete(s.position);
      }
    });
    await p.playTracks([t('a.flac'), t('a.mp3')], 0);
    await tester.runAsync(() async {
      await reached.future.timeout(const Duration(seconds: 10));
      await Future<void>.delayed(const Duration(milliseconds: 800));
    });
    expect(errors, isEmpty);
    expect(p.queue!.current!.title, 'a.mp3');
    expect(p.volume, 40); // volume rendu après le fondu
    await park(p);
  });
}
