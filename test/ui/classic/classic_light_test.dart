import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/theme/colors.dart';
import 'package:lafleurmusic/ui/classic/classic_now.dart';
import 'package:lafleurmusic/ui/classic/classic_shell.dart';

import '../../theme/light_mode_test.dart' show contrast;
import '../fonts.dart';
import '../phone_fixture.dart';
import 'classic_shell_test.dart' show press, rotateTo;

/// Mode Classic en clair (plan 7, décision T3a) : un iPod blanc. Écran clair au texte foncé,
/// molette blanche aux libellés gris lisibles ; le sombre garde ses couleurs d'avant.
void main() {
  setUpAll(loadFonts);

  Color textColor(WidgetTester tester, Finder text) =>
      tester.renderObject<RenderParagraph>(text.first).text.style!.color!;

  /// Le fond de l'écran façon iPod (le cadre aux coins de 10) autour de [text].
  Color screenOf(WidgetTester tester, Finder text) {
    for (final c in tester.widgetList<Container>(
      find.ancestor(of: text.first, matching: find.byType(Container)),
    )) {
      final d = c.decoration;
      if (d is BoxDecoration && d.borderRadius == BorderRadius.circular(10)) {
        return d.color!;
      }
    }
    throw StateError('pas d\'écran Classic autour du texte');
  }

  Future<void> openNow(WidgetTester tester) async {
    await rotateTo(tester, 'En cours');
    await press(tester, 'select');
    await tester.pumpAndSettle();
    expect(find.byType(ClassicNow), findsOneWidget);
  }

  test(
    'palette sombre : les couleurs d\'avant (goldens sombres inchangés)',
    () {
      const c = ClassicColors.dark;
      expect(c.screen, const Color(0xFF111111));
      expect(c.title, const Color(0xFF999999));
      expect(c.notOnPhone, const Color(0xFF555555));
      expect(c.artist, const Color(0xFFBBBBBB));
      expect(c.album, const Color(0xFF888888));
      expect(c.barTrack, const Color(0xFF2A2A2A));
      expect(c.volume, const Color(0xFFDDDDDD));
      expect(c.wheelEdge, const Color(0xFF2A2A2A));
      expect(c.wheelLabel, const Color(0xFFDDDDDD));
    },
  );

  test('palette claire : chaque texte lisible sur l\'écran et la molette', () {
    const c = ClassicColors.light;
    const t = LafleurColors.light;
    expect(c.screen.computeLuminance(), greaterThan(.5)); // écran clair
    expect(contrast(t.text, c.screen), greaterThanOrEqualTo(4.5));
    for (final ink in [c.title, c.artist, c.album]) {
      expect(
        contrast(ink, c.screen),
        greaterThanOrEqualTo(4.5),
        reason: '$ink',
      );
    }
    expect(contrast(c.volume, c.barTrack), greaterThanOrEqualTo(3));
    expect(contrast(c.wheelLabel, t.bar), greaterThanOrEqualTo(4.5)); // anneau
    expect(contrast(c.wheelEdge, t.bg), greaterThan(1.3)); // bord visible
  });

  testWidgets('clair : le menu se lit (texte foncé sur écran clair)', (
    tester,
  ) async {
    await pumpPhone(
      tester,
      home: const ClassicShell(),
      brightness: Brightness.light,
    );
    final row = find.text('Morceaux');
    final screen = screenOf(tester, row);
    expect(screen, ClassicColors.light.screen);
    expect(contrast(textColor(tester, row), screen), greaterThanOrEqualTo(4.5));
    final menu = find.text('MENU');
    expect(
      contrast(textColor(tester, menu), LafleurColors.light.bar),
      greaterThanOrEqualTo(4.5),
    );
  });

  testWidgets('clair : En cours se lit (titre, artiste, album)', (
    tester,
  ) async {
    final f = await pumpPhone(
      tester,
      home: const ClassicShell(),
      brightness: Brightness.light,
    );
    await openNow(tester);
    final t = f.player.current.track!;
    final title = find.text(t.title);
    final screen = screenOf(tester, title);
    expect(screen.computeLuminance(), greaterThan(.5));
    for (final text in [title, find.text(t.artist), find.text(t.album)]) {
      expect(
        contrast(textColor(tester, text), screen),
        greaterThanOrEqualTo(4.5),
      );
    }
  });

  testWidgets('sombre : l\'écran et la molette gardent leurs couleurs', (
    tester,
  ) async {
    await pumpPhone(tester, home: const ClassicShell());
    final row = find.text('Morceaux');
    expect(screenOf(tester, row), const Color(0xFF111111));
    expect(textColor(tester, row), const Color(0xFFFFFFFF));
    expect(textColor(tester, find.text('MENU')), const Color(0xFFDDDDDD));
  });
}
