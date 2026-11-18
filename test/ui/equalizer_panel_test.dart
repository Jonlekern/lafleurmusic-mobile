import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/l10n/strings.dart';
import 'package:lafleurmusic/player/equalizer.dart';
import 'package:lafleurmusic/theme/lafleur_theme.dart';
import 'package:lafleurmusic/ui/equalizer_panel.dart';

import 'fonts.dart';

Future<ValueNotifier<Equalizer>> pump(WidgetTester tester) async {
  desktopSize(tester);
  final eq = ValueNotifier(Equalizer.named('flat'));
  await tester.pumpWidget(
    MaterialApp(
      theme: lafleurTheme(),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 790,
            child: EqualizerPanel(
              equalizer: eq,
              strings: Strings.of(const Locale('fr')),
            ),
          ),
        ),
      ),
    ),
  );
  return eq;
}

void main() {
  testWidgets('ON / OFF', (tester) async {
    final eq = await pump(tester);
    await tester.tap(find.text('OFF'));
    await tester.pump();
    expect(eq.value.enabled, isTrue);
  });

  testWidgets('préréglage Rock', (tester) async {
    final eq = await pump(tester);
    await tester.tap(find.text('Rock'));
    await tester.pump();
    expect(eq.value.preset, 'rock');
    expect(eq.value.gains, Equalizer.presets['rock']);
    expect(eq.value.enabled, isTrue);
  });

  testWidgets('glisser une bande vers le haut : Mon réglage, gain positif', (
    tester,
  ) async {
    final eq = await pump(tester);
    await tester.drag(find.byKey(const Key('band-0')), const Offset(0, -80));
    await tester.pump();
    expect(eq.value.gains.first, greaterThan(0));
    expect(eq.value.preset, 'custom');
  });
}
