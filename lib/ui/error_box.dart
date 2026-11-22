import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/colors.dart';

/// Ce qui remplace un morceau d'écran qui a planté, hors débogage. Flutter met un rectangle gris
/// muet ; on y écrit la cause en petit, pour qu'une capture d'écran suffise à la trouver
/// (Johnny 22.11 : un carré gris sur l'Accueil après le Cover Flow, introuvable sans la cause).
class ErrorBox extends StatelessWidget {
  const ErrorBox(this.details, {super.key});
  final FlutterErrorDetails details;

  /// La cause en quelques lignes : le type et le message de l'erreur, puis le premier endroit de
  /// l'appli (lib/) dans la pile, s'il y en a un.
  static String describe(FlutterErrorDetails d) {
    final lines = <String>[
      '${d.exception.runtimeType}: ${d.exceptionAsString()}'
          .split('\n')
          .take(3)
          .join(' '),
    ];
    final here = d.stack
        ?.toString()
        .split('\n')
        .firstWhere(
          (l) => l.contains('package:lafleurmusic/'),
          orElse: () => '',
        );
    if (here != null && here.isNotEmpty) {
      lines.add(here.replaceFirst(RegExp(r'^#\d+\s+'), '').trim());
    }
    final text = lines.join('\n');
    return text.length > 400 ? '${text.substring(0, 400)}…' : text;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      color: c.divider,
      padding: const EdgeInsets.all(8),
      alignment: Alignment.topLeft,
      child: Text(
        'Erreur :\n${describe(details)}',
        textDirection: TextDirection.ltr,
        style: TextStyle(color: c.textMuted, fontSize: 10, height: 1.3),
      ),
    );
  }
}

/// À appeler au démarrage : hors débogage, les morceaux d'écran qui plantent montrent leur cause.
void installErrorBox() {
  if (kDebugMode) return;
  ErrorWidget.builder = (details) => ErrorBox(details);
}
