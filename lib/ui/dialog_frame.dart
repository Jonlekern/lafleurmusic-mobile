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
    this.inset = const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
    this.confirmColor,
  });
  final String title, cancel, confirm;
  final List<Widget> children;
  final VoidCallback onConfirm;
  final double width;
  final EdgeInsets inset; // marge autour de la fenêtre (étroite sur téléphone)
  final Color? confirmColor; // le rose du mode, par défaut

  static TextStyle body(BuildContext context) =>
      TextStyle(color: context.colors.textLabel, fontSize: 14, height: 1.5);

  @override
  Widget build(BuildContext context) {
    final pill = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
    );
    return Dialog(
      insetPadding: inset,
      backgroundColor: context.colors.dialog,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: context.colors.borderSoft),
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
                      foregroundColor: context.colors.text,
                      side: BorderSide(color: context.colors.border),
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
                      backgroundColor: confirmColor ?? context.colors.pink,
                      foregroundColor: context.colors.onPink,
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
      color: context.colors.panel,
      borderRadius: BorderRadius.circular(8),
    ),
    child: DefaultTextStyle.merge(
      style: TextStyle(
        color: context.colors.textBody,
        fontSize: 13,
        height: 1.8,
      ),
      child: child,
    ),
  );
}
