import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:async/async.dart' show StreamGroup;
import 'package:mpv_audio_kit/mpv_audio_kit.dart' hide Track;

import '../library/models.dart';
import 'crossfade.dart';
import 'eq_effects.dart';
import 'equalizer.dart';
import 'media_resolver.dart';
import 'mpv_port.dart';
import 'queue.dart';
import 'skip_guard.dart';

class PlayerState {
  const PlayerState({
    this.track,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.playing = false,
  });
  final Track? track;
  final Duration position;
  final Duration duration;
  final bool playing;
}

/// Infos du son en cours (fenêtre Winamp : kbps, kHz, mono / stéréo).
class AudioInfo {
  const AudioInfo({this.kbps, this.khz, this.channels});
  final int? kbps, khz, channels;
}

/// Ce que l'interface utilise du lecteur (remplacé par un faux dans les tests).
abstract interface class PlayerController {
  Stream<PlayerState> get state;
  Stream<String> get skipped;
  PlayerState get current;
  PlayQueue<Track>? get queue;
  Future<void> playTracks(
    List<Track> tracks,
    int index, {
    bool shuffle = false,
  });
  Future<void> toggle();
  Future<void> next();
  Future<void> previous();
  Future<void> seek(Duration d);
  Future<void> setVolume(double v);
  Future<void> toggleShuffle();
  Future<void> cycleRepeat();
  Future<void> setEqualizer(Equalizer eq);
  double get volume; // 0–100
  double get balance; // −1 (gauche) … 1 (droite)
  Future<void> setBalance(double b);
  Stream<List<double>> get spectrum; // 19 barres 0–1 (visualiseur, seulement écouté s'il est affiché)
  Stream<List<double>> get wave; // 76 points −1…1 (oscilloscope)
  AudioInfo get info;
  Stream<AudioInfo> get infoStream;
  Future<void> removeAt(
    int orderIndex,
  ); // retirer un morceau de la file (playlist Winamp)
  /// Lire ensuite / Ajouter à la file (lance la lecture si rien ne joue).
  Future<void> playNext(List<Track> tracks);
  Future<void> enqueue(List<Track> tracks);

  /// Glisser un morceau à venir (places dans `queue.order`).
  Future<void> moveUpcoming(int fromOrder, int toOrder);

  /// Vider : retire les ajouts.
  Future<void> clearAdded();

  /// Retire ce fichier de toute la file (supprimé du disque) ; s'il joue, on passe au suivant.
  Future<void> removeTrack(String path);

  /// Le fichier [oldPath] a été remplacé par [now] ; s'il joue, [now] démarre au début.
  Future<void> replaceTrack(String oldPath, Track now);

  /// Volume égal : gain (dB) appliqué aux morceaux sans ReplayGain dans leurs tags (0 = aucun).
  Future<void> setTrackGain(double db);

  /// Fondu enchaîné : durée en secondes (1 à 10), null = sans fondu.
  Future<void> setCrossfade(int? seconds);

  /// La file a changé (ajout, retrait, déplacement, morceau suivant).
  Stream<void> get queueChanged;
  Future<void> jumpTo(
    int orderIndex,
  ); // jouer ce morceau de la file, sans la refaire
}

