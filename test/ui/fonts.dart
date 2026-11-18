import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Charge Inter pour que les images de référence ressemblent aux maquettes.
Future<void> loadFonts() async {
  final loader = FontLoader('Inter')
    ..addFont(rootBundle.load('assets/fonts/Inter-Regular.otf'))
    ..addFont(rootBundle.load('assets/fonts/Inter-Bold.otf'));
  await loader.load();
}

void desktopSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Les images d'assets se chargent hors de l'horloge simulée des tests.
Future<void> precacheAssets(WidgetTester tester, List<String> assets) async {
  final ctx = tester.element(find.byType(Scaffold).first);
  await tester.runAsync(() async {
    for (final a in assets) {
      await precacheImage(AssetImage(a), ctx);
    }
  });
  await tester.pumpAndSettle();
}
