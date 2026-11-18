import 'package:flutter/material.dart';

import '../theme/colors.dart';

/// Cadre des fenêtres 8b / 8c : fond #1F1F1F, bord #3A3A3A, coins 14, boutons en pilule à droite.
class DialogFrame extends StatelessWidget {
  const DialogFrame({
    super.key,
    required this.title,
    required this.children,
    required this.cancel,
    required this.confirm,
    required this.onConfirm,
    this.width = 520,
    this.confirmColor = LafleurColors.pink,
  });
  final String title, cancel, confirm;
  final List<Widget> children;
  final VoidCallback onConfirm;
  final double width;
  final Color confirmColor;

  static const body = TextStyle(
    color: Color(0xFFBBBBBB),
    fontSize: 14,
    height: 1.5,
  );

  @override
  Widget build(BuildContext context) {
    final pill = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
    );
    return Dialog(
      backgroundColor: const Color(0xFF1F1F1F),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFF3A3A3A)),
      ),
      child: SizedBox(
        width: width,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 26, 28, 26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              ...children,
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      shape: pill,
                      foregroundColor: LafleurColors.text,
                      side: const BorderSide(color: Color(0xFF444444)),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 14,
                      ),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      cancel,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      shape: pill,
                      backgroundColor: confirmColor,
                      foregroundColor: const Color(0xFF111111),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 14,
                      ),
                    ),
                    onPressed: onConfirm,
                    child: Text(
                      confirm,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Encadré gris foncé (renumérotation, note de remplacement).
class NoteBox extends StatelessWidget {
  const NoteBox({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(top: 14),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: LafleurColors.panel,
      borderRadius: BorderRadius.circular(8),
    ),
    child: DefaultTextStyle.merge(
      style: const TextStyle(
        color: Color(0xFFCCCCCC),
        fontSize: 13,
        height: 1.8,
      ),
      child: child,
    ),
  );
}
