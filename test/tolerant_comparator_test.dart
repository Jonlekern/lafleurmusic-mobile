// The golden comparator of flutter_test_config.dart: on CI (CI=true) up to 1 % of pixels may differ;
// locally nothing may.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'tolerant_comparator.dart';

/// 100×100 white PNG with its first [changed] pixels black.
Uint8List png(int changed) {
  final im = img.Image(width: 100, height: 100);
  img.fill(im, color: img.ColorRgb8(255, 255, 255));
  for (var i = 0; i < changed; i++) {
    im.setPixelRgb(i % 100, i ~/ 100, 0, 0, 0);
  }
  return img.encodePng(im);
}

void main() {
  late Directory dir;
  late TolerantFileComparator comparator;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('golden-tolerance');
    File('${dir.path}/g.png').writeAsBytesSync(png(0));
    comparator = TolerantFileComparator(
      Uri.file('${dir.path}/x_test.dart'),
      tolerance: goldenToleranceFor({'CI': 'true'}),
    );
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<Object?> failure(WidgetTester tester, int changed) async {
    Object? error;
    await tester.runAsync(() async {
      try {
        await comparator.compare(png(changed), Uri.parse('g.png'));
      } catch (e) {
        error = e;
      }
    });
    return error;
  }

  test('tolerance: 1 % on CI, 0 % locally', () {
    expect(goldenToleranceFor({'CI': 'true'}), 0.01);
    expect(goldenToleranceFor({}), 0);
    expect(goldenToleranceFor({'CI': 'false'}), 0);
  });

  testWidgets('locally: a single differing pixel fails', (tester) async {
    comparator = TolerantFileComparator(
      Uri.file('${dir.path}/x_test.dart'),
      tolerance: goldenToleranceFor({}),
    );
    expect(await failure(tester, 1), isA<FlutterError>());
    final same = await tester.runAsync(
      () => comparator.compare(png(0), Uri.parse('g.png')),
    );
    expect(same, isTrue);
  });

  testWidgets('CI: 0.9 % of pixels differ: accepted (phone-6 drifted 0.83 %)', (
    tester,
  ) async {
    final ok = await tester.runAsync(
      () => comparator.compare(png(90), Uri.parse('g.png')),
    );
    expect(ok, isTrue);
  });

  testWidgets('CI: 0.5 % of pixels differ: accepted', (tester) async {
    final ok = await tester.runAsync(
      () => comparator.compare(png(50), Uri.parse('g.png')),
    );
    expect(ok, isTrue);
  });

  testWidgets('CI: 1.1 % of pixels differ: fails (just above 1 %)', (
    tester,
  ) async {
    expect(await failure(tester, 110), isA<FlutterError>());
  });

  testWidgets('CI: 2 % of pixels differ: fails with failure images', (
    tester,
  ) async {
    expect(await failure(tester, 200), isA<FlutterError>());
    expect(Directory('${dir.path}/failures').existsSync(), isTrue);
  });
}