/// Lecteur : la file d'attente (PlayQueue) décide de l'ordre, mpv joue la liste sans blanc.
class LafleurPlayer implements PlayerController {
  /// [resolver] : comment ouvrir un morceau du serveur (sans lui, seulement les fichiers locaux).
  LafleurPlayer({MediaResolver? resolver})
    : _resolver = resolver ?? MediaResolver.localOnly(),
      _mpv = Player(configuration: const PlayerConfiguration(autoPlay: true)) {
    _mpv.setGapless(Gapless.weak);
    // sortie audio fixe (48 kHz, float, stéréo) : mpv ne rouvre pas CoreAudio à chaque changement de format,
    // ce qui faisait planter mpv_audio_kit sur le Mac (44,1 kHz → 48 kHz)
    _mpv.setAudioSampleRate(48000);
    _mpv.setAudioFormat(Format.float32);
    _mpv.setAudioChannels(Channels.stereo);
    _mpv.setReplayGain(const ReplayGainSettings(mode: ReplayGain.track));
    _mpv.setMediaSession(const MediaSession());
    _sync = QueueSync<Track>(_port, (t) => t.path);
    _subs.addAll([
      _mpv.stream.playlist.listen((p) async {
        final q = _queue;
        // nos propres changements : la file est déjà à jour
        if (_editing > 0) return;
        if (p.index >= 0) _ends.mpvIndex = p.index;
        if (q != null && p.index >= 0 && p.index != q.position) {
          await _sync.advanced(q, p.index); // mpv est passé au suivant
          _ends.mpvIndex = q.position;
          _queueChanged.add(null);
        }
        _emit();
      }),
      _mpv.stream.position.listen((d) {
        _emit(position: d);
        _maybeFade(d);
      }),
      _mpv.stream.duration.listen((d) => _emit(duration: d)),
      _mpv.stream.playing.listen((b) => _emit(playing: b)),
      // Un événement « fin de fichier » par morceau, dans l'ordre de la liste mpv : la raison dit s'il a échoué.
      _mpv.stream.endFile.listen((e) {
        final q = _queue;
        if (q == null) return;
        final r = _ends.ended(q, switch (e.reason) {
          MpvEndFileReason.eof => FileEnd.eof,
          MpvEndFileReason.error =>
            FileEnd.error, // illisible, ou disparu du serveur (404)
          _ => FileEnd.other,
        });
        if (r.stop) _mpv.pause(); // 5 échecs de suite : le NAS ou le serveur est sans doute tombé
        // mpv passe au suivant
        if (r.skipped case final t?) _skipped.add(t.path);
      }),
    ]);
  }

  final Player _mpv;
  final MediaResolver _resolver;
  late final _port = PlayerPort(
    _mpv,
    _resolver,
  ); // la liste de mpv : modifiée seulement par ici, dans l'ordre
  late final QueueSync<Track> _sync;
  int _editing = 0;
  final _queueChanged = StreamController<void>.broadcast();

  @override
  Stream<void> get queueChanged => _queueChanged.stream;

  /// Un changement de file fait par l'appli : mpv et la file restent d'accord.
  Future<void> _edit(Future<void> Function(PlayQueue<Track> q) op) async {
    final q = _queue;
    if (q == null) return;
    _editing++;
    try {
      await op(q);
    } finally {
      _editing--;
    }
    _ends.mpvIndex = q.position;
    _queueChanged.add(null);
    _emit();
    await _checkFade();
  }

  @override
  Future<void> playNext(List<Track> tracks) => _add(tracks, next: true);
  @override
  Future<void> enqueue(List<Track> tracks) => _add(tracks, next: false);

  Future<void> _add(List<Track> tracks, {required bool next}) async {
    final playable = tracks.where((t) => !t.missing).toList();
    if (playable.isEmpty) return;
    final q = _queue;
    if (q == null || q.order.isEmpty) return playTracks(playable, 0);
    await _edit(
      (q) => next ? _sync.playNext(q, playable) : _sync.enqueue(q, playable),
    );
  }

  @override
  Future<void> setTrackGain(double db) => _mpv.setReplayGain(
    // ReplayGain des tags s'il existe, sinon notre mesure (« fallback »)
    ReplayGainSettings(mode: ReplayGain.track, fallback: db),
  );

  // fondu enchaîné : un 2e lecteur joue le début du suivant, puis mpv reprend au même endroit
  int? _crossfade;
  late final _deck = MpvDeck(_resolver);
  late final _fader = Crossfader(
    deck: _deck,
    setMainVolume: _mpv.setVolume,
    handover: _handover,
  );
  String? _fadeNext; // le morceau que joue le 2e lecteur
  String? _fadedFrom; // le morceau dont la fin a déjà été fondue
  double?
  _userVolume; // pendant un fondu, mpv descend : on montre le volume choisi

  @override
  Future<void> setCrossfade(int? seconds) async {
    _crossfade = seconds;
    if (seconds == null) await _fader.cancel();
  }

