import 'dart:async';

import '../library/models.dart';
import '../player/equalizer.dart';
import '../player/player.dart';
import '../player/queue.dart';

/// Lecteur muet du mode démo (debug seulement) : tient la file et l'état affichés, ne joue aucun son.
class DemoPlayer implements PlayerController {
  DemoPlayer(this.current, this.queue);

  final _state = StreamController<PlayerState>.broadcast();
  final _queue = StreamController<void>.broadcast();

  @override
  PlayerState current;
  @override
  PlayQueue<Track>? queue;

  void _show({Track? track, Duration? position, bool? playing}) {
    final t = track ?? current.track;
    current = PlayerState(
      track: t,
      position: position ?? current.position,
      duration: Duration(milliseconds: t?.durationMs ?? 0),
      playing: playing ?? current.playing,
    );
    _state.add(current);
    _queue.add(null);
  }

  @override
  Stream<PlayerState> get state => _state.stream;
  @override
  Stream<void> get queueChanged => _queue.stream;
  @override
  Stream<String> get skipped => const Stream.empty();

  @override
  Future<void> playTracks(
    List<Track> tracks,
    int index, {
    bool shuffle = false,
  }) async {
    queue = PlayQueue(tracks, index: index);
    _show(track: tracks[index], position: Duration.zero, playing: true);
  }

  @override
  Future<void> toggle() async => _show(playing: !current.playing);
  @override
  Future<void> next() async {
    if (queue?.next() ?? false) {
      _show(track: queue!.current, position: Duration.zero);
    }
  }

  @override
  Future<void> previous() async {
    queue?.previous(Duration.zero);
    _show(track: queue?.current, position: Duration.zero);
  }

  @override
  Future<void> seek(Duration d) async => _show(position: d);
  @override
  Future<void> jumpTo(int i) async {
    queue?.jumpTo(i);
    _show(track: queue?.current, position: Duration.zero);
  }

  @override
  Future<void> playNext(List<Track> tracks) async {
    (queue ??= PlayQueue<Track>.empty()).playNext(tracks);
    _queue.add(null);
  }

  @override
  Future<void> enqueue(List<Track> tracks) async {
    (queue ??= PlayQueue<Track>.empty()).enqueue(tracks);
    _queue.add(null);
  }

  @override
  Future<void> removeAt(int i) async {
    queue?.removeAt(i);
    _queue.add(null);
  }

  @override
  Future<void> moveUpcoming(int from, int to) async {
    queue?.move(from, to);
    _queue.add(null);
  }

  @override
  Future<void> clearAdded() async {
    queue?.clearAdded();
    _queue.add(null);
  }

  @override
  Future<void> removeAdded(List<Track> tracks) async {
    queue?.removeLastAdded(tracks);
    _queue.add(null);
  }

  @override
  Future<void> removeTrack(String path) async {}
  @override
  Future<void> replaceTrack(String oldPath, Track now) async {}
  @override
  Future<void> toggleShuffle() async {
    queue?.toggleShuffle(1);
    _queue.add(null);
  }

  @override
  Future<void> cycleRepeat() async {
    queue?.cycleRepeat();
    _queue.add(null);
  }

  @override
  Future<void> setEqualizer(Equalizer eq) async {}
  @override
  Future<void> setVolume(double v) async => volume = v;
  @override
  double volume = 75;
  @override
  double balance = 0;
  @override
  Future<void> setBalance(double b) async => balance = b;
  @override
  Stream<List<double>> get spectrum => const Stream.empty();
  @override
  Stream<List<double>> get wave => const Stream.empty();
  @override
  AudioInfo get info => const AudioInfo();
  @override
  Stream<AudioInfo> get infoStream => const Stream.empty();
  @override
  Future<void> setTrackGain(double db) async {}
  @override
  Future<void> setCrossfade(int? seconds) async {}
}
