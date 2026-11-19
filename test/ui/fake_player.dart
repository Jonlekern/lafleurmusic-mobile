import 'dart:async';

import 'package:lafleurmusic/library/models.dart';
import 'package:lafleurmusic/player/equalizer.dart';
import 'package:lafleurmusic/player/player.dart';
import 'package:lafleurmusic/player/queue.dart';

class FakePlayer implements PlayerController {
  final calls = <String>[];
  List<Track>? lastTracks;
  int? lastIndex;
  final _state = StreamController<PlayerState>.broadcast();
  @override
  PlayerState current = const PlayerState();
  @override
  PlayQueue<Track>? queue;

  void show(PlayerState s) {
    current = s;
    _state.add(s);
  }

  @override
  Stream<PlayerState> get state => _state.stream;
  @override
  Stream<String> get skipped => const Stream.empty();
  bool? lastShuffle;
  @override
  Future<void> playTracks(
    List<Track> tracks,
    int index, {
    bool shuffle = false,
  }) async {
    calls.add('play');
    lastShuffle = shuffle;
    lastTracks = tracks;
    lastIndex = index;
    queue = PlayQueue(tracks, index: index);
  }

  @override
  Future<void> toggle() async => calls.add('toggle');
  @override
  Future<void> next() async => calls.add('next');
  @override
  Future<void> previous() async => calls.add('previous');
  Duration? lastSeek;
  @override
  Future<void> seek(Duration d) async {
    calls.add('seek');
    lastSeek = d;
  }

  @override
  Future<void> setVolume(double v) async {
    calls.add('volume');
    volume = v;
  }

  @override
  Future<void> toggleShuffle() async => calls.add('shuffle');
  @override
  Future<void> cycleRepeat() async => calls.add('repeat');
  @override
  double volume = 75;
  @override
  double balance = 0;
  @override
  Future<void> setBalance(double b) async {
    calls.add('balance');
    balance = b;
  }

  final spectrumCtrl = StreamController<List<double>>.broadcast();
  final waveCtrl = StreamController<List<double>>.broadcast();
  @override
  Stream<List<double>> get spectrum => spectrumCtrl.stream;
  @override
  Stream<List<double>> get wave => waveCtrl.stream;
  @override
  AudioInfo info = const AudioInfo(kbps: 320, khz: 44, channels: 2);
  @override
  Stream<AudioInfo> get infoStream => const Stream.empty();
  @override
  Future<void> jumpTo(int i) async {
    calls.add('jump');
    queue?.jumpTo(i);
  }

  @override
  Future<void> removeAt(int i) async {
    calls.add('remove');
    queue?.removeAt(i);
    queueCtrl.add(null);
  }

  Equalizer? lastEq;
  @override
  Future<void> setEqualizer(Equalizer eq) async {
    calls.add('eq');
    lastEq = eq;
  }

  final queueCtrl = StreamController<void>.broadcast();
  @override
  Stream<void> get queueChanged => queueCtrl.stream;
  List<Track>? lastAdded;

  @override
  Future<void> playNext(List<Track> tracks) async {
    calls.add('playNext');
    lastAdded = tracks;
    (queue ??= PlayQueue<Track>.empty()).playNext(tracks);
    queueCtrl.add(null);
  }

  @override
  Future<void> enqueue(List<Track> tracks) async {
    calls.add('enqueue');
    lastAdded = tracks;
    (queue ??= PlayQueue<Track>.empty()).enqueue(tracks);
    queueCtrl.add(null);
  }

  @override
  Future<void> moveUpcoming(int from, int to) async {
    calls.add('move $from $to');
    queue?.move(from, to);
    queueCtrl.add(null);
  }

  @override
  Future<void> clearAdded() async {
    calls.add('clearAdded');
    queue?.clearAdded();
    queueCtrl.add(null);
  }

  @override
  Future<void> removeTrack(String path) async {
    calls.add('removeTrack $path');
    final q = queue;
    if (q == null) return;
    for (var i = q.order.length - 1; i >= 0; i--) {
      if (q.order[i].path == path) q.removeAt(i);
    }
    queueCtrl.add(null);
  }

  @override
  Future<void> replaceTrack(String oldPath, Track now) async {
    calls.add('replaceTrack $oldPath');
    queue?.replaceWhere((t) => t.path == oldPath, now);
    queueCtrl.add(null);
  }

  double trackGain = 0;
  @override
  Future<void> setTrackGain(double db) async => trackGain = db;

  int? crossfade;
  @override
  Future<void> setCrossfade(int? seconds) async {
    calls.add('crossfade $seconds');
    crossfade = seconds;
  }
}
