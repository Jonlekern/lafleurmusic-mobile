import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/theme/colors.dart';
import 'package:lafleurmusic/theme/lafleur_theme.dart';

/// Fichiers où une couleur littérale reste permise, avec la raison.
const _allowed = <String, String>{
  'lib/ui/classic/classic_menu.dart': 'écran de l\'iPod Classic : look fixe',
  'lib/ui/classic/classic_now.dart': 'écran de l\'iPod Classic : look fixe',
  'lib/ui/classic/click_wheel.dart': 'molette de l\'iPod Classic : look fixe',
};

void main() {
  test('jetons sombres : les valeurs d\'avant le mode clair', () {
    const c = LafleurColors.dark;
    final actual = <String, Color>{
      'bg': c.bg,
      'bar': c.bar,
      'panel': c.panel,
      'line': c.line,
      'text': c.text,
      'sub': c.sub,
      'pink': c.pink,
      'ink': c.ink,
      'onPink': c.onPink,
      'onPinkBlack': c.onPinkBlack,
      'hairline': c.hairline,
      'coverBack': c.coverBack,
      'shadow': c.shadow,
      'scrim': c.scrim,
      'toastShade': c.toastShade,
      'thumb': c.thumb,
      'textBright': c.textBright,
      'textBody': c.textBody,
      'textLabel': c.textLabel,
      'textMuted': c.textMuted,
      'textDim': c.textDim,
      'textDimmer': c.textDimmer,
      'textFaint': c.textFaint,
      'textHighlight': c.textHighlight,
      'outlineDim': c.outlineDim,
      'border': c.border,
      'borderSoft': c.borderSoft,
      'divider': c.divider,
      'trackBar': c.trackBar,
      'raised': c.raised,
      'sheet': c.sheet,
      'dialog': c.dialog,
      'field': c.field,
      'inputFill': c.inputFill,
      'rowHover': c.rowHover,
      'rule': c.rule,
      'ruleTop': c.ruleTop,
      'pinkTint': c.pinkTint,
      'pinkWash': c.pinkWash,
      'coverGradTop': c.coverGradTop,
      'coverGradBottom': c.coverGradBottom,
      'shine': c.shine,
      'shineFade': c.shineFade,
      'danger': c.danger,
      'ok': c.ok,
      'jellyfin': c.jellyfin,
      'plex': c.plex,
    };
    final expected = <String, Color>{
      'bg': const Color(0xFF0D0D0D),
      'bar': const Color(0xFF1C1C1C),
      'panel': const Color(0xFF141414),
      'line': const Color(0xFF282828),
      'text': const Color(0xFFFFFFFF),
      'sub': const Color(0xFF969696),
      'pink': const Color(0xFFF26EF2),
      'ink': const Color(0xFF1F1F1F),
      'onPink': const Color(0xFF111111),
      'onPinkBlack': const Color(0xFF000000),
      'hairline': const Color(0xFF000000),
      'coverBack': const Color(0xFF000000),
      'shadow': const Color(0xFF000000),
      'scrim': const Color.from(alpha: 0.5, red: 0, green: 0, blue: 0),
      'toastShade': const Color(0x99000000),
      'thumb': const Color(0xFFFFFFFF),
      'textBright': const Color(0xFFDDDDDD),
      'textBody': const Color(0xFFCCCCCC),
      'textLabel': const Color(0xFFBBBBBB),
      'textMuted': const Color(0xFF999999),
      'textDim': const Color(0xFF888888),
      'textDimmer': const Color(0xFF777777),
      'textFaint': const Color(0xFF666666),
      'textHighlight': const Color(0xFFF2F2F2),
      'outlineDim': const Color(0xFF555555),
      'border': const Color(0xFF444444),
      'borderSoft': const Color(0xFF3A3A3A),
      'divider': const Color(0xFF333333),
      'trackBar': const Color(0xFF3D3D3D),
      'raised': const Color(0xFF2A2A2A),
      'sheet': const Color(0xFF232323),
      'dialog': const Color(0xFF1F1F1F),
      'field': const Color(0xFF161616),
      'inputFill': const Color(0xFF0F0F0F),
      'rowHover': const Color(0xFF262626),
      'rule': const Color(0xFF1E1E1E),
      'ruleTop': const Color(0xFF222222),
      'pinkTint': const Color(0xFF3A2240),
      'pinkWash': const Color(0xFF2A1A2A),
      'coverGradTop': const Color(0xFF1D1D1D),
      'coverGradBottom': const Color(0xFF050505),
      'shine': const Color(0x47FFFFFF),
      'shineFade': const Color(0x00FFFFFF),
      'danger': const Color(0xFFFF6B6B),
      'ok': const Color(0xFF5FD16F),
      'jellyfin': const Color(0xFF7AA7FF),
      'plex': const Color(0xFFE5A00D),
    };
    expect(actual.keys, expected.keys);
    for (final k in expected.keys) {
      expect(actual[k], expected[k], reason: k);
    }
  });

  test('le thème porte les couleurs, copyWith et lerp marchent', () {
    final t = lafleurTheme();
    expect(t.extension<LafleurColors>(), LafleurColors.dark);
    final other = LafleurColors.dark.copyWith(bg: const Color(0xFFFFFFFF));
    expect(other.bg, const Color(0xFFFFFFFF));
    expect(other.bar, LafleurColors.dark.bar);
    final mid = LafleurColors.dark.lerp(other, 1);
    expect(mid.bg, const Color(0xFFFFFFFF));
  });

  testWidgets('context.colors lit le thème', (tester) async {
    late LafleurColors seen;
    final light = LafleurColors.dark.copyWith(bg: const Color(0xFFFFFFFF));
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [light]),
        home: Builder(
          builder: (context) {
            seen = context.colors;
            return const SizedBox();
          },
        ),
      ),
    );
    expect(seen.bg, const Color(0xFFFFFFFF));
  });

  test('aucune couleur littérale sous lib/ui ni dans theme/widgets.dart', () {
    final literal = RegExp(
      r'Color\(0x|Color\.from|Colors\.(?!transparent\b)\w+',
    );
    final files = [
      ...Directory('lib/ui')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart')),
      File('lib/theme/widgets.dart'),
    ];
    final bad = <String>[];
    for (final f in files) {
      final path = f.path.replaceAll('\\', '/');
      if (_allowed.containsKey(path)) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.trimLeft().startsWith('//')) continue;
        if (literal.hasMatch(line)) bad.add('$path:${i + 1}: ${line.trim()}');
      }
    }
    expect(bad, isEmpty, reason: 'couleur en dur : utiliser context.colors');
  });

  test('les exceptions de la liste existent encore', () {
    for (final p in _allowed.keys) {
      expect(File(p).existsSync(), isTrue, reason: p);
    }
  });

  test('logo noir : même taille que le blanc', () {
    final white = File('assets/logo-texte-grand.png').readAsBytesSync();
    final black = File('assets/logo-texte-grand-noir.png').readAsBytesSync();
    // IHDR : largeur et hauteur aux octets 16 à 23
    expect(black.sublist(16, 24), white.sublist(16, 24));
  });
}
