import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Share of differing pixels accepted against a golden on CI (1 %): the GitHub macOS runner
/// rasterises text and images very slightly differently from the dev Mac (up to 0.83 % seen,
/// phone-6). On a 390×844 phone golden 1 % is about 3 300 pixels: a swapped icon or label still fails.
const ciGoldenTolerance = 0.01;

/// Local runs stay strict (0 %): the reference images are made on this Mac.
/// [env] is for tests; GitHub Actions sets `CI=true`.
double goldenToleranceFor([Map<String, String>? env]) =>
    (env ?? Platform.environment)['CI'] == 'true' ? ciGoldenTolerance : 0;

/// [LocalFileComparator] that accepts a diff up to [tolerance] (see flutter_test_config.dart).
class TolerantFileComparator extends LocalFileComparator {
  TolerantFileComparator(super.testFile, {double? tolerance})
    : tolerance = tolerance ?? goldenToleranceFor();
  final double tolerance;

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );
    if (result.passed || result.diffPercent <= tolerance) {
      if (!result.passed) {
        // accepted, but shown, so a slow drift stays visible in the logs
        debugPrint(
          'Golden $golden: ${(result.diffPercent * 100).toStringAsFixed(2)} % '
          'of pixels differ (accepted up to ${tolerance * 100} %)',
        );
      }
      result.dispose();
      return true;
    }
    final error = await generateFailureOutput(result, golden, basedir);
    result.dispose();
    throw FlutterError(error);
  }
}
