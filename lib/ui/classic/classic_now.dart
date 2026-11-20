import 'dart:async';

import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../l10n/strings.dart';
import '../../player/player.dart';
import '../../theme/colors.dart';
import '../cover_image.dart';
import '../format.dart';
import '../phone/phone_shell.dart';
import 'classic_frame.dart';
import 'click_wheel.dart';

// Maquette 12 A / B (maquettes/src/12-classic.html, .np)
const _screenBg = Color(0xFF111111);
const _grey = Color(0xFF999999); // titre, n sur m, temps, haut-parleurs
const _artist = Color(0xFFBBBBBB);
const _album = Color(0xFF888888);
const _track = Color(0xFF2A2A2A); // fond des deux barres
const _volume = Color(0xFFDDDDDD); // la barre blanche du volume

/// Ouvre En cours du Mode Classic (debout, comme l'En cours du mode normal).
Future<void> openClassicNow(BuildContext context) => pushPhone(
  context,
  const ClassicNow(),
  settings: const RouteSettings(name: 'now'),
);

/// En cours en Mode Classic (maquette 12) : l'écran façon iPod (EN COURS, n sur m, pochette,
/// titre, artiste, album, progression, volume) et la molette. Tourner = volume ; un appui au
/// milieu passe en « avancer dans le morceau » (losange rose), un nouvel appui ou 3 s sans
/// toucher la molette revient au volume. ⏮ ⏭ ▶︎❙❙ commandent le lecteur, MENU revient au menu.
class ClassicNow extends StatefulWidget {
  const ClassicNow({super.key});

  /// Un cran de volume, sur 0–100 : la molette règle le volume de l'appli (le lecteur), pas
  /// celui du téléphone. 20 crans du silence au maximum.
  static const volumeStep = 5.0;
  static const maxVolume = 100.0;

  /// Un cran en avançant dans le morceau.
  static const seekStep = Duration(seconds: 5);

  /// Sans toucher la molette pendant ce temps : retour au volume.
  static const scrubIdle = Duration(seconds: 3);

  /// Le seek part quand la molette s'arrête ce temps-là (un seul seek pour un tour rapide).
  static const seekDelay = Duration(milliseconds: 120);

  /// Le lecteur est arrivé au losange à ce temps près : le cran suivant part de la lecture.
  static const reached = Duration(seconds: 1);

  /// Le lecteur n'a pas dit être arrivé au losange après ce temps : le temps revient à la lecture.
  static const seekSettle = Duration(seconds: 2);

  @override
  State<ClassicNow> createState() => _ClassicNowState();
}

