import 'package:flutter/material.dart';

import 'colors.dart';

ThemeData lafleurTheme() {
  const c = LafleurColors.dark;
  final base = ThemeData(
    brightness: Brightness.dark,
    fontFamily: 'Inter',
    useMaterial3: true,
  );
  return base.copyWith(
    scaffoldBackgroundColor: c.bg,
    colorScheme: base.colorScheme.copyWith(
      primary: c.pink,
      onPrimary: c.ink,
      surface: c.panel,
      onSurface: c.text,
      outline: c.line,
    ),
    dividerColor: c.line,
    textSelectionTheme: TextSelectionThemeData(cursorColor: c.pink),
    extensions: const [LafleurColors.dark],
  );
}
