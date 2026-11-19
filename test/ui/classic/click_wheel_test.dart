import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/theme/lafleur_theme.dart';
import 'package:lafleurmusic/ui/classic/click_wheel.dart';

/// Ce que la molette a fait : crans (+1 / -1), boutons, petits clics.
class Log {
  final steps = <int>[];
  final buttons = <String>[];
  var clicks = 0;
}

Future<Log> pump(WidgetTester tester) async {
  final log = Log();
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'HapticFeedback.vibrate' &&
          call.arguments == 'HapticFeedbackType.selectionClick') {
        log.clicks++;
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: lafleurTheme(),
      home: Scaffold(
        body: Center(
          child: ClickWheel(
            onRotate: log.steps.add,
            onSelect: () => log.buttons.add('select'),
            onMenu: () => log.buttons.add('menu'),
            onPrevious: () => log.buttons.add('previous'),
            onNext: () => log.buttons.add('next'),
            onPlayPause: () => log.buttons.add('playpause'),
          ),
        ),
      ),
    ),
  );
  return log;
}

/// Un point de la molette : [deg] dans le sens des aiguilles depuis midi, à [r] du centre.
Offset at(WidgetTester tester, double deg, [double r = 110]) {
  final c = tester.getCenter(find.byType(ClickWheel));
  final a = deg * math.pi / 180;
  return c + Offset(math.sin(a) * r, -math.cos(a) * r);
}

/// Tourne de [from] à [to] degrés par pas de [by] degrés, [ms] millisecondes entre deux pas.
Future<void> turn(
  WidgetTester tester,
  double from,
  double to, {
  double by = 5,
  int ms = 16,
}) async {
  final g = await tester.startGesture(at(tester, from));
  final dir = to > from ? 1 : -1;
  var deg = from;
  while ((to - deg) * dir > 1e-9) {
    deg += dir * math.min(by, (to - deg).abs());
    await g.moveTo(at(tester, deg));
    await tester.pump(Duration(milliseconds: ms));
  }
  await g.up();
  await tester.pump();
}