class _ClassicNowState extends State<ClassicNow> {
  PlayerController? _player;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<void>? _queueSub;
  PlayerState _st = const PlayerState();
  double _vol = 0;
  bool _scrub = false;
  Duration? _target; // où la molette a envoyé le morceau (le losange y reste)
  Timer? _idle;
  Timer? _seekTimer; // le seek vers [_target], en attente
  Timer? _settle; // le seek est parti : [_target] ne reste pas plus longtemps

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final player = AppScope.of(context).player;
    if (identical(player, _player)) return;
    _stateSub?.cancel();
    _queueSub?.cancel();
    _player = player;
    _st = player.current;
    _vol = player.volume.clamp(0, ClassicNow.maxVolume);
    _stateSub = player.state.listen((st) {
      if (!mounted) return;
      setState(() {
        // un autre morceau : le losange repart de sa position
        if (st.track?.path != _st.track?.path) _clearTarget();
        // le lecteur est arrivé au losange : la suite part de la lecture, le temps la suit
        final t = _target;
        if (t != null &&
            _seekTimer == null &&
            (st.position - t).abs() <= ClassicNow.reached) {
          _clearTarget();
        }
        _st = st;
      });
    });
    // n sur m : la file a changé (ajout, retrait, saut)
    _queueSub = player.queueChanged.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _idle?.cancel();
    // MENU juste après un cran : le dernier seek n'est pas perdu
    if (_seekTimer?.isActive ?? false) _sendSeek();
    _seekTimer?.cancel();
    _settle?.cancel();
    _stateSub?.cancel();
    _queueSub?.cancel();
    super.dispose();
  }

  void _rotate(int steps) => _scrub ? _seek(steps) : _changeVolume(steps);

  void _changeVolume(int steps) {
    final next = (_vol + steps * ClassicNow.volumeStep).clamp(
      0.0,
      ClassicNow.maxVolume,
    );
    if (next == _vol) return;
    setState(() => _vol = next);
    _player!.setVolume(next);
  }

  void _seek(int steps) {
    _restartIdle();
    final total = _st.duration;
    if (total <= Duration.zero) return;
    final from = _target ?? _st.position;
    var next = from + ClassicNow.seekStep * steps;
    if (next < Duration.zero) next = Duration.zero;
    if (next > total) next = total;
    if (next == from) return;
    setState(() => _target = next);
    _seekTimer?.cancel();
    _seekTimer = Timer(ClassicNow.seekDelay, _sendSeek);
  }

  /// Envoie le seek en attente, tout de suite.
  void _sendSeek() {
    _seekTimer?.cancel();
    _seekTimer = null;
    final t = _target;
    if (t == null) return;
    _player?.seek(t);
    _settle?.cancel();
    _settle = Timer(ClassicNow.seekSettle, () {
      if (mounted && _seekTimer == null) setState(_clearTarget);
    });
  }

  /// Le temps suit de nouveau la lecture.
  void _clearTarget() {
    _target = null;
    _settle?.cancel();
    _settle = null;
  }

  /// Le rond du milieu : volume ↔ avancer dans le morceau (rien à avancer sans morceau).
  void _select() {
    if (_scrub) return _toVolume();
    if (_st.track == null) return;
    setState(() => _scrub = true);
    _restartIdle();
  }

  void _restartIdle() {
    _idle?.cancel();
    _idle = Timer(ClassicNow.scrubIdle, _toVolume);
  }

  void _toVolume() {
    _idle?.cancel();
    _idle = null;
    if (_seekTimer != null) _sendSeek(); // le dernier cran n'est pas perdu
    if (!mounted) return;
    // le temps reste au losange jusqu'à ce que le lecteur y soit (voir l'écoute du lecteur)
    setState(() => _scrub = false);
  }

  /// Lecteur d'écran : ce que règle la molette, [step] crans plus loin.
  String _wheelValue(int step) {
    if (_scrub) {
      final total = _st.duration;
      var at = (_target ?? _st.position) + ClassicNow.seekStep * step;
      if (at < Duration.zero) at = Duration.zero;
      if (total > Duration.zero && at > total) at = total;
      return '${clock(at)} / ${clock(total)}';
    }
    final v = (_vol + ClassicNow.volumeStep * step).clamp(
      0.0,
      ClassicNow.maxVolume,
    );
    return '${v.round()} %';
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final player = app.player;
    final q = player.queue;
    final t = _st.track;
    return ClassicFrame(
      screen: LayoutBuilder(
        // petit téléphone : l'écran se resserre en entier, comme la molette
        builder: (_, c) {
          const h = ClassicFrame.screenHeight;
          final k = c.maxHeight < h ? c.maxHeight / h : 1.0;
          return FittedBox(
            child: SizedBox(
              width: c.maxWidth / k,
              height: h,
              child: _Card(
                strings: app.strings,
                state: _st,
                position: _target ?? _st.position,
                where: t == null || q == null || q.order.isEmpty
                    ? null
                    : (q.position + 1, q.order.length),
                volume: _vol / ClassicNow.maxVolume,
                scrub: _scrub,
              ),
            ),
          );
        },
      ),
      wheel: ClickWheel(
        onRotate: _rotate,
        onSelect: _select,
        onMenu: () => Navigator.of(context).maybePop(),
        onPrevious: player.previous,
        onNext: player.next,
        onPlayPause: player.toggle,
        semanticLabel: app.strings.wheel,
        // tourner règle le volume, ou la position dans le morceau
        semanticValue: _wheelValue(0),
        semanticIncreasedValue: _wheelValue(1),
        semanticDecreasedValue: _wheelValue(-1),
      ),
    );
  }
}

