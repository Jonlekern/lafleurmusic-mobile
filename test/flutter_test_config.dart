// Runs before every test file under test/ (flutter_test convention).
//
// Goldens: the reference images are made on the dev Mac and compared strictly
// there. CI (CI=true) runs on a GitHub macos-15 runner whose text and image
// rasterisation differs very slightly (up to 0.83 % of pixels seen): there a
// diff up to [ciGoldenTolerance] is accepted and printed; anything above still
// fails and writes the usual failure images under failures/.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'tolerant_comparator.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final current = goldenFileComparator;
  if (current is LocalFileComparator) {
    goldenFileComparator = TolerantFileComparator(
      current.basedir.resolve('flutter_test_config.dart'),
    );
  }
  await testMain();
}
