import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/theme/colors.dart';
import 'package:lafleurmusic/theme/lafleur_theme.dart';
import 'package:lafleurmusic/ui/classic/click_wheel.dart';

import '../fonts.dart';

void main() {
  testWidgets('maquette 6 A : la molette', (tester) async {
    await loadFonts();
    tester.view.physicalSize = const Size(310, 310);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: lafleurTheme(),
        home: Scaffold(
          backgroundColor: LafleurColors.dark.bg,
          body: Center(child: ClickWheel(onRotate: (_) {})),
        ),
      ),
    );
    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/6-molette.png'),
    );
  }, tags: ['golden']);
}
