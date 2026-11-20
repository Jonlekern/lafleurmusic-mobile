import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'colors.dart';

/// Le thème LAFLEUR d'un mode ; le sombre par défaut.
ThemeData lafleurTheme([Brightness brightness = Brightness.dark]) {
  final c = brightness == Brightness.light
      ? LafleurColors.light
      : LafleurColors.dark;
  final base = ThemeData(
    brightness: brightness,
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
    extensions: [c],
  );
}

/// L'appli suit le réglage clair / sombre du téléphone (pas de bouton) ; barre d'état et barre de
/// navigation Android assorties.
MaterialApp lafleurMaterialApp({
  required Widget home,
  String title = 'LAFLEURMUSIC',
}) => MaterialApp(
  title: title,
  debugShowCheckedModeBanner: false,
  theme: lafleurTheme(Brightness.light),
  darkTheme: lafleurTheme(Brightness.dark),
  themeMode: ThemeMode.system,
  builder: (context, child) =>
      SystemBars(child: child ?? const SizedBox.shrink()),
  home: home,
);

/// Icônes de la barre d'état et de la barre de navigation : foncées sur fond clair, claires sur
/// fond sombre ; la barre de navigation Android prend le fond de l'écran.
class SystemBars extends StatelessWidget {
  const SystemBars({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final light = context.lightColors;
    final icons = light ? Brightness.dark : Brightness.light;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: icons, // Android
        statusBarBrightness: light ? Brightness.light : Brightness.dark, // iOS
        systemNavigationBarColor: context.colors.bg,
        systemNavigationBarIconBrightness: icons,
        systemNavigationBarDividerColor: Colors.transparent,
      ),
      child: child,
    );
  }
}
