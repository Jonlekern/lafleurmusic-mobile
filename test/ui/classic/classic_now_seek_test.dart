import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/library/models.dart';
import 'package:lafleurmusic/player/player.dart';

import '../fonts.dart';
import '../phone_fixture.dart';
import 'classic_now_test.dart' show openClassic, scrubbing;
import 'classic_shell_test.dart' show press, rotate;

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

  testWidgets('maquette 20 A : un rond rose de 18 points sur la position', (
    tester,
  ) async {
    final f = await openClassic(tester);
    expect(find.byKey(_knob), findsOneWidget);
    final bar = tester.getRect(find.byKey(_bar));
    final knob = tester.getRect(find.byKey(_knob));
    // l'écran Classic se resserre un peu sur les petits téléphones : 18 points à cette échelle
    final k = bar.height / 6;
    expect(knob.width / k, closeTo(18, 0.01));
    expect(knob.height / k, closeTo(18, 0.01));
    expect(knob.center.dy, closeTo(bar.center.dy, 0.01));
    final played =
        f.player.current.position.inMilliseconds / _total(f); // 1:33 sur 4:05
    expect(_knobAt(tester), closeTo(played, 0.01));
  });

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
    expect(_knobAt(tester), closeTo(0, 0.01)); // la lecture du nouveau morceau
    await g.up();
    await tester.pump();
    expect(_seeks(f), 0);
  });

  testWidgets(
    'appui central : le losange remplace le rond, la molette avance comme avant',
    (tester) async {
      final f = await openClassic(tester);
      await press(tester, 'select');
      expect(scrubbing(tester), isTrue);
      expect(find.byKey(_knob), findsNothing);
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
      expect(find.byKey(_knob), findsOneWidget);
    },
  );
}
