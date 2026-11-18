import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/player/crossfade.dart';
import 'package:lafleurmusic/player/queue.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart'
    show AudioEffect, RawAudioEffect;

class FakeDeck implements Deck {
  final calls = <String>[];
  bool playing = false;
  double volume = -1;
  List<AudioEffect> effects = const [];
  @override
  Future<void> play(String path) async {
    calls.add('play $path');
    playing = true;
  }

  @override
  Future<void> setVolume(double v) async => volume = v;
  double gain = -99;
  @override
  Future<void> setGain(double db) async => gain = db;
  @override
  Future<void> setEffects(List<AudioEffect> e) async => effects = e;
  @override
  Future<Duration> position() async => const Duration(milliseconds: 300);
  @override
  Future<void> stop() async {
    calls.add('stop');
    playing = false;
  }
}

void main() {
  test('début du fondu', () {
    expect(
      CrossfadePlan.startAt(const Duration(minutes: 3), 5, repeat: Repeat.off),
      const Duration(minutes: 2, seconds: 55),
    );
    expect(
      CrossfadePlan.startAt(const Duration(seconds: 8), 5, repeat: Repeat.off),
      isNull,
    );
    expect(
      CrossfadePlan.startAt(const Duration(minutes: 3), 5, repeat: Repeat.one),
      isNull,
    );
  });

  test('les volumes se croisent', () {
    expect(CrossfadePlan.volumes(Duration.zero, 5), (1.0, 0.0));
    expect(CrossfadePlan.volumes(const Duration(milliseconds: 2500), 5), (
      0.5,
      0.5,
    ));
    expect(CrossfadePlan.volumes(const Duration(seconds: 5), 5), (0.0, 1.0));
    expect(CrossfadePlan.volumes(const Duration(seconds: 9), 5), (0.0, 1.0));
  });

  late FakeDeck deck;
  late List<double> main;
  late List<Duration> handed;
  late Crossfader fader;

  setUp(() {
    deck = FakeDeck();
    main = [];
    handed = [];
    fader = Crossfader(
      deck: deck,
      setMainVolume: (v) async => main.add(v),
      handover: (pos) async => handed.add(pos),
      tick: const Duration(milliseconds: 10),
    );
  });

  test('fondu complet : le 2e lecteur monte, le principal reprend la suite au même endroit', () async {
    const eq = [RawAudioEffect('lavfi-volume=1')];
    await fader.start(
      '/next.flac',
      length: const Duration(milliseconds: 120),
      volume: 80,
      effects: eq,
    );
    expect(deck.calls, ['play /next.flac']);
    expect(deck.effects, eq); // même égaliseur sur le 2e lecteur
    expect(fader.fading, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(fader.fading, isFalse);
    expect(handed, [const Duration(milliseconds: 300)]);
    expect(deck.playing, isFalse); // un seul lecteur joue à la fin
    expect(main.last, 80); // volume du principal rendu
    expect(main.any((v) => v > 0 && v < 80), isTrue); // il est bien descendu
  });

  test(
    'Suivant pendant le fondu : arrêt net du 2e lecteur, pas de relais',
    () async {
      await fader.start(
        '/next.flac',
        length: const Duration(seconds: 2),
        volume: 60,
        effects: const [],
      );
      await Future<void>.delayed(const Duration(milliseconds: 40));
      await fader.cancel();
      expect(deck.playing, isFalse);
      expect(main.last, 60);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(handed, isEmpty);
    },
  );

  test(
    'égaliseur changé pendant le fondu : appliqué au 2e lecteur aussi',
    () async {
      await fader.start(
        '/next.flac',
        length: const Duration(seconds: 2),
        volume: 60,
        effects: const [],
      );
      const eq = [RawAudioEffect('lavfi-bass=g=6')];
      await fader.effectsChanged(eq);
      expect(deck.effects, eq);
      await fader.cancel();
    },
  );

  test('relais : avancer seulement si le principal est encore sur le morceau qui finit', () {
    expect(
      CrossfadePlan.handover(current: '/a', fadedFrom: '/a', fadeNext: '/b'),
      Handover.advanceAndSeek,
    );
    expect(
      CrossfadePlan.handover(current: '/b', fadedFrom: '/a', fadeNext: '/b'),
      Handover.seekOnly,
    );
    expect(
      CrossfadePlan.handover(current: '/x', fadedFrom: '/a', fadeNext: '/b'),
      Handover.nothing,
    );
  });

  test('fondu encore valable si la file n’a pas changé', () {
    expect(
      CrossfadePlan.stillValid(
        current: '/a',
        next: '/b',
        fadedFrom: '/a',
        fadeNext: '/b',
      ),
      isTrue,
    );
    expect(
      CrossfadePlan.stillValid(
        current: '/b',
        next: '/c',
        fadedFrom: '/a',
        fadeNext: '/b',
      ),
      isTrue,
    );
    expect(
      CrossfadePlan.stillValid(
        current: '/a',
        next: '/x',
        fadedFrom: '/a',
        fadeNext: '/b',
      ),
      isFalse,
    ); // Lire ensuite X
    expect(
      CrossfadePlan.stillValid(
        current: '/c',
        next: '/d',
        fadedFrom: '/a',
        fadeNext: '/b',
      ),
      isFalse,
    ); // B supprimé
  });

  test(
    'le 2e lecteur reçoit le gain du morceau suivant avant de jouer',
    () async {
      await fader.start(
        '/next.flac',
        length: const Duration(seconds: 2),
        volume: 60,
        effects: const [],
        gain: -7,
      );
      expect(deck.gain, -7);
      await fader.cancel();
    },
  );

  test('arrêt pendant le relais : le relais n’a pas lieu', () async {
    final slow = Crossfader(
      deck: deck,
      setMainVolume: (v) async => main.add(v),
      handover: (pos) async {
        await Future<void>.delayed(const Duration(milliseconds: 80));
        handed.add(pos);
      },
      tick: const Duration(milliseconds: 10),
    );
    await slow.start(
      '/n.flac',
      length: const Duration(milliseconds: 30),
      volume: 50,
      effects: const [],
    );
    await Future<void>.delayed(
      const Duration(milliseconds: 50),
    ); // en plein relais
    expect(slow.fading, isTrue);
    await slow.cancel();
    expect(slow.aborted, isTrue); // le lecteur principal ne doit plus avancer
    expect(deck.playing, isFalse);
    expect(main.last, 50);
    expect(slow.fading, isFalse);
  });
}
