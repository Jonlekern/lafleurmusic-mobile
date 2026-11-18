import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Share of differing pixels accepted against a golden (0.8 %): the worst CI drift seen was 0.64 %,
/// and on a 390×844 phone golden 0.8 % is about 2 600 pixels, kept tight so a swapped icon or label fails.
const goldenTolerance = 0.008;

/// [LocalFileComparator] that accepts a diff up to [tolerance] (see flutter_test_config.dart).
class TolerantFileComparator extends LocalFileComparator {
  TolerantFileComparator(super.testFile, {this.tolerance = goldenTolerance});
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
