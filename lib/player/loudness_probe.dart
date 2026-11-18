import 'dart:async';

import 'package:mpv_audio_kit/mpv_audio_kit.dart';

/// Volume perçu d'un fichier (EBU R128, LUFS intégré), null s'il est illisible.
/// Un lecteur mpv muet ouvre le fichier sans le jouer ; mpv le décode hors lecture, bien plus vite que le temps réel.
/// Le lecteur est gardé d'une mesure à l'autre : en fermer un pendant que le son du Mac change peut faire planter mpv.
Future<double?> measureLoudness(
  String path, {
  Duration timeout = const Duration(seconds: 60),
}) => LoudnessProbe.shared.measure(path, timeout: timeout);

class LoudnessProbe {
  static final shared = LoudnessProbe();

  Player? _player;
  bool _used = false;
  Future<void> _last = Future.value();

  /// Une mesure à la fois (les demandes attendent leur tour).
  Future<double?> measure(String path, {required Duration timeout}) {
    final run = _last.then((_) => _measure(path, timeout));
    _last = run.then((_) {}, onError: (_) {});
    return run;
  }

  Future<double?> _measure(String path, Duration timeout) async {
    var player = _player;
    if (player == null) {
      player = _player = Player(
        configuration: const PlayerConfiguration(
          autoPlay: false,
          initialVolume: 0,
        ),
      );
      // aucune sortie son : la mesure n'ouvre jamais CoreAudio (voir LafleurPlayer)
      await player.setRawProperty('ao', 'null');
    }
    final done = Completer<double?>();
    void finish(double? v) {
      if (!done.isCompleted) done.complete(v);
    }

    // la mesure du fichier d'avant peut encore traîner : on attend le passage au nouveau (null ou « scanning »)
    var fresh = !_used; // premier fichier : rien d'ancien à écarter
    _used = true;
    final subs = [
      player.stream.loudnessScan.listen((s) {
        if (s == null || s.state == LoudnessScanState.scanning) {
          fresh = true;
          return;
        }
        if (!fresh) return;
        switch (s.state) {
          case LoudnessScanState.ready:
            final g = s.gatedBlockCount ?? 0;
            finish(
              g > 0 ? s.integrated : null,
            ); // que du silence : pas de mesure utile
          case LoudnessScanState.failed || LoudnessScanState.unavailable:
            finish(null);
          default:
            break;
        }
      }),
      player.stream.error.listen((_) => finish(null)),
    ];
    try {
      await player.open(Media(path), play: false);
      return await done.future.timeout(timeout, onTimeout: () => null);
    } catch (_) {
      return null;
    } finally {
      for (final s in subs) {
        await s.cancel();
      }
    }
  }
}