  void _maybeFade(Duration at) {
    final secs = _crossfade, q = _queue, cur = q?.current;
    if (secs == null || q == null || cur == null || _fader.fading) return;
    if (!_mpv.state.playing || cur.path == _fadedFrom) return;
    final start = CrossfadePlan.startAt(_last.duration, secs, repeat: q.repeat);
    if (start == null || at < start || at >= _last.duration) return;
    final i = q.position + 1 < q.order.length
        ? q.position + 1
        : (q.repeat == Repeat.all ? 0 : -1);
    if (i < 0 || q.order[i].missing || i == q.position) return;
    _fadedFrom = cur.path;
    _fadeNext = q.order[i].path;
    _userVolume = _mpv.state.volume;
    final next = q.order[i];
    unawaited(() async {
      _fadeGain = await gainOf?.call(next) ?? 0;
      await _fader.start(
        next.path,
        length: Duration(seconds: secs),
        volume: _userVolume ?? _mpv.state.volume,
        effects: audioEffects(_eq, _balance),
        gain: _fadeGain,
      );
    }());
  }

  /// Volume égal : gain d'un morceau avant qu'il joue (donné par LoudnessService), pour le 2e lecteur du fondu.
  Future<double> Function(Track track)? gainOf;
  double _fadeGain = 0;

  String? _nextPath(PlayQueue<Track> q) {
    if (q.order.isEmpty) return null;
    if (q.position + 1 < q.order.length) return q.order[q.position + 1].path;
    return q.repeat == Repeat.all ? q.order.first.path : null;
  }

  /// La file a changé pendant un fondu (Lire ensuite, suppression…) : le fondu n'a plus de sens.
  Future<void> _checkFade() async {
    final q = _queue;
    if (!_fader.fading || q == null) return;
    if (!CrossfadePlan.stillValid(
      current: q.current?.path,
      next: _nextPath(q),
      fadedFrom: _fadedFrom,
      fadeNext: _fadeNext,
    )) {
      await _stopFade();
    }
  }

  /// Fin du fondu : mpv passe au suivant (s'il n'y est pas déjà allé tout seul) et se place où en est le 2e lecteur.
  Future<void> _handover(Duration at) async {
    final q = _queue;
    if (q == null || _fader.aborted) return;
    switch (CrossfadePlan.handover(
      current: q.current?.path,
      fadedFrom: _fadedFrom,
      fadeNext: _fadeNext,
    )) {
      case Handover.advanceAndSeek:
        await setTrackGain(_fadeGain);
        _editing++; // pas de vérification du fondu pendant ce passage-là
        try {
          await _sync.next(q);
        } finally {
          _editing--;
        }
        _ends.mpvIndex = q.position;
        _queueChanged.add(null);
        _emit();
        if (_fader.aborted) return;
        await _mpv.seek(at);
      case Handover.seekOnly:
        await setTrackGain(_fadeGain);
        await _mpv.seek(at);
      case Handover.nothing:
        break;
    }
    _userVolume = null;
  }

  /// Une action de l'utilisateur pendant un fondu : le 2e lecteur s'arrête net.
  Future<void> _stopFade() async {
    if (!_fader.fading) return;
    await _fader.cancel();
    _userVolume = null;
  }

  @override
  Future<void> moveUpcoming(int fromOrder, int toOrder) =>
      _edit((q) => _sync.move(q, fromOrder, toOrder));
  @override
  Future<void> clearAdded() => _edit(_sync.clearAdded);
  @override
  Future<void> removeTrack(String path) async {
    var ended = false;
    await _edit(
      (q) async => ended = await _sync.removeWhere(q, (t) => t.path == path),
    );
    if (ended) await _parkAtEnd();
  }

  /// Fin de liste après une suppression : on reste sur le dernier morceau, en pause (comme à la fin de l'album).
  Future<void> _parkAtEnd() async {
    await _mpv.pause();
    await _mpv.seek(Duration.zero);
    _emit();
  }

