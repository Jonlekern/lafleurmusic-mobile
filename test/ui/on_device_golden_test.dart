// Pixel comparison: run on macOS only (CI job goldens), see dart_test.yaml.
@Tags(['golden'])
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/ui/phone/on_device_screen.dart';

import 'fonts.dart';
import 'phone/keep_screen_test.dart' show done;
import 'phone/on_device_screen_test.dart' show pumpOnDevice;

/// « Sur mon iPhone », 390 × 844 sur un iPhone : haut et bas de la maquette 4, mêmes données que le
/// mode démo (`LAFLEUR_DEMO_SCREEN=ondevice`).
void main() {
  setUpAll(() async {
    await loadFonts();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  testWidgets('9 Sur mon iPhone, haut', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await pumpOnDevice(tester, images: true);
    await done(tester);
    await expectLater(
      find.byType(OnDeviceScreen),
      matchesGoldenFile('goldens/phone-9.png'),
    );
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('9 Sur mon iPhone, en bas', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await pumpOnDevice(tester, images: true);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -2000));
    await done(tester);
    await expectLater(
      find.byType(OnDeviceScreen),
      matchesGoldenFile('goldens/phone-9-bas.png'),
    );
    debugDefaultTargetPlatformOverride = null;
  });
}
