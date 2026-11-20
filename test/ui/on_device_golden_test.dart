// Pixel comparison: run on macOS only (CI job goldens), see dart_test.yaml.
@Tags(['golden'])
library;

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show OffsetLayer;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/ui/phone/on_device_screen.dart';

import 'fonts.dart';
import 'phone/keep_screen_test.dart' show done;
import 'phone/on_device_screen_test.dart' show pumpOnDevice;

/// « Sur mon iPhone », 390 × 844 sur un iPhone : haut et bas de la maquette 4, mêmes données que le
/// mode démo (`LAFLEUR_DEMO_SCREEN=ondevice`).
///
/// Image en 2 pixels par point, comme un vrai iPhone (la mise en page reste 390 × 844) : l'écran est
/// surtout du petit texte, et le Mac de GitHub en lisse les bords un peu autrement (1,13 % des
/// pixels à 1 pixel par point, au-delà du 1 % toléré, sans aucun écart de contenu). Le double de
/// pixels divise environ par deux la part de ces bords ; un libellé ou une icône qui change fait
/// toujours échouer.
/// L'écran rendu en 2 pixels par point (même découpe que `matchesGoldenFile(finder)`).
Future<ui.Image> at2x(WidgetTester tester) {
  var box = tester.renderObject(find.byType(OnDeviceScreen));
  while (!box.isRepaintBoundary) {
    box = box.parent!;
  }
  final layer = box.debugLayer! as OffsetLayer;
  return layer.toImage(box.paintBounds, pixelRatio: 2);
}

void main() {
  setUpAll(() async {
    await loadFonts();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  for (final (mode, sfx) in goldenModes) {
    testWidgets(inMode(mode, '9 Sur mon iPhone, haut'), (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await pumpOnDevice(tester, brightness: mode,  images: true);
      await done(tester);
      await expectLater(
        at2x(tester),
        matchesGoldenFile('goldens/phone-9$sfx.png'),
      );
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets(inMode(mode, '9 Sur mon iPhone, en bas'), (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await pumpOnDevice(tester, brightness: mode,  images: true);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -2000));
      await done(tester);
      await expectLater(
        at2x(tester),
        matchesGoldenFile('goldens/phone-9-bas$sfx.png'),
      );
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
