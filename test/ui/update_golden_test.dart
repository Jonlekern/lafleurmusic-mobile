// Pixel comparison: run on macOS only (CI job goldens), see dart_test.yaml.
@Tags(['golden'])
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/ui/update_sheet.dart';

import 'fonts.dart';
import 'phone_fixture.dart';
import 'update_fixture.dart';

/// Maquette 19 : A le bandeau sur l'Accueil, B la feuille Android (barre à 62 %), C la feuille
/// iPhone ; sombre et clair (-light).
void main() {
  setUpAll(() async {
    await loadFonts();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  setUp(() {
    UpdateHooks.install = (_) async => true;
    UpdateHooks.launch = (_) async => true;
    UpdateHooks.cacheDir = () async => Directory('/cache');
  });
  tearDown(UpdateHooks.reset);

  Future<FakeUpdateService> start(
    WidgetTester tester,
    Brightness mode,
    TargetPlatform platform,
  ) async {
    debugDefaultTargetPlatformOverride = platform;
    final service = FakeUpdateService(available: update0110);
    await pumpPhone(tester, images: true, brightness: mode, update: service);
    return service;
  }

  Future<void> shot(String name) => expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('goldens/$name.png'),
  );

  for (final (mode, sfx) in goldenModes) {
    testWidgets(inMode(mode, '19 A bandeau sur l\'Accueil'), (tester) async {
      await start(tester, mode, TargetPlatform.iOS);
      await shot('phone-19a$sfx');
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets(inMode(mode, '19 B feuille Android, 62 %'), (tester) async {
      final service = await start(tester, mode, TargetPlatform.android);
      await tester.tap(find.text('Mettre à jour'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('updateAction')));
      await tester.pump();
      service.progress!(0.62);
      await tester.pumpAndSettle();
      await shot('phone-19b$sfx');
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets(inMode(mode, '19 C feuille iPhone'), (tester) async {
      await start(tester, mode, TargetPlatform.iOS);
      await tester.tap(find.text('Mettre à jour'));
      await tester.pumpAndSettle();
      await shot('phone-19c$sfx');
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
