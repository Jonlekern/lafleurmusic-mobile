import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/offline/device.dart';
import 'package:lafleurmusic/settings.dart';

/// Two roots: kept songs (visible folder, or the app's private folder) and hand-placed files
/// (always the visible folder).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const ch = MethodChannel('studio.lafleur/device');
  late Directory tmp;
  late AppSettings settings;
  late int saves;
  late List<MethodCall> calls;
  late Future<Object?> Function(MethodCall) native;
  Future<void> Function()? save;

  String def() => '${tmp.path}/Documents/LAFLEURMUSIC';
  String priv() => '${tmp.path}/Library/Application Support/LAFLEURMUSIC';

  ChannelDevice device({bool ios = false}) => ChannelDevice(
    settings: settings,
    saveSettings: () async {
      saves++;
      await save?.call();
    },
    channel: ch,
    ios: ios,
  );

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('roots');
    settings = AppSettings();
    saves = 0;
    save = null;
    calls = [];
    native = (c) async => switch (c.method) {
      'defaultRoot' => def(),
      'privateRoot' => priv(),
      _ => null,
    };
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ch, (c) {
          calls.add(c);
          return native(c);
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ch, null);
    tmp.deleteSync(recursive: true);
  });

  test('keepInApp is off by default, saved and read back', () async {
    expect(AppSettings().keepInApp, isFalse);
    final f = File('${tmp.path}/settings.json');
    final s = AppSettings()..keepInApp = true;
    await s.save(f);
    expect((await AppSettings.load(f)).keepInApp, isTrue);
    await (AppSettings()..keepInApp = false).save(f);
    expect((await AppSettings.load(f)).keepInApp, isFalse);
  });

  for (final ios in [false, true]) {
    final os = ios ? 'iPhone' : 'Android';

    test('$os: by default the kept root is the visible root', () async {
      final d = device(ios: ios);
      expect((await d.keptRoot()).path, def());
      expect((await d.visibleRoot()).path, def());
      expect(await d.rootReachable(), isTrue);
      expect(await d.visibleReachable(), isTrue);
    });

    test('$os: a chosen folder is both roots by default', () async {
      final x = Directory('${tmp.path}/X')..createSync();
      settings.musicFolder = ios ? 'bm' : x.path;
      native = (c) async => switch (c.method) {
        'openBookmark' => {'path': x.path},
        'defaultRoot' => def(),
        'privateRoot' => priv(),
        _ => null,
      };
      final d = device(ios: ios);
      expect((await d.keptRoot()).path, x.path);
      expect((await d.visibleRoot()).path, x.path);
    });

    test('$os: keepInApp moves the kept root to the private folder only', () async {
      final x = Directory('${tmp.path}/X')..createSync();
      settings.musicFolder = ios ? 'bm' : x.path;
      native = (c) async => switch (c.method) {
        'openBookmark' => {'path': x.path},
        'defaultRoot' => def(),
        'privateRoot' => priv(),
        _ => null,
      };
      final d = device(ios: ios);
      await d.setKeepInApp(true);
      expect(settings.keepInApp, isTrue);
      expect(saves, 1);
      expect((await d.keptRoot()).path, priv());
      expect((await d.privateRoot()).path, priv());
      expect((await d.visibleRoot()).path, x.path, reason: 'the chosen folder stays');
      expect(settings.musicFolder, ios ? 'bm' : x.path);
      await d.setKeepInApp(false);
      expect((await d.keptRoot()).path, x.path);
      expect(saves, 2);
    });

    test('$os: in the app, a vanished visible folder never stops keeping', () async {
      settings.musicFolder = ios ? 'bm' : '${tmp.path}/gone';
      settings.keepInApp = true;
      native = (c) async => switch (c.method) {
        'openBookmark' => throw PlatformException(code: 'bookmark'),
        'defaultRoot' => def(),
        'privateRoot' => priv(),
        _ => null,
      };
      final d = device(ios: ios);
      expect(await d.rootReachable(), isTrue);
      expect(await d.visibleReachable(), isFalse);
      expect((await d.visibleRoot()).path, def());
      expect((await d.keptRoot()).path, priv());
    });

    test('$os: app:// keys round-trip and survive a container move', () async {
      final d = device(ios: ios);
      expect(await d.keyFor('${priv()}/Art/Alb/01 a.mp3'), 'app://Art/Alb/01 a.mp3');
      expect(await d.absolutePath('app://Art/Alb/01 a.mp3'), '${priv()}/Art/Alb/01 a.mp3');
      // a sibling with the same prefix is not inside
      expect(await d.keyFor('${priv()}x/a.mp3'), '${priv()}x/a.mp3');
      native = (c) async => switch (c.method) {
        'privateRoot' => '${tmp.path}/other/LAFLEURMUSIC',
        'defaultRoot' => def(),
        _ => null,
      };
      expect(
        await device(ios: ios).absolutePath('app://Art/Alb/01 a.mp3'),
        '${tmp.path}/other/LAFLEURMUSIC/Art/Alb/01 a.mp3',
      );
    });

    test('$os: setKeepInApp that cannot be saved changes nothing', () async {
      final d = device(ios: ios);
      save = () async => throw const FileSystemException('disk full');
      await expectLater(d.setKeepInApp(true), throwsA(isA<FileSystemException>()));
      expect(settings.keepInApp, isFalse);
      expect((await d.keptRoot()).path, def());
    });
  }

  test('iPhone: docs:// keys are unchanged next to app:// ones', () async {
    final d = device(ios: true);
    expect(await d.keyFor('${def()}/Art/a.mp3'), 'docs://LAFLEURMUSIC/Art/a.mp3');
    expect(await d.absolutePath('docs://LAFLEURMUSIC/Art/a.mp3'), '${def()}/Art/a.mp3');
  });

  test('Android: files outside the private folder keep their absolute path', () async {
    final d = device();
    expect(await d.keyFor('${def()}/Art/a.mp3'), '${def()}/Art/a.mp3');
  });

  test('a phone without a private folder answer keeps keys absolute', () async {
    native = (c) async => c.method == 'defaultRoot' ? def() : null;
    final d = device();
    expect(await d.keyFor('${priv()}/a.mp3'), '${priv()}/a.mp3');
    expect(await d.absolutePath('/x/a.mp3'), '/x/a.mp3');
  });

  test('Android: a file in the private folder is never announced', () async {
    final d = device();
    await d.announce('${priv()}/Art/a.mp3');
    expect(calls.where((c) => c.method == 'announce'), isEmpty);
    await d.announce('${def()}/Art/a.mp3');
    expect(calls.where((c) => c.method == 'announce').single.arguments, {
      'path': '${def()}/Art/a.mp3',
    });
  });

  test('the private folder is asked excluded from backup on every resolve', () async {
    final d = device(ios: true);
    await d.privateRoot();
    settings.keepInApp = true;
    await d.keptRoot();
    final asks = calls.where((c) => c.method == 'privateRoot').toList();
    expect(asks, hasLength(2));
    for (final c in asks) {
      expect(c.arguments, {'excludeFromBackup': true});
    }
  });
}
