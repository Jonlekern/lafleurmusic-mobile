import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/library/models.dart';
import 'package:lafleurmusic/player/player.dart';
import 'package:lafleurmusic/ui/classic/classic_now.dart';
import 'package:lafleurmusic/ui/format.dart';

import '../fonts.dart';
import '../phone_fixture.dart';
import 'classic_now_test.dart' show openClassic, scrubbing;
import 'classic_shell_test.dart' show press, rotate, wheel;

const _bar = Key('classic-now-progress-bar');
const _knob = Key('classic-now-knob');

int _seeks(PhoneFixture f) => f.player.calls.where((c) => c == 'seek').length;

int _total(PhoneFixture f) => f.player.current.duration.inMilliseconds;

void _near(PhoneFixture f, double fraction) => expect(
  (f.player.lastSeek!.inMilliseconds - _total(f) * fraction).abs(),
  lessThan(_total(f) * 0.01),
);

/// Où est le rond sur la barre, de 0 à 1.
double _knobAt(WidgetTester tester) {
  final bar = tester.getRect(find.byKey(_bar));
  return (tester.getCenter(find.byKey(_knob)).dx - bar.left) / bar.width;
}

void main() {
  setUpAll(loadFonts);

  testWidgets(
    'maquette 20 A / B : le rond rose de 18 points, seulement sous le doigt',
    (tester) async {
      await openClassic(tester);
      // au repos (maquette 20 B) : pas de rond
      expect(find.byKey(_knob), findsNothing);
      final bar = tester.getRect(find.byKey(_bar));
      final g = await tester.startGesture(
        Offset(bar.left + bar.width * .2, bar.center.dy),
      );
      await g.moveBy(const Offset(20, 0));
      await tester.pump();
      await g.moveTo(Offset(bar.left + bar.width * .4, bar.center.dy));
      await tester.pump();
      // sous le doigt (maquette 20 A) : 18 points à l'échelle de l'écran Classic
      expect(find.byKey(_knob), findsOneWidget);
      final knob = tester.getRect(find.byKey(_knob));
      final k = bar.height / 6;
      expect(knob.width / k, closeTo(18, 0.01));
      expect(knob.height / k, closeTo(18, 0.01));
      expect(knob.center.dy, closeTo(bar.center.dy, 0.01));
      expect(_knobAt(tester), closeTo(.4, 0.01));
      await g.up();
      await tester.pump();
      expect(find.byKey(_knob), findsNothing);
    },
  );

  testWidgets('toucher la barre : un seul saut, au bon endroit', (
    tester,
  ) async {
    final f = await openClassic(tester);
    final bar = tester.getRect(find.byKey(_bar));
    await tester.tapAt(Offset(bar.left + bar.width * .3, bar.center.dy));
    await tester.pump();
    expect(_seeks(f), 1);
    _near(f, .3);
    // un peu au-dessus de la barre (6 points, c'est fin) : encore la barre
    await tester.tapAt(Offset(bar.left + bar.width * .8, bar.top - 8));
    await tester.pump();
    expect(_seeks(f), 2);
    _near(f, .8);
  });

  testWidgets('glisser : le rond suit le doigt, un seul saut au lâcher', (
    tester,
  ) async {
    final f = await openClassic(tester);
    final bar = tester.getRect(find.byKey(_bar));
    final g = await tester.startGesture(
      Offset(bar.left + bar.width * .1, bar.center.dy),
    );
    await g.moveBy(const Offset(20, 0));
    await tester.pump();
    await g.moveTo(Offset(bar.left + bar.width * .7, bar.center.dy));
    await tester.pump();
    expect(_seeks(f), 0);
    expect(_knobAt(tester), closeTo(.7, 0.01));
    await g.up();
    await tester.pump();
    expect(_seeks(f), 1);
    _near(f, .7);
  });

  testWidgets('glisser : les temps suivent le doigt', (tester) async {
    final f = await openClassic(tester);
    expect(find.text('1:33'), findsOneWidget);
    final bar = tester.getRect(find.byKey(_bar));
    final g = await tester.startGesture(
      Offset(bar.left + bar.width * .1, bar.center.dy),
    );
    await g.moveBy(const Offset(20, 0));
    await tester.pump();
    await g.moveTo(Offset(bar.left + bar.width * (149.5 / 245), bar.center.dy));
    await tester.pump();
    expect(_total(f), 245000);
    expect(find.text('2:29'), findsOneWidget);
    expect(find.text('−1:35'), findsOneWidget);
    expect(find.text('1:33'), findsNothing);
    await g.up();
    await tester.pump();
    // au lâcher, les temps restent au point choisi le temps que le lecteur y arrive
    expect(find.text(clock(f.player.lastSeek!)), findsOneWidget);
    expect(find.text('1:33'), findsNothing);
    // le faux lecteur n'y arrive jamais : au bout de 2 s, les temps reviennent à la lecture
    await tester.pump(ClassicNow.seekSettle);
    expect(find.text('1:33'), findsOneWidget);
  });

  testWidgets('durée 0 : la barre ne fait rien', (tester) async {
    final f = await openClassic(tester);
    f.player.show(PlayerState(track: f.player.current.track, playing: true));
    await tester.pump();
    await tester.pump();
    final bar = tester.getRect(find.byKey(_bar));
    await tester.tapAt(Offset(bar.left + bar.width * .5, bar.center.dy));
    await tester.drag(find.byKey(_bar), const Offset(80, 0));
    await tester.pump();
    expect(_seeks(f), 0);
    expect(find.byKey(_knob), findsNothing);
  });

  testWidgets('le morceau change pendant le glisser : pas de saut au lâcher', (
    tester,
  ) async {
    final f = await openClassic(tester);
    final bar = tester.getRect(find.byKey(_bar));
    final g = await tester.startGesture(
      Offset(bar.left + bar.width * .1, bar.center.dy),
    );
    await g.moveBy(const Offset(20, 0));
    await tester.pump();
    await g.moveTo(Offset(bar.left + bar.width * .9, bar.center.dy));
    await tester.pump();
    f.player.show(
      const PlayerState(
        track: Track(
          path: '/next.mp3',
          title: 'Suivant',
          artist: 'Quelqu’un',
          album: 'Ailleurs',
          durationMs: 200000,
          hasCover: false,
          size: 1,
        ),
        duration: Duration(milliseconds: 200000),
        playing: true,
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Suivant'), findsOneWidget);
    // le glisser est abandonné : plus de rond, la barre suit le nouveau morceau
    expect(find.byKey(_knob), findsNothing);
    await g.up();
    await tester.pump();
    expect(_seeks(f), 0);
  });

  testWidgets(
    'appui central : le losange, la molette avance comme avant, le doigt aussi',
    (tester) async {
      final f = await openClassic(tester);
      await press(tester, 'select');
      expect(scrubbing(tester), isTrue);
      await rotate(tester, 2);
      await tester.pump(const Duration(milliseconds: 200));
      expect(_seeks(f), 1);
      // le doigt sur la barre, en mode losange : le saut part tout de suite, là où on touche
      final bar = tester.getRect(find.byKey(_bar));
      await tester.tapAt(Offset(bar.left + bar.width * .5, bar.center.dy));
      await tester.pump();
      expect(_seeks(f), 2);
      _near(f, .5);
      await press(tester, 'select');
      expect(scrubbing(tester), isFalse);
    },
  );

  testWidgets(
    'après un toucher : tout reste au point choisi jusqu\'au lecteur, un cran part de là',
    (tester) async {
      final f = await openClassic(tester);
      final before = f.player.current;
      final bar = tester.getRect(find.byKey(_bar));
      await tester.tapAt(Offset(bar.left + bar.width * .6, bar.center.dy));
      await tester.pump();
      expect(_seeks(f), 1);
      _near(f, .6);
      final at = f.player.lastSeek!;
      final want = at.inMilliseconds / _total(f);
      // le faux lecteur dit encore l'ancienne position : rien ne revient en arrière
      for (var i = 0; i < 3; i++) {
        f.player.show(before);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(_fill(tester), closeTo(want, 1e-9));
        expect(find.text(clock(at)), findsOneWidget);
        expect(wheel(tester).progress, closeTo(want, 1e-9));
      }
      // un cran juste après part du point choisi, pas de l'ancienne position
      await press(tester, 'select');
      await rotate(tester, 1);
      await tester.pump(const Duration(milliseconds: 200));
      expect(f.player.lastSeek, at + ClassicNow.seekStep);
    },
  );

  testWidgets(
    'le lecteur arrive au point choisi : la barre suit de nouveau la lecture',
    (tester) async {
      final f = await openClassic(tester);
      final st = f.player.current;
      final bar = tester.getRect(find.byKey(_bar));
      await tester.tapAt(Offset(bar.left + bar.width * .6, bar.center.dy));
      await tester.pump();
      final at = f.player.lastSeek!;
      f.player.show(
        PlayerState(
          track: st.track,
          position: at,
          duration: st.duration,
          playing: true,
        ),
      );
      await tester.pump();
      await tester.pump();
      final later = at + const Duration(seconds: 10);
      f.player.show(
        PlayerState(
          track: st.track,
          position: later,
          duration: st.duration,
          playing: true,
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text(clock(later)), findsOneWidget);
      expect(_fill(tester), closeTo(later.inMilliseconds / _total(f), 1e-9));
    },
  );
}

double _fill(WidgetTester tester) => tester
    .widget<FractionallySizedBox>(find.byKey(const Key('classic-now-progress')))
    .widthFactor!;
