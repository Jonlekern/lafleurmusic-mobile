import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../app_scope.dart';
import '../../l10n/strings.dart';
import '../../theme/colors.dart';

/// La molette du Mode Classic (maquette 6 A) : tourner le doigt sur l'anneau = un cran tous les
/// 15° (sens des aiguilles +1 = descendre, l'autre sens -1 = monter), avec un petit clic ;
/// une tape sans rotation sur une zone appuie sur son bouton.
class ClickWheel extends StatefulWidget {
  const ClickWheel({
    super.key,
    required this.onRotate,
    this.onSelect,
    this.onMenu,
    this.onPrevious,
    this.onNext,
    this.onPlayPause,
  });

  /// Appelé une fois par cran, avec +1 (sens des aiguilles) ou -1.
  final void Function(int steps) onRotate;

  /// Rond du milieu.
  final VoidCallback? onSelect;

  /// MENU, en haut de l'anneau.
  final VoidCallback? onMenu;

  /// ⏮ à gauche, ⏭ à droite, ▶︎❙❙ en bas.
  final VoidCallback? onPrevious, onNext, onPlayPause;

  /// Diamètre (maquette : 270 points).
  static const size = 270.0;

  /// Un cran.
  static const step = 15 * math.pi / 180;

  @override
  State<ClickWheel> createState() => _ClickWheelState();
}

const _radius = ClickWheel.size / 2;
const _hubRadius = 50.0;

/// Près du centre exact, l'angle du doigt n'a plus de sens : on n'y compte rien.
const _deadRadius = 20.0;

const _ring = LafleurColors.bar;
const _edge = Color(0xFF2A2A2A);
const _label = Color(0xFFDDDDDD);

class _ClickWheelState extends State<ClickWheel> {
  int? _pointer;
  Offset _down = Offset.zero;
  Offset _last = Offset.zero;
  double? _lastAngle;
  double _turned = 0;
  bool _moved = false;
  bool _rotated = false;

  static const _center = Offset(_radius, _radius);

  void _onDown(PointerDownEvent e) {
    if (_pointer != null) return; // un seul doigt fait tourner
    _pointer = e.pointer;
    _down = e.localPosition - _center;
    _last = _down;
    _lastAngle = _down.distance < _deadRadius ? null : _down.direction;
    _turned = 0;
    _moved = false;
    _rotated = false;
  }

  void _onMove(PointerMoveEvent e) {
    if (e.pointer != _pointer) return;
    final v = e.localPosition - _center;
    if ((v - _down).distance > kTouchSlop) _moved = true;
    final from = _last;
    _last = v;
    // Un doigt rapide peut sauter par-dessus le centre en un seul événement : c'est le trajet
    // qui compte, pas seulement le point d'arrivée.
    if (_distanceToCenter(from, v) < _deadRadius) {
      _lastAngle = null; // on repart de là où le doigt ressort
      return;
    }
    final a = v.direction;
    final last = _lastAngle;
    _lastAngle = a;
    if (last == null) return;
    // Le plus court chemin entre deux angles : passer par ±180° ne fait pas un tour à l'envers.
    var d = a - last;
    if (d > math.pi) d -= 2 * math.pi;
    if (d <= -math.pi) d += 2 * math.pi;
    _turned += d;
    const eps = 1e-9;
    while (_turned >= ClickWheel.step - eps) {
      _turned -= ClickWheel.step;
      _click(1);
    }
    while (_turned <= -ClickWheel.step + eps) {
      _turned += ClickWheel.step;
      _click(-1);
    }
  }

  /// Distance du centre au segment [a]–[b] (positions par rapport au centre).
  static double _distanceToCenter(Offset a, Offset b) {
    final ab = b - a;
    final len2 = ab.distanceSquared;
    if (len2 == 0) return b.distance;
    final t = (-(a.dx * ab.dx + a.dy * ab.dy) / len2).clamp(0.0, 1.0);
    return (a + ab * t).distance;
  }

  void _click(int dir) {
    _rotated = true;
    HapticFeedback.selectionClick();
    widget.onRotate(dir);
  }

  void _onUp(PointerUpEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    if (!_moved && !_rotated) _zoneAt(_down)?.call();
  }

  void _onCancel(PointerCancelEvent e) {
    if (e.pointer == _pointer) _pointer = null;
  }

  /// Le bouton sous [v] (par rapport au centre) : le rond du milieu, ou un quart de l'anneau.
  VoidCallback? _zoneAt(Offset v) {
    final r = v.distance;
    if (r <= _hubRadius) return widget.onSelect;
    if (r > _radius) return null;
    // degrés dans le sens des aiguilles depuis midi
    final deg = (math.atan2(v.dx, -v.dy) * 180 / math.pi + 360) % 360;
    if (deg < 45 || deg >= 315) return widget.onMenu;
    if (deg < 135) return widget.onNext;
    if (deg < 225) return widget.onPlayPause;
    return widget.onPrevious;
  }

