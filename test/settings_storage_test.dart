import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/settings.dart';

void main() {
  late Directory dir;
  late File f;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('settings');
    f = File('${dir.path}/settings.json');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  const gib10 = 10 * 1024 * 1024 * 1024;

  test('storageLimitBytes defaults to 10 GiB', () async {
    expect((await AppSettings.load(f)).storageLimitBytes, gib10);
  });

  test('storageLimitBytes round-trips', () async {
    final s = AppSettings()..storageLimitBytes = 3 * 1024 * 1024 * 1024;
    await s.save(f);
    expect(
      (await AppSettings.load(f)).storageLimitBytes,
      3 * 1024 * 1024 * 1024,
    );
  });

  test('bad storageLimitBytes falls back to the default', () async {
    for (final bad in ['"big"', '0', '-5', '1.5', 'null']) {
      f.writeAsStringSync('{"storageLimitBytes": $bad}');
      expect((await AppSettings.load(f)).storageLimitBytes, gib10, reason: bad);
    }
  });

  test('musicFolder defaults to null and round-trips', () async {
    expect((await AppSettings.load(f)).musicFolder, isNull);
    await (AppSettings()..musicFolder = '/storage/emulated/0/Music/X').save(f);
    expect(
      (await AppSettings.load(f)).musicFolder,
      '/storage/emulated/0/Music/X',
    );
  });

  test('bad musicFolder falls back to null', () async {
    for (final bad in ['3', '""', '[]']) {
      f.writeAsStringSync('{"musicFolder": $bad}');
      expect((await AppSettings.load(f)).musicFolder, isNull, reason: bad);
    }
  });
}
