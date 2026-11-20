import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/theme/colors.dart';
import 'package:lafleurmusic/theme/lafleur_theme.dart';
import 'package:lafleurmusic/ui/cover_image.dart';
import 'package:lafleurmusic/ui/phone/album_screen.dart';

import '../ui/fonts.dart';
import '../ui/phone_fixture.dart';

/// Mode clair (plan 7, tâche 2) : l'appli suit le réglage du téléphone.
void main() {
  setUpAll(loadFonts);

  Color? textColor(WidgetTester tester, String text) => tester
      .renderObject<RenderParagraph>(find.text(text).first)
      .text
      .style
      ?.color;

  Color bg(WidgetTester tester) =>
      tester.widget<Scaffold>(find.byType(Scaffold).last).backgroundColor!;

  String logo(WidgetTester tester) {
    final img = tester.widget<Image>(
      find.byWidgetPredicate(
        (w) =>
            w is Image &&
            w.image is AssetImage &&
            (w.image as AssetImage).assetName.contains('logo-texte-grand'),
      ),
    );
    return (img.image as AssetImage).assetName;
  }

  Finder coverEdges() => find.descendant(
    of: find.byType(CoverImage),
    matching: find.byWidgetPredicate(
      (w) =>
          w is DecoratedBox &&
          w.position == DecorationPosition.foreground &&
          (w.decoration as BoxDecoration).border?.top.color ==
              const Color(0xFFE4E4E4),
    ),
  );

  test('jetons clairs : les valeurs de la maquette 5', () {
    const c = LafleurColors.light;
    expect(c.bg, const Color(0xFFFFFFFF));
    expect(c.bar, const Color(0xFFF3F3F3));
    expect(c.text, const Color(0xFF111111));
    expect(c.sub, const Color(0xFF6E6E6E));
    expect(c.line, const Color(0xFFE4E4E4));
    expect(c.rule, const Color(0xFFEEEEEE));
    expect(c.border, const Color(0xFFCFCFCF));
    expect(c.outlineDim, const Color(0xFFB8B8B8));
    expect(c.pink, const Color(0xFFF26EF2));
    expect(c.pink, LafleurColors.dark.pink);
    expect(c.coverEdge, const Color(0xFFE4E4E4));
    expect(LafleurColors.dark.coverEdge.a, 0); // sombre : pas de filet
  });

  test('texte sur rose : #111 dans les deux modes', () {
    expect(LafleurColors.light.onPink, const Color(0xFF111111));
    expect(LafleurColors.dark.onPink, const Color(0xFF111111));
    expect(LafleurColors.light.ink, const Color(0xFF111111));
  });

  test('un thème par mode, le sombre par défaut', () {
    final light = lafleurTheme(Brightness.light);
    final dark = lafleurTheme(Brightness.dark);
    expect(light.brightness, Brightness.light);
    expect(light.extension<LafleurColors>(), LafleurColors.light);
    expect(light.scaffoldBackgroundColor, const Color(0xFFFFFFFF));
    expect(light.colorScheme.onPrimary, const Color(0xFF111111));
    expect(dark.brightness, Brightness.dark);
    expect(dark.extension<LafleurColors>(), LafleurColors.dark);
    expect(lafleurTheme().extension<LafleurColors>(), LafleurColors.dark);
  });

  test('l\'appli suit le téléphone : thème clair, thème sombre, système', () {
    final app = lafleurMaterialApp(home: const SizedBox());
    expect(app.themeMode, ThemeMode.system);
    expect(app.theme!.extension<LafleurColors>(), LafleurColors.light);
    expect(app.darkTheme!.extension<LafleurColors>(), LafleurColors.dark);
  });

  testWidgets(
    'changer de mode, appli ouverte : tout l\'écran change, la lecture continue',
    (tester) async {
      final f = await pumpPhone(tester, brightness: Brightness.light);
      await tester.tap(find.text('Studio Lafleur'));
      await tester.pumpAndSettle();
      await settle(tester);
      expect(find.byType(AlbumScreen), findsOneWidget);
      expect(bg(tester), const Color(0xFFFFFFFF));
      expect(textColor(tester, 'Ocean Drive'), const Color(0xFF111111));
      expect(logo(tester), 'assets/logo-texte-grand-noir.png');
      final state = f.player.current;
      final queue = f.player.queue;
      final calls = [...f.player.calls];

      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pumpAndSettle();

      expect(find.byType(AlbumScreen), findsOneWidget); // même écran
      expect(bg(tester), LafleurColors.dark.bg);
      expect(textColor(tester, 'Ocean Drive'), LafleurColors.dark.text);
      expect(logo(tester), 'assets/logo-texte-grand.png');
      expect(f.player.current, same(state));
      expect(f.player.queue, same(queue));
      expect(f.player.calls, calls);

      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      await tester.pumpAndSettle();
      expect(bg(tester), const Color(0xFFFFFFFF));
      expect(textColor(tester, 'Ocean Drive'), const Color(0xFF111111));
      expect(f.player.calls, calls);
    },
  );

  testWidgets('barres du système lisibles dans les deux modes', (tester) async {
    await pumpPhone(tester, brightness: Brightness.light);
    SystemUiOverlayStyle style() => tester
        .widget<AnnotatedRegion<SystemUiOverlayStyle>>(
          find.byType(AnnotatedRegion<SystemUiOverlayStyle>).first,
        )
        .value;
    expect(style().statusBarIconBrightness, Brightness.dark); // Android
    expect(style().statusBarBrightness, Brightness.light); // iOS
    expect(style().systemNavigationBarIconBrightness, Brightness.dark);
    expect(style().systemNavigationBarColor, const Color(0xFFFFFFFF));

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();
    expect(style().statusBarIconBrightness, Brightness.light);
    expect(style().statusBarBrightness, Brightness.dark);
    expect(style().systemNavigationBarIconBrightness, Brightness.light);
    expect(style().systemNavigationBarColor, LafleurColors.dark.bg);
  });

  testWidgets('pochettes : un filet #E4E4E4 en clair', (tester) async {
    await pumpPhone(tester, brightness: Brightness.light);
    expect(find.byType(CoverImage), findsWidgets);
    expect(
      coverEdges().evaluate().length,
      find.byType(CoverImage).evaluate().length,
    );
  });

  testWidgets('pochettes : aucun filet en sombre', (tester) async {
    await pumpPhone(tester);
    expect(find.byType(CoverImage), findsWidgets);
    expect(coverEdges(), findsNothing);
    expect(
      find.descendant(
        of: find.byType(CoverImage),
        matching: find.byWidgetPredicate(
          (w) =>
              w is DecoratedBox && w.position == DecorationPosition.foreground,
        ),
      ),
      findsNothing,
    );
  });

  testWidgets('texte sur rose : #111 à l\'écran en clair', (tester) async {
    await pumpPhone(tester, brightness: Brightness.light);
    // l'album en cours est surligné en rose sur l'Accueil
    expect(textColor(tester, 'Studio Lafleur'), const Color(0xFF111111));
  });

  testWidgets('un test clair voit bien les couleurs claires', (tester) async {
    await pumpPhone(tester, brightness: Brightness.light);
    expect(
      tester.element(find.byType(Scaffold).last).colors,
      LafleurColors.light,
    );
  });

  testWidgets('thème LAFLEUR sans ses couleurs : erreur, pas de sombre muet', (
    tester,
  ) async {
    final half = lafleurTheme(Brightness.light).copyWith(extensions: []);
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        theme: half,
        home: Builder(
          builder: (c) {
            ctx = c;
            return const SizedBox();
          },
        ),
      ),
    );
    expect(() => ctx.colors, throwsAssertionError);
  });

  testWidgets('MaterialApp nu (anciens tests) : le sombre, sans erreur', (
    tester,
  ) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) {
            ctx = c;
            return const SizedBox();
          },
        ),
      ),
    );
    expect(ctx.colors, LafleurColors.dark);
  });
}
