// Runs before every test file under test/ (flutter_test convention).
//
// Goldens: the reference images are made on the dev Mac, but CI runs on a
// GitHub macos-15 runner whose text and image rasterisation differs very
// slightly (0.08 % to 0.64 % of pixels on the first CI run). A diff up to
// [goldenTolerance] is accepted; anything above still fails and writes the
// usual failure images under failures/.
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