  @override
  Future<void> replaceTrack(String oldPath, Track now) =>
      _edit((q) => _sync.replaceWhere(q, (t) => t.path == oldPath, now));
  final _subs = <StreamSubscription<Object?>>[];
  final _state = StreamController<PlayerState>.broadcast();
  final _skipped = StreamController<String>.broadcast();
  final _rand = Random();
  PlayQueue<Track>? _queue;
  final _ends =
      EndFiles<
        Track
      >(); // _ends.mpvIndex : morceau que mpv joue ou essaie d'ouvrir
  PlayerState _last = const PlayerState();

  @override
  Stream<PlayerState> get state => _state.stream;
  @override
  Stream<String> get skipped => _skipped.stream;
  @override
  PlayerState get current => _last;
  @override
  PlayQueue<Track>? get queue => _queue;

  /// Pochette de l'écran verrouillé pour un morceau du serveur, en octets (donnée par Covers dans main).
  Future<Uint8List?> Function(Track track)? artworkOf;
  String? _sessionPath;

  /// Écran verrouillé : morceau du serveur → tags de la bibliothèque et pochette en octets ; fichier local → mpv.
  Future<void> _updateSession(Track t) async {
    if (t.path == _sessionPath) return;
    final wasRemote =
        _sessionPath != null && parseRemoteKey(_sessionPath!) != null;
    _sessionPath = t.path;
    final remote = parseRemoteKey(t.path) != null;
    if (!remote && !wasRemote) return; // déjà la session par défaut
    try {
      await _mpv.setMediaSession(sessionFor(t, null));
      if (!remote) return;
      final art = await artworkOf?.call(t);
      // passé à un autre morceau entre-temps : rien à montrer
      if (art == null || _sessionPath != t.path) return;
      await _mpv.setMediaSession(sessionFor(t, art));
    } on Object {
      // pochette introuvable ou lecteur fermé : l'écran verrouillé garde ce qu'il a
    }
  }

  void _emit({Duration? position, Duration? duration, bool? playing}) {
    final track = _queue?.current;
    // nouveau morceau : on n'hérite pas de la position et de la durée de l'ancien
    final same = track?.path == _last.track?.path;
    if (track != null && !same) unawaited(_updateSession(track));
    _last = PlayerState(
      track: track,
      position: position ?? (same ? _last.position : Duration.zero),
      duration: duration ?? (same ? _last.duration : Duration.zero),
      playing: playing ?? _last.playing,
    );
    _state.add(_last);
  }

  Future<void> _open({Duration? at}) async {
    final q = _queue;
    if (q == null || q.order.isEmpty) return;
    _ends.mpvIndex = q.position;
    _editing++;
    try {
      await _sync.open(q);
    } finally {
      _editing--;
    }
    _queueChanged.add(null);
    if (at != null && at > Duration.zero) await _mpv.seek(at);
    _emit();
  }

  /// Joue la liste à partir de [index] (double-clic sur un morceau).
  @override
  Future<void> playTracks(
    List<Track> tracks,
    int index, {
    bool shuffle = false,
  }) async {
    final old = _queue;
    final playable = tracks.where((t) => !t.missing).toList();
    if (playable.isEmpty) return;
    // bouton Aléatoire : départ au hasard, liste ouverte une seule fois
    final start = shuffle
        ? _rand.nextInt(playable.length)
        : playable.indexOf(tracks[index]).clamp(0, playable.length - 1);
    final q = PlayQueue<Track>(playable, index: start);
    if (old != null) q.repeat = old.repeat;
    if (shuffle || (old?.shuffle ?? false)) {
      q.toggleShuffle(_rand.nextInt(1 << 30));
    }
    _queue = q;
    await _stopFade();
    await _open();
  }

  @override
  Future<void> toggle() async {
    await _stopFade();
    await (_mpv.state.playWhenReady ? _mpv.pause() : _mpv.play());
  }

  @override
  Future<void> next() async {
    final q = _queue;
    if (q == null) return;
    await _stopFade();
    var moved = false;
    await _edit((q) async => moved = await _sync.next(q));
    if (!moved) {
      // fin de la liste : on reste sur le dernier morceau, en pause (stop viderait la liste de mpv)
      await _mpv.pause();
      await _mpv.seek(Duration.zero);
    }
    _emit();
  }

