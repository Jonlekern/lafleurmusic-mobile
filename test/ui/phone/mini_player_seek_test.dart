import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/library/models.dart';
import 'package:lafleurmusic/player/player.dart';
import 'package:lafleurmusic/ui/phone/mini_player.dart';
import 'package:lafleurmusic/ui/phone/now_screen.dart';
import 'package:lafleurmusic/ui/phone/phone_shell.dart';

import '../fonts.dart';
import '../phone_fixture.dart';

/// Une liste qui défile au-dessus du mini-lecteur (comme un album ou une playlist).
const _list = Key('list');
final _home = PhoneScaffold(
  header: const SizedBox(height: 44),
  body: ListView.builder(
    key: _list,
    itemCount: 100,
    itemExtent: 50,
    itemBuilder: (_, i) => Text('ligne $i'),
  ),
);

int _seeks(PhoneFixture f) => f.player.calls.where((c) => c == 'seek').length;

double _scroll(WidgetTester tester) => tester
    .state<ScrollableState>(
      find.descendant(of: find.byKey(_list), matching: find.byType(Scrollable)),
    )
    .position
    .pixels;

/// Le fil rose : en haut du mini-lecteur, 3 points de haut.
Rect _line(WidgetTester tester) {
  final r = tester.getRect(find.byType(MiniPlayer));
  return Rect.fromLTWH(r.left, r.top, r.width, MiniPlayer.lineHeight);
}

Duration _total(PhoneFixture f) => f.player.current.duration;

void _near(PhoneFixture f, double fraction) {
  final want = _total(f).inMilliseconds * fraction;
  expect(
    (f.player.lastSeek!.inMilliseconds - want).abs(),
    lessThan(_total(f).inMilliseconds * 0.01),
  );
}

void main() {
  setUpAll(loadFonts);

  for (final landscape in [false, true]) {
    final where = landscape ? 'couché' : 'debout';

    Future<PhoneFixture> start(WidgetTester tester) async {
      final f = await pumpPhone(tester, home: _home);
      if (landscape) {
        landscapeSize(tester);
        await tester.pumpAndSettle();
      }
      return f;
    }

    testWidgets('$where : le fil reste de 3 points, la hauteur ne bouge pas', (
      tester,
    ) async {
      await start(tester);
      expect(tester.getSize(find.byType(MiniPlayer)).height, 3 + 64);
      final band = tester.getRect(find.byKey(const Key('mini-seek')));
      expect(band.height, MiniPlayer.touchBand);
      expect(band.center.dy, closeTo(_line(tester).center.dy, 0.01));
    });

    testWidgets('$where : toucher le fil saute, sans ouvrir En cours', (
      tester,
    ) async {
      final f = await start(tester);
      final line = _line(tester);
      await tester.tapAt(Offset(line.left + line.width * .25, line.center.dy));
      await tester.pumpAndSettle();
      expect(_seeks(f), 1);
      _near(f, .25);
      expect(find.byType(NowScreen), findsNothing);
      // la bande déborde sur la liste : 12 points au-dessus du fil, c'est encore le fil
      await tester.tapAt(Offset(line.left + line.width * .5, line.top - 12));
      await tester.pumpAndSettle();
      expect(_seeks(f), 2);
      _near(f, .5);
      expect(find.byType(NowScreen), findsNothing);
    });

    // Review Focus 2
    testWidgets(
      '$where : glisser le fil — un seul saut au lâcher, ni En cours ni défilement',
      (tester) async {
        final f = await start(tester);
        final line = _line(tester);
        expect(_scroll(tester), 0);
        final g = await tester.startGesture(
          Offset(line.left + line.width * .1, line.top - 10),
        );
        await g.moveBy(const Offset(20, -6));
        await tester.pump();
        await g.moveTo(Offset(line.left + line.width * .6, line.top - 30));
        await tester.pump();
        // le rond et le temps suivent le doigt ; la musique n'a pas encore sauté
        expect(_seeks(f), 0);
        expect(find.byKey(const Key('mini-seek-knob')), findsOneWidget);
        final at = Duration(
          milliseconds: (_total(f).inMilliseconds * .6).round(),
        );
        final s = at.inSeconds;
        expect(
          find.text('${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}'),
          findsOneWidget,
        );
        final knob = tester.getRect(find.byKey(const Key('mini-seek-knob')));
        expect(knob.size, const Size(14, 14));
        expect(knob.center.dx, closeTo(line.left + line.width * .6, 0.5));
        expect(knob.center.dy, closeTo(line.center.dy, 0.01));
        // le temps est au-dessus du rond
        final time = tester.getRect(find.byKey(const Key('mini-seek-time')));
        expect(time.bottom, lessThan(knob.top));
        await g.up();
        await tester.pumpAndSettle();
        expect(_seeks(f), 1);
        _near(f, .6);
        expect(find.byType(NowScreen), findsNothing);
        expect(_scroll(tester), 0);
        expect(find.byKey(const Key('mini-seek-knob')), findsNothing);
      },
    );

    testWidgets('$where : toucher ailleurs ouvre toujours En cours', (
      tester,
    ) async {
      final f = await start(tester);
      await tester.tap(find.text('Lafleur Surf'));
      await tester.pumpAndSettle();
      expect(find.byType(NowScreen), findsOneWidget);
      expect(_seeks(f), 0);
    });

    testWidgets('$where : la liste au-dessus défile toujours', (tester) async {
      await start(tester);
      final line = _line(tester);
      // plus haut que la bande, la liste reprend la main
      await tester.dragFrom(
        Offset(line.center.dx, line.top - 40),
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();
      expect(_scroll(tester), greaterThan(0));
    });
  }

  // Review Focus 3
  testWidgets('le morceau change pendant le glisser : pas de saut au lâcher', (
    tester,
  ) async {
    final f = await pumpPhone(tester, home: _home);
    final line = _line(tester);
    final g = await tester.startGesture(
      Offset(line.left + line.width * .2, line.center.dy),
    );
    await g.moveBy(const Offset(30, 0));
    await tester.pump();
    await g.moveTo(Offset(line.left + line.width * .9, line.center.dy));
    await tester.pump();
    expect(find.byKey(const Key('mini-seek-knob')), findsOneWidget);
    // fin du morceau : le suivant commence
    const next = Track(
      path: '/next.mp3',
      title: 'Suivant',
      artist: 'Quelqu’un',
      album: 'Ailleurs',
      durationMs: 200000,
      hasCover: false,
      size: 1,
    );
    f.player.show(
      const PlayerState(
        track: next,
        duration: Duration(milliseconds: 200000),
        playing: true,
      ),
    );
    await tester.pump(); // le flux du lecteur
    await tester.pump();
    expect(find.text('Suivant'), findsOneWidget);
    // la barre revient à la lecture du nouveau morceau
    expect(find.byKey(const Key('mini-seek-knob')), findsNothing);
    await g.moveBy(const Offset(-20, 0));
    await tester.pump();
    expect(find.byKey(const Key('mini-seek-knob')), findsNothing);
    await g.up();
    await tester.pumpAndSettle();
    expect(_seeks(f), 0);
    expect(find.byType(NowScreen), findsNothing);
  });
}
