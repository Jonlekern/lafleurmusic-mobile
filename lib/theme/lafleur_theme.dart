import 'package:flutter/material.dart';

import 'colors.dart';

ThemeData lafleurTheme() {
  final base = ThemeData(
    brightness: Brightness.dark,
    fontFamily: 'Inter',
    useMaterial3: true,
  );
  return base.copyWith(
    scaffoldBackgroundColor: LafleurColors.bg,
    colorScheme: base.colorScheme.copyWith(
      primary: LafleurColors.pink,
      onPrimary: LafleurColors.ink,
      surface: LafleurColors.panel,
      onSurface: LafleurColors.text,
      outline: LafleurColors.line,
    ),
    dividerColor: LafleurColors.line,
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: LafleurColors.pink,
    ),
  );
}