/// L'écran du haut (maquette 12 A, .np).
class _Card extends StatelessWidget {
  const _Card({
    required this.strings,
    required this.state,
    required this.position,
    required this.where,
    required this.volume,
    required this.scrub,
  });
  final Strings strings;
  final PlayerState state;
  final Duration position;
  final (int, int)? where; // n sur m dans la file
  final double volume; // 0–1
  final bool scrub;

  static const _head = TextStyle(
    color: _grey,
    fontSize: 11,
    letterSpacing: 1,
    fontWeight: FontWeight.w700,
  );
  static const _time = TextStyle(color: _grey, fontSize: 12);

  @override
  Widget build(BuildContext context) {
    final s = strings;
    final t = state.track;
    final total = state.duration;
    final f = total > Duration.zero
        ? (position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
    final rest = total - position;
    return Container(
      clipBehavior: Clip.hardEdge,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      decoration: BoxDecoration(
        color: _screenBg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(s.classicNowPlaying.toUpperCase(), style: _head),
              const Spacer(),
              if (where case (final n, final m))
                Text(s.classicPosition(n, m), style: _head),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              CoverImage(trackPath: t?.path, size: 120, radius: 6),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _line(
                      t?.title ?? '',
                      TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: context.colors.text,
                      ),
                    ),
                    const SizedBox(height: 6),
                    _line(
                      t == null
                          ? ''
                          : t.artist.isEmpty
                          ? s.unknownArtist
                          : t.artist,
                      const TextStyle(fontSize: 13, color: _artist),
                    ),
                    const SizedBox(height: 3),
                    _line(
                      t?.album ?? '',
                      const TextStyle(fontSize: 13, color: _album),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 26),
          // lecteur d'écran : où on en est, dit pendant qu'on tourne
          Semantics(
            key: const Key('classic-now-progress-bar'),
            container: true,
            label: s.classicTrackPosition,
            value: '${clock(position)} / ${clock(total)}',
            child: _Bar(
              fraction: f,
              color: context.colors.pink,
              diamond: scrub,
              fillKey: const Key('classic-now-progress'),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(clock(position), style: _time),
              const Spacer(),
              Text('−${clock(rest)}', style: _time),
            ],
          ),
          const SizedBox(height: 18),
          if (scrub)
            Text(
              s.classicScrub,
              // le losange se voit, il ne se lit pas
              semanticsLabel: s.classicScrub.replaceFirst('◆', '').trim(),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.colors.pink,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            )
          else
            Row(
              children: [
                const ExcludeSemantics(
                  child: Icon(
                    Icons.volume_mute_rounded,
                    size: 14,
                    color: _grey,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Semantics(
                    key: const Key('classic-now-volume-bar'),
                    container: true,
                    label: s.classicVolume,
                    value: '${(volume * 100).round()} %',
                    child: _Bar(
                      fraction: volume,
                      color: _volume,
                      fillKey: const Key('classic-now-volume'),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const ExcludeSemantics(
                  child: Icon(Icons.volume_up_rounded, size: 14, color: _grey),
                ),
              ],
            ),
        ],
      ),
    );
  }

  static Widget _line(String text, TextStyle style) =>
      Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: style);
}

/// Une barre de 6 points (progression ou volume) ; [diamond] : le losange rose de la maquette 12 B.
class _Bar extends StatelessWidget {
  const _Bar({
    required this.fraction,
    required this.color,
    required this.fillKey,
    this.diamond = false,
  });
  final double fraction;
  final Color color;
  final Key fillKey;
  final bool diamond;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 6,
    child: LayoutBuilder(
      builder: (_, c) => Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: _track,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          Positioned.fill(
            child: Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                key: fillKey,
                widthFactor: fraction,
                heightFactor: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
          ),
          if (diamond)
            Positioned(
              key: const Key('classic-now-diamond'),
              left: c.maxWidth * fraction - 8,
              top: -5,
              child: Transform.rotate(
                angle: 0.785398, // 45°
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: context.colors.pink,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