  @override
  Future<void> previous() async {
    final q = _queue;
    if (q == null) return;
    await _stopFade();
    final before = q.position;
    q.previous(_last.position);
    if (q.position == before) {
      await _mpv.seek(Duration.zero);
    } else {
      _ends.mpvIndex = q.position;
      await _port.jump(q.position); // après les ajouts en cours
    }
    _emit();
  }

  @override
  Future<void> seek(Duration d) async {
    await _stopFade();
    await _mpv.seek(d);
  }

  @override
  Future<void> setVolume(double v) async {
    if (_fader.fading) {
      // pendant le fondu, mpv suit la rampe : le volume choisi s'appliquera à la fin
      _userVolume = v;
      _fader.volume = v;
      return;
    }
    await _mpv.setVolume(v);
  }

  @override
  Future<void> toggleShuffle() async {
    final q = _queue;
    if (q == null) return;
    await _stopFade();
    q.toggleShuffle(_rand.nextInt(1 << 30));
    await _open(at: _last.position); // même morceau, même endroit, nouvel ordre
  }

  Equalizer _eq = Equalizer.named('flat');
  double _balance = 0;

  @override
  Future<void> setEqualizer(Equalizer eq) {
    _eq = eq;
    unawaited(_fader.effectsChanged(audioEffects(_eq, _balance)));
    return _mpv.setAudioEffects(audioEffects(_eq, _balance));
  }

  @override
  double get volume => _userVolume ?? _mpv.state.volume;
  @override
  double get balance => _balance;
  @override
  Future<void> setBalance(double b) {
    _balance = b.clamp(-1.0, 1.0);
    unawaited(_fader.effectsChanged(audioEffects(_eq, _balance)));
    return _mpv.setAudioEffects(audioEffects(_eq, _balance));
  }

  @override
  Future<void> jumpTo(int orderIndex) async {
    final q = _queue;
    if (q == null || orderIndex < 0 || orderIndex >= q.order.length) return;
    await _stopFade();
    await _edit((q) => _sync.jumpTo(q, orderIndex));
    await _mpv.play();
  }

  @override
  Future<void> removeAt(int orderIndex) async {
    final q = _queue;
    if (q == null || orderIndex < 0 || orderIndex >= q.order.length) return;
    var ended = false;
    await _edit((q) async => ended = await _sync.removeAt(q, orderIndex));
    if (ended) await _parkAtEnd();
  }

  @override
  AudioInfo get info => _info(_mpv.state.audioBitrate, _mpv.state.audioParams);
  @override
  late final Stream<AudioInfo> infoStream = StreamGroup.mergeBroadcast([
    _mpv.stream.audioBitrate,
    _mpv.stream.audioParams,
  ]).map((_) => info).asBroadcastStream();

  static AudioInfo _info(double? bitrate, AudioParams p) => AudioInfo(
    kbps: bitrate == null ? null : (bitrate / 1000).round(),
    khz: p.sampleRate == null ? null : (p.sampleRate! / 1000).round(),
    channels: p.channelCount,
  );

  // flux créés une fois : mpv n'analyse le son que tant que quelqu'un écoute
  @override
  late final Stream<List<double>> spectrum = _mpv.stream.fft.map(
    (f) => spectrumBars(f.bands),
  );
  @override
  late final Stream<List<double>> wave = _mpv.stream.pcm.map(
    (f) => wavePoints(f.samples, f.channels),
  );

  @override
  Future<void> cycleRepeat() async {
    final q = _queue;
    if (q == null) return;
    q.cycleRepeat();
    await _mpv.setLoop(switch (q.repeat) {
      Repeat.off => Loop.off,
      Repeat.all => Loop.playlist,
      Repeat.one => Loop.file,
    });
    _emit();
  }

  Future<void> dispose() async {
    await _fader.cancel();
    await _deck.dispose();
    for (final s in _subs) {
      await s.cancel();
    }
    await _mpv.dispose();
  }
}
