import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/theme/colors.dart';
import 'package:lafleurmusic/theme/lafleur_theme.dart';

void main() {
  test('couleurs LAFLEURSTUDIO', () {
    expect(LafleurColors.dark.pink, const Color(0xFFF26EF2));
    expect(LafleurColors.dark.bg, const Color(0xFF0D0D0D));
    expect(LafleurColors.dark.bar, const Color(0xFF1C1C1C));
  });
  test('thème sombre en Inter', () {
    final t = lafleurTheme();
    expect(t.brightness, Brightness.dark);
    expect(t.scaffoldBackgroundColor, LafleurColors.dark.bg);
    expect(t.textTheme.bodyMedium?.fontFamily, 'Inter');
  });
}
