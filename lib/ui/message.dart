import 'package:flutter/material.dart';

import '../theme/colors.dart';

/// Petit message en bas de la fenêtre (erreur d'écriture, Corbeille refusée…).
void showMessage(BuildContext context, String text) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      backgroundColor: context.colors.bar,
      content: Text(text, style: TextStyle(color: context.colors.text)),
    ),
  );
}