  @override
  Widget build(BuildContext context) {
    final s =
        context.dependOnInheritedWidgetOfExactType<AppScope>()?.strings ??
        Strings.of(View.of(context).platformDispatcher.locale);
    Widget zone(Rect r, String label, VoidCallback? onTap) =>
        Positioned.fromRect(
          rect: r,
          child: Semantics(
            container: true,
            button: true,
            label: label,
            onTap: onTap,
            child: const SizedBox.expand(),
          ),
        );
    // La molette prend tout le geste : une liste ou une page autour ne défile pas en même temps.
    // VoiceOver / TalkBack : balayer vers le haut / le bas fait tourner d'un cran.
    return Semantics(
      container: true,
      onIncrease: () => widget.onRotate(1),
      onDecrease: () => widget.onRotate(-1),
      child: RawGestureDetector(
        gestures: {
          EagerGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
                EagerGestureRecognizer.new,
                (_) {},
              ),
        },
        child: Listener(
          onPointerDown: _onDown,
          onPointerMove: _onMove,
          onPointerUp: _onUp,
          onPointerCancel: _onCancel,
          child: CustomPaint(
            painter: const _WheelPainter(),
            size: const Size.square(ClickWheel.size),
            child: SizedBox.square(
              dimension: ClickWheel.size,
              child: Stack(
                children: [
                  Positioned(
                    top: 22,
                    left: 0,
                    right: 0,
                    child: IgnorePointer(
                      child: ExcludeSemantics(
                        child: Text(
                          s.wheelMenu,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            letterSpacing: 1,
                            color: _label,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                    ),
                  ),
                  zone(
                    const Rect.fromLTWH(75, 0, 120, 70),
                    s.wheelMenu,
                    widget.onMenu,
                  ),
                  zone(
                    const Rect.fromLTWH(0, 75, 70, 120),
                    s.previousTrack,
                    widget.onPrevious,
                  ),
                  zone(
                    const Rect.fromLTWH(200, 75, 70, 120),
                    s.nextTrack,
                    widget.onNext,
                  ),
                  zone(
                    const Rect.fromLTWH(75, 200, 120, 70),
                    s.playPause,
                    widget.onPlayPause,
                  ),
                  zone(
                    Rect.fromCircle(center: _center, radius: _hubRadius),
                    s.wheelSelect,
                    widget.onSelect,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// L'anneau, le rond du milieu, l'arc rose (décor, de 11 h 40 à 2 h 40) et ⏮ ⏭ ▶︎❙❙.
class _WheelPainter extends CustomPainter {
  const _WheelPainter();

  static const _c = Offset(_radius, _radius);

  @override
  void paint(Canvas canvas, Size size) {
    final edge = Paint()
      ..color = _edge
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas
      ..drawCircle(_c, _radius, Paint()..color = _ring)
      ..drawCircle(_c, _radius - .5, edge)
      ..drawCircle(_c, _hubRadius, Paint()..color = LafleurColors.bg)
      ..drawCircle(_c, _hubRadius - .5, edge);

    // CSS : bordure haute de 3 px tournée de 35°, soit de -10° à 80° depuis midi
    const deg = math.pi / 180;
    canvas.drawArc(
      Rect.fromCircle(center: _c, radius: _radius - 1.5),
      -100 * deg,
      90 * deg,
      false,
      Paint()
        ..color = LafleurColors.pink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );

    final ink = Paint()..color = _label;
    // ⏮ / ⏭ : une barre et deux triangles, 14 × 8, à 26 du bord
    void skip(double left, bool next) {
      const w = 14.0, h = 8.0, top = _radius - h / 2;
      double x(double dx) => next ? left + w - dx : left + dx;
      canvas
        ..drawRect(
          Rect.fromLTRB(
            math.min(x(0), x(3)),
            top,
            math.max(x(0), x(3)),
            top + h,
          ),
          ink,
        )
        ..drawPath(_triangle(x(3), x(8.5), top, h), ink)
        ..drawPath(_triangle(x(8.5), x(14), top, h), ink);
    }

    skip(26, false);
    skip(ClickWheel.size - 26 - 14, true);

    // ▶︎❙❙ : 21 × 13, à 24 du bas
    const h = 13.0, w = 21.0;
    const left = _radius - w / 2, top = ClickWheel.size - 24 - h;
    canvas
      ..drawPath(_triangle(left + 12, left, top, h), ink)
      ..drawRect(Rect.fromLTWH(left + 13, top + 1.5, 3.5, h - 3), ink)
      ..drawRect(Rect.fromLTWH(left + 17.5, top + 1.5, 3.5, h - 3), ink);
  }

  /// Triangle de pointe en [tipX], de base verticale en [baseX], haut [top], hauteur [h].
  static Path _triangle(double tipX, double baseX, double top, double h) =>
      Path()
        ..moveTo(tipX, top + h / 2)
        ..lineTo(baseX, top)
        ..lineTo(baseX, top + h)
        ..close();

  /// Seul le disque répond au doigt, pas les coins du carré.
  @override
  bool hitTest(Offset position) => (position - _c).distance <= _radius;

  @override
  bool shouldRepaint(_WheelPainter old) => false;
}
