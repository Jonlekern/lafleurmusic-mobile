import 'package:flutter/material.dart';

import 'colors.dart';

/// Bouton pilule des maquettes : rose plein (primary) ou contour gris.
class PillButton extends StatelessWidget {
  const PillButton({
    super.key,
    required this.label,
    this.icon,
    this.primary = false,
    this.onPressed,
  });
  final String label;
  final IconData? icon;
  final bool primary;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final fg = primary ? LafleurColors.ink : LafleurColors.text;
    return Opacity(
      opacity: onPressed == null ? 0.4 : 1,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: primary ? LafleurColors.pink : null,
            border: primary ? null : Border.all(color: const Color(0xFF444444)),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: fg),
                const SizedBox(width: 8),
              ],
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Puce des maquettes (EQ, préréglages) : contour rose quand elle est active.
class LafleurChip extends StatelessWidget {
  const LafleurChip({
    super.key,
    required this.label,
    this.on = false,
    this.onPressed,
  });
  final String label;
  final bool on;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onPressed,
    borderRadius: BorderRadius.circular(14),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        border: Border.all(color: on ? LafleurColors.pink : LafleurColors.line),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          color: on ? LafleurColors.pink : LafleurColors.text,
        ),
      ),
    ),
  );
}

/// Barre du haut : logo texte LAFLEURMUSIC centré, contenu optionnel à droite (recherche).
class TitleBar extends StatelessWidget {
  const TitleBar({super.key, this.trailing});
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Container(
    height: 52,
    width: double.infinity,
    decoration: const BoxDecoration(
      color: LafleurColors.bar,
      border: Border(bottom: BorderSide(color: LafleurColors.line)),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 18),
    child: Stack(
      alignment: Alignment.center,
      children: [
        Image.asset('assets/logo-texte-grand.png', height: 20),
        if (trailing != null)
          Align(alignment: Alignment.centerRight, child: trailing),
      ],
    ),
  );
}

/// Contour en pointillés arrondi (zone de dépôt de la maquette 1).
class DashedBorderPainter extends CustomPainter {
  const DashedBorderPainter({
    required this.color,
    this.radius = 18,
    this.dash = 7,
    this.gap = 5,
    this.width = 2,
  });
  final Color color;
  final double radius, dash, gap, width;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = width
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
      );
    for (final m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += dash + gap) {
        canvas.drawPath(m.extractPath(d, d + dash), paint);
      }
    }
  }

  @override
  bool shouldRepaint(DashedBorderPainter old) => old.color != color;
}

/// Champ qui prend le clavier dès qu'il apparaît. `autofocus` ne le fait pas quand l'écran a déjà le clavier
/// (raccourcis espace, flèches), et l'espace mettait alors la musique en pause au lieu de s'écrire.
class FocusOnShow extends StatefulWidget {
  const FocusOnShow({super.key, required this.builder});
  final Widget Function(FocusNode node) builder;
  @override
  State<FocusOnShow> createState() => _FocusOnShowState();
}

class _FocusOnShowState extends State<FocusOnShow> {
  final _node = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _node.requestFocus();
    });
  }

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(_node);
}
