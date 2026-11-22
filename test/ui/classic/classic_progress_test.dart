import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/player/player.dart';
import 'package:lafleurmusic/ui/classic/classic_now.dart';
import 'package:lafleurmusic/ui/classic/classic_shell.dart';
import 'package:lafleurmusic/ui/classic/click_wheel.dart';

import '../fonts.dart';
import '../phone_fixture.dart';
import 'classic_now_test.dart' show openClassic;
import 'classic_shell_test.dart' show press, rotate, wheel;

const _row = Key('classic-now-volume-row');
const _bar = Key('classic-now-progress-bar');

double _opacity(WidgetTester tester) =>
    tester.widget<AnimatedOpacity>(find.byKey(_row)).opacity;

/// L'opacité vraiment dessinée (après le fondu).
double _shown(WidgetTester tester) =>
    tester.renderObject<RenderAnimatedOpacity>(find.byKey(_row)).opacity.value;

/// Le peintre de la molette à l'écran.
WheelPainter _painter(WidgetTester tester) => tester
    .widgetList<CustomPaint>(
      find.descendant(
        of: find.byType(ClickWheel),
        matching: find.byType(CustomPaint),
      ),
    )
    .map((c) => c.painter)
    .whereType<WheelPainter>()
    .single;

void main() {
  setUpAll(loadFonts);

  group('l\'arc rose de la molette', () {
    test('part de midi, balaie fraction × 2π dans le sens des aiguilles', () {
      for (final f in [.1, .4, .75, 1.0]) {
        final (start, sweep) = WheelPainter.arc(f)!;
        expect(start, closeTo(-math.pi / 2, 1e-12));
        expect(sweep, closeTo(f * 2 * math.pi, 1e-12));
      }
      expect(WheelPainter.arc(null), isNull);
      expect(WheelPainter.arc(0), isNull);
      expect(WheelPainter.arc(double.nan), isNull);
    });

    test('la part jouée : pas de morceau ou durée 0 → pas d\'arc', () {
      expect(ClickWheel.progressOf(const PlayerState()), isNull);
      expect(
        ClickWheel.progressOf(
          const PlayerState(position: Duration(seconds: 5)),
        ),
        isNull,
      );
    });

    testWidgets('En cours : l\'arc suit la position du lecteur', (
      tester,
    ) async {
      final fx = await openClassic(tester);
      final st = fx.player.current;
      expect(st.track, isNotNull);
      // 1:33 sur 4:05
      expect(wheel(tester).progress, closeTo(93 / 245, .01));
      expect(_painter(tester).progress, wheel(tester).progress);
      fx.player.show(
        PlayerState(
          track: st.track,
          position: const Duration(seconds: 98),
          duration: const Duration(seconds: 245),
          playing: true,
        ),
      );
      await tester.pump();
      await tester.pump(); // l'événement, puis le dessin
      expect(wheel(tester).progress, closeTo(98 / 245, 1e-9));
    });

    testWidgets('le menu aussi ; sans morceau, pas d\'arc', (tester) async {
      final fx = await pumpPhone(tester, home: const ClassicShell());
      final st = fx.player.current;
      expect(st.track, isNotNull);
      fx.player.show(const PlayerState());
      await tester.pump();
      await tester.pump(); // l'événement, puis le dessin
      expect(wheel(tester).progress, isNull);
      expect(_painter(tester).progress, isNull);
      fx.player.show(
        PlayerState(
          track: st.track,
          position: const Duration(seconds: 60),
          duration: const Duration(seconds: 240),
        ),
      );
      await tester.pump();
      await tester.pump(); // l'événement, puis le dessin
      expect(wheel(tester).progress, closeTo(.25, 1e-9));
      expect(_painter(tester).progress, closeTo(.25, 1e-9));
    });

    testWidgets(
      'durée inconnue (flux) : pas d\'arc, la barre ne saute pas, rien ne casse',
      (tester) async {
        final fx = await openClassic(tester);
        final t = fx.player.current.track;
        fx.player.show(
          PlayerState(
            track: t,
            position: const Duration(seconds: 30),
            playing: true,
          ),
        );
        await tester.pump();
        await tester.pump(); // l'événement, puis le dessin
        expect(wheel(tester).progress, isNull);
        expect(_painter(tester).progress, isNull);
        final seeks = fx.player.calls.where((c) => c == 'seek').length;
        await tester.tapAt(tester.getCenter(find.byKey(_bar)));
        await tester.pump();
        // le mode « avancer » ne saute pas non plus
        await press(tester, 'select');
        await rotate(tester, 3);
        await tester.pump(const Duration(seconds: 1));
        expect(fx.player.calls.where((c) => c == 'seek').length, seeks);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('la barre de son, seulement en tournant', () {
    testWidgets('cachée au repos, sa place gardée, toujours lue', (
      tester,
    ) async {
      final h = tester.ensureSemantics();
      await openClassic(tester);
      expect(_opacity(tester), 0);
      expect(_shown(tester), 0);
      final hidden = tester.getRect(find.byKey(_row));
      expect(hidden.height, greaterThan(0)); // la place reste
      expect(
        tester.getSemantics(find.byKey(const Key('classic-now-volume-bar'))),
        isSemantics(label: 'Volume', value: '75 %'),
      );
      await rotate(tester, 1);
      await tester.pumpAndSettle(const Duration(milliseconds: 50));
      expect(_shown(tester), 1);
      expect(tester.getRect(find.byKey(_row)), hidden); // rien ne bouge
      h.dispose();
    });

    testWidgets(
      'tourner sans arrêt : visible tout du long, s\'efface 2 s après le dernier cran',
      (tester) async {
        await openClassic(tester);
        for (var i = 0; i < 8; i++) {
          await rotate(tester, i.isEven ? 1 : -1);
          await tester.pump(const Duration(milliseconds: 1500));
          expect(_opacity(tester), 1, reason: 'cran $i');
          expect(_shown(tester), 1, reason: 'cran $i');
        }
        // le dernier cran il y a 1,5 s : encore là
        await tester.pump(const Duration(milliseconds: 400));
        expect(_opacity(tester), 1);
        // 2 s : s'efface
        await tester.pump(const Duration(milliseconds: 100));
        expect(_opacity(tester), 0);
        await tester.pump(ClassicNow.volumeFade);
        expect(_shown(tester), 0);
      },
    );

    testWidgets('en butée, un cran la montre quand même', (tester) async {
      final fx = await openClassic(tester);
      await rotate(tester, 5); // 100
      await tester.pump(const Duration(seconds: 3));
      expect(_opacity(tester), 0);
      final calls = fx.player.calls.length;
      await rotate(tester, 1);
      expect(fx.player.calls.length, calls); // rien à régler
      expect(_opacity(tester), 1);
    });

    testWidgets('quitter l\'écran pendant ce temps : pas d\'erreur de timer', (
      tester,
    ) async {
      await openClassic(tester);
      await rotate(tester, 1);
      expect(_opacity(tester), 1);
      await press(tester, 'menu');
      await tester.pumpAndSettle();
      expect(find.byType(ClassicNow), findsNothing);
      await tester.pump(const Duration(seconds: 3));
      expect(tester.takeException(), isNull);
    });

    testWidgets('le mode « avancer » ne change pas : sa légende à la place', (
      tester,
    ) async {
      await openClassic(tester);
      await press(tester, 'select');
      expect(find.byKey(_row), findsNothing);
      expect(find.text('◆ Tourne pour avancer dans le morceau'), findsOne);
    });
  });
}
