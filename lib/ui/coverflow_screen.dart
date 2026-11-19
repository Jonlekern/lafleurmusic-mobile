import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_scope.dart';
import '../library/merge.dart';
import '../library/models.dart';
import '../theme/colors.dart';
import '../theme/widgets.dart';
import 'cover_image.dart';
import 'coverflow_layout.dart';

/// Cover Flow plein écran (maquette 3) : molette, trackpad, ← →, Entrée = jouer, Échap = sortir.
class CoverflowScreen extends StatefulWidget {
  const CoverflowScreen({
    super.key,
    required this.albums,
    this.initial = 0,
    this.onOpen,
  });
  final List<Album> albums;
  final int initial;
  final void Function(Album album)? onOpen;

  @override
  State<CoverflowScreen> createState() => _CoverflowScreenState();
}

class _CoverflowScreenState extends State<CoverflowScreen>
    with SingleTickerProviderStateMixin {
  late double _pos = widget.initial.toDouble();
  late final AnimationController _anim =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 320),
      )..addListener(
        () => setState(
          () => _pos =
              _from +
              (_to - _from) * Curves.easeOutCubic.transform(_anim.value),
        ),
      );
  double _from = 0, _to = 0;

  int get _count => widget.albums.length;
  int get _current => settle(_pos, _count).toInt();

  void _goTo(double target) {
    _from = _pos;
    _to = settle(target, _count);
    _anim.forward(from: 0);
  }

  // molette de souris : un cran = un album, tout de suite ; les crans rapides s'enchaînent
  // sans à-coup (chaque cran repart de la position où en est l'animation)
  double _wheel = 0;
  Timer? _wheelIdle;

  void _onWheel(double delta) {
    _wheel += delta;
    _wheelIdle?.cancel();
    _wheelIdle = Timer(const Duration(milliseconds: 300), () => _wheel = 0);
    if (_wheel.abs() < 20) return;
    final step = _wheel.sign;
    _wheel = 0;
    final base = _anim.isAnimating ? _to : _pos.roundToDouble();
    _goTo(base + step);
  }

  // trackpad : on suit le doigt, puis on se pose quand ça s'arrête.
  // Un petit geste (un cran de molette) suffit pour passer à l'album voisin.
  Timer? _idle;
  double? _scrollFrom;

  void _scrollBy(double albums) {
    _anim.stop();
    _scrollFrom ??= _current.toDouble();
    setState(() => _pos = (_pos + albums).clamp(-0.4, _count - 0.6));
    _idle?.cancel();
    _idle = Timer(const Duration(milliseconds: 140), _endScroll);
  }

  void _endScroll() {
    _idle?.cancel();
    final from = _scrollFrom;
    _scrollFrom = null;
    if (from == null || !mounted) return;
    final moved = _pos - from;
    var target = _pos.roundToDouble();
    if (target == from && moved.abs() >= 0.15) target = from + moved.sign;
    _goTo(target);
  }

  Future<void> _play() async {
    if (_count == 0) return;
    final app = AppScope.of(context);
    final tracks = await app.library
        .albumTracks(widget.albums[_current].key)
        .first;
    if (tracks.isNotEmpty) await app.player.playTracks(tracks, 0);
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    switch (e.logicalKey) {
      case LogicalKeyboardKey.arrowLeft:
        _goTo(_current - 1.0);
      case LogicalKeyboardKey.arrowRight:
        _goTo(_current + 1.0);
      case LogicalKeyboardKey.enter:
        _play();
      case LogicalKeyboardKey.escape:
        Navigator.of(context).maybePop();
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    _idle?.cancel();
    _wheelIdle?.cancel();
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context).strings;
    final size = MediaQuery.sizeOf(context);
    final cover = (size.height * 0.44).clamp(180.0, 400.0);
    final k = cover / 400;
    final album = _count == 0 ? null : widget.albums[_current];
    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        body: Listener(
          onPointerSignal: (e) {
            if (e is PointerScrollEvent) {
              _onWheel(
                e.scrollDelta.dx.abs() > e.scrollDelta.dy.abs()
                    ? e.scrollDelta.dx
                    : e.scrollDelta.dy,
              );
            }
          },
          onPointerPanZoomUpdate: (e) => _scrollBy(
            -(e.panDelta.dx.abs() >= e.panDelta.dy.abs()
                    ? e.panDelta.dx
                    : e.panDelta.dy) /
                (180 * k),
          ),
          onPointerPanZoomEnd: (_) => _endScroll(),
          child: Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -0.2),
                radius: 0.9,
                colors: [Color(0xFF1D1D1D), Color(0xFF050505)],
              ),
            ),
            child: Stack(
              children: [
                Positioned(
                  top: 28,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Image.asset(
                      'assets/logo-texte-grand.png',
                      height: 22,
                    ),
                  ),
                ),
                Positioned(
                  top: 30,
                  right: 30,
                  child: Text(
                    s.escToQuit,
                    style: const TextStyle(
                      color: LafleurColors.sub,
                      fontSize: 13,
                    ),
                  ),
                ),
                Positioned(
                  top: size.height * 0.17,
                  left: 0,
                  right: 0,
                  height: cover * 1.5,
                  child: Stack(
                    alignment: Alignment.topCenter,
                    children: [
                      for (final i in drawOrder(_pos, _count))
                        _cover(i, cover, k),
                    ],
                  ),
                ),
                if (album != null)
                  Positioned(
                    top: size.height * 0.17 + cover * 1.35,
                    left: 0,
                    right: 0,
                    child: Column(
                      children: [
                        Text(
                          album.name.isEmpty ? s.unknownArtist : album.name,
                          style: const TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          s.playlistN(album.trackCount),
                          style: const TextStyle(
                            color: LafleurColors.sub,
                            fontSize: 17,
                          ),
                        ),
                        const SizedBox(height: 22),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            PillButton(
                              label: s.play,
                              icon: Icons.play_arrow_rounded,
                              primary: true,
                              onPressed: _play,
                            ),
                            const SizedBox(width: 12),
                            PillButton(
                              label: s.openPlaylist,
                              onPressed: () {
                                widget.onOpen?.call(album);
                                Navigator.of(context).maybePop();
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 26),
                        Text(
                          s.coverFlowHelp,
                          style: const TextStyle(
                            color: Color(0xFF666666),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _cover(int i, double size, double k) {
    final slot = layout(_pos, i);
    final b = slot.brightness;
    final img = CoverImage(
      trackPath: widget.albums[i].coverTrackPath,
      size: size,
      radius: 0,
    );
    return Transform(
      key: ValueKey(i),
      alignment: Alignment.topCenter,
      origin: Offset(0, size / 2), // pivote autour du milieu de la pochette
      // décalage à plat, puis réduction (côtés plus petits que le centre, maquette 3), puis inclinaison en perspective
      transform: Matrix4.translationValues(slot.dx * k, 0, 0)
        ..multiply(Matrix4.diagonal3Values(slot.scale, slot.scale, 1))
        ..multiply(Matrix4.identity()..setEntry(3, 2, 0.0006))
        ..rotateY(slot.angle),
      child: GestureDetector(
        onTap: () => i == _current ? _play() : _goTo(i.toDouble()),
        child: ColorFiltered(
          colorFilter: ColorFilter.matrix([
            b,
            0,
            0,
            0,
            0,
            0,
            b,
            0,
            0,
            0,
            0,
            0,
            b,
            0,
            0,
            0,
            0,
            0,
            1,
            0,
          ]),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              img,
              const SizedBox(height: 2),
              // reflet : seulement le haut de la pochette retournée
              ClipRect(
                child: Align(
                  alignment: Alignment.topCenter,
                  heightFactor: 0.42,
                  child: ShaderMask(
                    shaderCallback: (r) => const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x47FFFFFF), Color(0x00FFFFFF)],
                      stops: [0, 0.9],
                    ).createShader(r),
                    blendMode: BlendMode.dstIn,
                    child: Transform.flip(flipY: true, child: img),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ouvre le Cover Flow sur l'album en cours (ou le premier).
Future<void> openCoverflow(
  BuildContext context, {
  void Function(Album album)? onOpen,
}) async {
  final app = AppScope.of(context);
  final albums = await app.library.albums().first;
  if (!context.mounted || albums.isEmpty) return;
  final now = app.player.current.track;
  final playing = now == null ? null : albumKeyOf(now);
  final i = albums.indexWhere((a) => a.key == playing);
  await Navigator.of(context).push(
    PageRouteBuilder<void>(
      pageBuilder: (_, _, _) => CoverflowScreen(
        albums: albums,
        initial: i < 0 ? 0 : i,
        onOpen: onOpen,
      ),
      transitionsBuilder: (_, a, _, child) =>
          FadeTransition(opacity: a, child: child),
    ),
  );
}