void main() {
  testWidgets(
    'sens des aiguilles : un cran +1 tous les 15°, un petit clic chacun',
    (tester) async {
      final log = await pump(tester);
      await turn(tester, 0, 90);
      expect(log.steps, List.filled(6, 1));
      expect(log.clicks, 6);
      expect(log.buttons, isEmpty);
    },
  );

  testWidgets('sens inverse : un cran -1 tous les 15°', (tester) async {
    final log = await pump(tester);
    await turn(tester, 200, 155);
    expect(log.steps, [-1, -1, -1]);
    expect(log.clicks, 3);
  });

  testWidgets('moins de 15° : aucun cran, et pas une tape', (tester) async {
    final log = await pump(tester);
    await turn(tester, 30, 44);
    expect(log.steps, isEmpty);
    expect(log.clicks, 0);
    expect(log.buttons, isEmpty);
  });

  testWidgets('aller puis retour dans le même geste', (tester) async {
    final log = await pump(tester);
    final g = await tester.startGesture(at(tester, 90));
    for (var d = 95.0; d <= 135; d += 5) {
      await g.moveTo(at(tester, d));
    }
    for (var d = 130.0; d >= 75; d -= 5) {
      await g.moveTo(at(tester, d));
    }
    await g.up();
    expect(log.steps, [1, 1, 1, -1, -1, -1, -1]);
  });

  testWidgets('passer par 9 heures (±180° de atan2) dans les deux sens', (
    tester,
  ) async {
    final log = await pump(tester);
    // de 8 heures à 10 heures (240° → 300°) : 60°, 4 crans, puis le retour
    await turn(tester, 240, 300, by: 10);
    await turn(tester, 300, 240, by: 10);
    expect(log.steps, [1, 1, 1, 1, -1, -1, -1, -1]);
  });

  group('geste très rapide : un tour complet en 0,2 s', () {
    for (final by in [15.0, 30.0, 45.0, 90.0, 120.0]) {
      testWidgets('${360 ~/ by} événements de ${by.toInt()}° : 24 crans', (
        tester,
      ) async {
        final log = await pump(tester);
        final ms = 200 ~/ (360 / by);
        await turn(tester, 0, 360, by: by, ms: ms);
        expect(log.steps, List.filled(24, 1));
        expect(log.clicks, 24);
        expect(log.buttons, isEmpty);
      });
    }

    testWidgets('dans l\'autre sens aussi, deux tours', (tester) async {
      final log = await pump(tester);
      await turn(tester, 0, -720, by: 30, ms: 8);
      expect(log.steps, List.filled(48, -1));
    });
  });

  group('doigt qui passe par le centre', () {
    testWidgets('de MENU à ▶︎❙❙ en ligne droite : ni choix, ni cran', (
      tester,
    ) async {
      final log = await pump(tester);
      final g = await tester.startGesture(at(tester, 0, 115));
      for (var y = 105.0; y >= -115; y -= 10) {
        await g.moveTo(at(tester, 0, y));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await g.up();
      await tester.pump();
      expect(log.buttons, isEmpty);
      expect(log.steps, isEmpty);
    });

    testWidgets(
      'tourner puis lever le doigt sur le rond du milieu : pas de choix',
      (tester) async {
        final log = await pump(tester);
        final g = await tester.startGesture(at(tester, 0));
        for (var d = 5.0; d <= 45; d += 5) {
          await g.moveTo(at(tester, d));
        }
        for (var r = 100.0; r >= 0; r -= 20) {
          await g.moveTo(at(tester, 45, r));
        }
        await g.up();
        await tester.pump();
        expect(log.steps, [1, 1, 1]);
        expect(log.buttons, isEmpty);
      },
    );

    testWidgets('tremblement autour du centre exact : aucun cran parasite', (
      tester,
    ) async {
      final log = await pump(tester);
      final g = await tester.startGesture(at(tester, 0, 110));
      await g.moveTo(at(tester, 0, 60));
      await g.moveTo(at(tester, 0, 2));
      for (var d = 0.0; d <= 720; d += 40) {
        await g.moveTo(at(tester, d, 3));
      }
      await g.up();
      await tester.pump();
      expect(log.steps, isEmpty);
      expect(log.buttons, isEmpty);
    });

    testWidgets(
      'un seul saut de 60 pt par-dessus le centre : ni cran, ni choix',
      (tester) async {
        final log = await pump(tester);
        final g = await tester.startGesture(at(tester, 270, 110));
        await g.moveTo(at(tester, 270, 30));
        await tester.pump(const Duration(milliseconds: 16));
        await g.moveTo(
          at(tester, 90, 30),
        ); // de 30 pt à gauche à 30 pt à droite
        await tester.pump(const Duration(milliseconds: 16));
        await g.moveTo(at(tester, 90, 110));
        await g.up();
        await tester.pump();
        expect(log.steps, isEmpty);
        expect(log.buttons, isEmpty);
      },
    );
  });

  group('tapes', () {
    for (final (zone, deg, r) in [
      ('select', 0.0, 0.0),
      ('select', 130.0, 40.0),
      ('menu', 0.0, 110.0),
      ('next', 90.0, 110.0),
      ('playpause', 180.0, 110.0),
      ('previous', 270.0, 110.0),
      ('menu', 30.0, 90.0),
      ('next', 60.0, 90.0),
    ]) {
      testWidgets('$zone (${deg.toInt()}°, ${r.toInt()})', (tester) async {
        final log = await pump(tester);
        await tester.tapAt(at(tester, deg, r));
        await tester.pump();
        expect(log.buttons, [zone]);
        expect(log.steps, isEmpty);
        expect(log.clicks, 0);
      });
    }

    testWidgets('un léger tremblement reste une tape', (tester) async {
      final log = await pump(tester);
      final g = await tester.startGesture(at(tester, 0, 5));
      await g.moveBy(const Offset(3, 2));
      await g.up();
      await tester.pump();
      expect(log.buttons, ['select']);
    });

    testWidgets('hors du cercle (coin) : rien', (tester) async {
      final log = await pump(tester);
      final c = tester.getCenter(find.byType(ClickWheel));
      await tester.tapAt(c + const Offset(-130, -130));
      await tester.pump();
      expect(log.buttons, isEmpty);
    });

    testWidgets('un bouton absent (null) ne fait rien', (tester) async {
      final steps = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Center(child: ClickWheel(onRotate: steps.add)),
        ),
      );
      await tester.tapAt(tester.getCenter(find.byType(ClickWheel)));
      await tester.pump();
      expect(steps, isEmpty);
    });
  });

  testWidgets('VoiceOver / TalkBack : chaque zone est un bouton nommé', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final log = await pump(tester);
    for (final (label, zone) in [
      ('MENU', 'menu'),
      ('Previous track', 'previous'),
      ('Next track', 'next'),
      ('Play / pause', 'playpause'),
      ('Select', 'select'),
    ]) {
      final node = find.bySemanticsLabel(label);
      expect(
        tester.getSemantics(node),
        matchesSemantics(label: label, isButton: true, hasTapAction: true),
      );
      tester.semantics.tap(find.semantics.byLabel(label));
      await tester.pump();
      expect(log.buttons.last, zone);
    }
    handle.dispose();
  });

  testWidgets(
    'VoiceOver / TalkBack : augmenter / diminuer fait tourner d\'un cran',
    (tester) async {
      final handle = tester.ensureSemantics();
      final log = await pump(tester);
      final node = tester.getSemantics(find.byType(ClickWheel));
      expect(
        node.getSemanticsData().hasAction(SemanticsAction.increase),
        isTrue,
      );
      node.owner!.performAction(node.id, SemanticsAction.increase);
      node.owner!.performAction(node.id, SemanticsAction.increase);
      node.owner!.performAction(node.id, SemanticsAction.decrease);
      await tester.pump();
      expect(log.steps, [1, 1, -1]);
      expect(log.buttons, isEmpty);
      handle.dispose();
    },
  );

  testWidgets('VoiceOver / TalkBack : la molette a un nom et une valeur', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: ClickWheel(
            onRotate: (_) {},
            semanticLabel: 'Wheel',
            semanticValue: 'Albums',
          ),
        ),
      ),
    );
    expect(
      tester.getSemantics(find.byType(ClickWheel)),
      isSemantics(
        label: 'Wheel',
        value: 'Albums',
        hasIncreaseAction: true,
        hasDecreaseAction: true,
      ),
    );
    handle.dispose();
  });

  testWidgets(
    'tourner la molette dans une liste ne fait pas défiler la liste',
    (tester) async {
      final steps = <int>[];
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: ListView(
            controller: scroll,
            children: [
              const SizedBox(height: 100),
              Center(child: ClickWheel(onRotate: steps.add)),
              const SizedBox(height: 2000),
            ],
          ),
        ),
      );
      // de 3 heures à 9 heures par le bas : le doigt descend de 220 pt
      await turn(tester, 90, 270, by: 10);
      expect(steps, List.filled(12, 1));
      expect(scroll.offset, 0);
    },
  );
}
