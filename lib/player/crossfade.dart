import 'dart:async';

import 'package:mpv_audio_kit/mpv_audio_kit.dart';

import 'media_resolver.dart';
import 'queue.dart';

/// Quand commencer le fondu et comment croiser les volumes.
class CrossfadePlan {
  /// Moment où le suivant démarre ; null = pas de fondu (morceau trop court, répéter un seul).
  static Duration? startAt(
    Duration duration,
    int seconds, {
    required Repeat repeat,
  }) {
    final n = Duration(seconds: seconds);
    if (repeat == Repeat.one || seconds <= 0 || duration < n * 2) return null;
    return duration - n;
  }

  /// Volumes (sortant, entrant) de 0 à 1, rampe linéaire sur [seconds].
  static (double, double) volumes(Duration sinceStart, int seconds) =>
      ramp(sinceStart, Duration(seconds: seconds));

  /// Fin du fondu : que doit faire le lecteur principal ?
  static Handover handover({
    required String? current,
    required String? fadedFrom,
    required String? fadeNext,
  }) => current == fadedFrom
      ? Handover.advanceAndSeek
      : (current == fadeNext ? Handover.seekOnly : Handover.nothing);

  /// Le fondu en cours a encore un sens (la file n'a pas changé sous lui).
  static bool stillValid({
    required String? current,
    required String? next,
    required String? fadedFrom,
    required String? fadeNext,
  }) => current == fadeNext || (current == fadedFrom && next == fadeNext);

  static (double, double) ramp(Duration since, Duration length) {
    final x = length <= Duration.zero
        ? 1.0
        : (since.inMicroseconds / length.inMicroseconds).clamp(0.0, 1.0);
    return (1 - x, x.toDouble());
  }
}

enum Handover {
  advanceAndSeek, // encore sur le morceau qui finit : passer au suivant, se placer où en est le 2e lecteur
  seekOnly, // mpv est déjà passé au suivant tout seul : se placer seulement
  nothing, // la file a changé : ne rien faire
}

/// Le 2e lecteur, qui joue le début du morceau suivant pendant le fondu.
abstract interface class Deck {
  Future<void> play(String path);
  Future<void> setVolume(double v); // 0–100
  Future<void> setGain(
    double db,
  ); // Volume égal : gain du morceau sans ReplayGain
  Future<void> setEffects(List<AudioEffect> effects);
  Future<Duration> position();
  Future<void> stop();
}

/// 2e lecteur mpv, créé au premier fondu.
class MpvDeck implements Deck {
  MpvDeck([MediaResolver? resolver])
    : _resolver = resolver ?? MediaResolver.localOnly();
  final MediaResolver _resolver;
  Player? _p;
  Player get _player => _p ??=
      Player(
          configuration: const PlayerConfiguration(
            autoPlay: true,
            initialVolume: 0,
          ),
        )
        // même sortie fixe que le lecteur principal (voir LafleurPlayer)
        ..setAudioSampleRate(48000)
        ..setAudioFormat(Format.float32)
        ..setAudioChannels(Channels.stereo)
        ..setReplayGain(const ReplayGainSettings(mode: ReplayGain.track));

  @override
  Future<void> play(String path) async {
    final media = await _resolver.media(path);
    await _player.setVolume(0);
    await _player.open(media);
  }

  @override
  Future<void> setVolume(double v) => _player.setVolume(v);
  @override
  Future<void> setGain(double db) => _player.setReplayGain(
    ReplayGainSettings(mode: ReplayGain.track, fallback: db),
  );
  @override
  Future<void> setEffects(List<AudioEffect> effects) =>
      _player.setAudioEffects(effects);
  @override
  Future<Duration> position() async => _player.state.position;
  @override
  Future<void> stop() async => _p?.stop();

  Future<void> dispose() async => _p?.dispose();
}

/// Fondu enchaîné : le 2e lecteur démarre le suivant à volume 0, les volumes se croisent,
/// puis le lecteur principal passe au suivant au même endroit ([handover]) et le 2e s'arrête.
class Crossfader {
  Crossfader({
    required this.deck,
    required this.setMainVolume,
    required this.handover,
    this.tick = const Duration(milliseconds: 50),
  });
  final Deck deck;
  final Future<void> Function(double volume) setMainVolume;
  final Future<void> Function(Duration nextPosition) handover;
  final Duration tick;

  Timer? _timer;
  double _volume = 100;
  bool _finishing = false;
  bool _aborted = false;

  /// Arrêté pendant le relais : le lecteur principal ne doit plus avancer.
  bool get aborted => _aborted;
  bool get fading => _timer != null || _finishing;

  /// Volume à rendre au principal à la fin (l'utilisateur l'a changé pendant le fondu).
  set volume(double v) => _volume = v;

  Future<void> start(
    String nextPath, {
    required Duration length,
    required double volume,
    required List<AudioEffect> effects,
    double gain = 0,
  }) async {
    await cancel();
    _aborted = false;
    _volume = volume;
    await deck.setEffects(effects);
    await deck.setGain(gain);
    await deck.setVolume(0);
    await deck.play(nextPath);
    final clock = Stopwatch()..start();
    _timer = Timer.periodic(tick, (_) async {
      final (out, inn) = CrossfadePlan.ramp(clock.elapsed, length);
      unawaited(setMainVolume(_volume * out));
      unawaited(deck.setVolume(_volume * inn));
      if (clock.elapsed >= length) {
        _timer?.cancel();
        _timer = null;
        await _finish();
      }
    });
  }

  Future<void> _finish() async {
    _finishing = true;
    try {
      await handover(await deck.position());
      if (_aborted) return; // cancel() a déjà tout remis
      await setMainVolume(_volume);
      await deck.stop();
    } finally {
      _finishing = false;
    }
  }

  /// Suivant / Précédent / clic / pause pendant un fondu : le 2e lecteur s'arrête net.
  Future<void> cancel() async {
    if (_timer == null && !_finishing) return;
    _aborted = _finishing;
    _timer?.cancel();
    _timer = null;
    _finishing = false;
    await deck.stop();
    await setMainVolume(_volume);
  }

  Future<void> effectsChanged(List<AudioEffect> effects) async {
    if (fading) await deck.setEffects(effects);
  }
}
