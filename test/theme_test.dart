import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/theme/colors.dart';
import 'package:lafleurmusic/theme/lafleur_theme.dart';

void main() {
  test('couleurs LAFLEURSTUDIO', () {
    expect(LafleurColors.pink, const Color(0xFFF26EF2));
    expect(LafleurColors.bg, const Color(0xFF0D0D0D));
    expect(LafleurColors.bar, const Color(0xFF1C1C1C));
  });
  test('thème sombre en Inter', () {
    final t = lafleurTheme();
    expect(t.brightness, Brightness.dark);
    expect(t.scaffoldBackgroundColor, LafleurColors.bg);
    expect(t.textTheme.bodyMedium?.fontFamily, 'Inter');
  });
}
