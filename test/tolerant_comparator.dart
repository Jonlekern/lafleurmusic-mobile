import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Share of differing pixels accepted against a golden (1 %).
const goldenTolerance = 0.01;

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
      result.dispose();
      return true;
    }
    final error = await generateFailureOutput(result, golden, basedir);
    result.dispose();
    throw FlutterError(error);
  }
}
