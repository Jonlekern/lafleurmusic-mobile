import 'package:flutter/widgets.dart';

/// Une barre de progression qu'on touche ou qu'on fait glisser (Johnny 20.11 : « pouvoir
/// glisser sur la barre de progression »). Toucher saute à l'endroit touché ; glisser fait
/// suivre la barre au doigt et ne saute qu'au lâcher (un seul saut, pas un par image).
class SeekArea extends StatefulWidget {
  const SeekArea({
    super.key,
    required this.total,
    required this.fraction,
    required this.onSeek,
    required this.builder,
    this.track,
  });

  /// La durée du morceau, en millisecondes (0 : rien à chercher).
  final int total;

  /// Où en est la lecture, de 0 à 1.
  final double fraction;
  final ValueChanged<Duration> onSeek;

  /// Le morceau en cours (son chemin, par exemple). S'il change pendant un glisser (fin du
  /// morceau), le glisser est abandonné : pas de saut dans le morceau suivant au lâcher.
  final Object? track;

  /// Dessine la barre à [fraction] : celle de la lecture, ou celle du doigt pendant un
  /// glisser ([dragging]).
  final Widget Function(BuildContext context, double fraction, bool dragging)
  builder;

  @override
  State<SeekArea> createState() => _SeekAreaState();
}

class _SeekAreaState extends State<SeekArea> {
  double? _drag; // pendant un glisser : où est le doigt, de 0 à 1
  Object? _dragTrack; // le morceau au début du glisser

  double _at(double dx, double width) =>
      width <= 0 ? 0 : (dx / width).clamp(0.0, 1.0);

  void _seek(double f) =>
      widget.onSeek(Duration(milliseconds: (f * widget.total).round()));

  bool get _sameTrack => widget.track == _dragTrack;

  @override
  void didUpdateWidget(SeekArea old) {
    super.didUpdateWidget(old);
    // un autre morceau pendant le glisser : la barre revient à la lecture, rien au lâcher
    if (_drag != null && !_sameTrack) _drag = null;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final on = widget.total > 0;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: on ? (d) => _seek(_at(d.localPosition.dx, c.maxWidth)) : null,
        onHorizontalDragStart: on
            ? (d) => setState(() {
                _dragTrack = widget.track;
                _drag = _at(d.localPosition.dx, c.maxWidth);
              })
            : null,
        onHorizontalDragUpdate: on
            ? (d) {
                if (!_sameTrack) return;
                setState(() => _drag = _at(d.localPosition.dx, c.maxWidth));
              }
            : null,
        onHorizontalDragEnd: on
            ? (_) {
                final f = _drag;
                setState(() => _drag = null);
                if (f != null && _sameTrack) _seek(f);
              }
            : null,
        onHorizontalDragCancel: () => setState(() => _drag = null),
        child: widget.builder(context, _drag ?? widget.fraction, _drag != null),
      );
    },
  );
}
