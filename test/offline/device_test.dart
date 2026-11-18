import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/offline/device.dart';
import 'package:lafleurmusic/settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const ch = MethodChannel('studio.lafleur/device');
  late Directory tmp;
  late AppSettings settings;
  late int saves;
  late List<MethodCall> calls;
  late Future<Object?> Function(MethodCall) native;

  ChannelDevice device({bool ios = false}) => ChannelDevice(
    settings: settings,
    saveSettings: () async => saves++,
    channel: ch,
    ios: ios,
  );

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('dev');
    settings = AppSettings();
    saves = 0;
    calls = [];
    native = (c) async => c.method == 'defaultRoot' ? '${tmp.path}/def' : null;
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

  test('no chosen folder: default root, reachable', () async {
    final d = device();
    expect((await d.musicRoot()).path, '${tmp.path}/def');
    expect(await d.rootReachable(), true);
  });

  test('Android: chosen folder used when it exists', () async {
    final x = Directory('${tmp.path}/X')..createSync();
    settings.musicFolder = x.path;
    final d = device();
    expect((await d.musicRoot()).path, x.path);
    expect(await d.rootReachable(), true);
  });

  test('Android: vanished folder falls back to default, unreachable', () async {
    settings.musicFolder = '${tmp.path}/gone';
    final d = device();
    expect((await d.musicRoot()).path, '${tmp.path}/def');
    expect(await d.rootReachable(), false);
  });

  test('pickFolder stores the path (Android)', () async {
    native = (c) async => {'path': '/storage/1234-ABCD/Music'};
    final d = device();
    final c = (await d.pickFolder())!;
    expect(c.path, '/storage/1234-ABCD/Music');
    expect(settings.musicFolder, isNull, reason: 'picking does not switch');
    expect(saves, 0);
    await d.commitFolder(c);
    expect(settings.musicFolder, '/storage/1234-ABCD/Music');
    expect(saves, 1);
    expect((await d.musicRoot()).path, '/storage/1234-ABCD/Music');
  });

  test('pickFolder stores the bookmark (iOS)', () async {
    native = (c) async => {'path': '/private/iCloud/Music', 'bookmark': 'Ym0='};
    final d = device(ios: true);
    final c = (await d.pickFolder())!;
    expect(c.path, '/private/iCloud/Music');
    expect(settings.musicFolder, isNull);
    await d.commitFolder(c);
    expect(settings.musicFolder, 'Ym0=');
  });

  test(
    'iOS: commitFolder and releaseCandidate reach the native side',
    () async {
      native = (c) async => {'path': '/p', 'bookmark': 'Ym0='};
      final d = device(ios: true);
      final c = (await d.pickFolder())!;
      calls.clear();
      await d.releaseCandidate();
      await d.commitFolder(c);
      expect(calls.map((c) => c.method), ['releaseCandidate', 'commitFolder']);
      calls.clear();
      final a = device();
      await a.releaseCandidate();
      await a.commitFolder(const PickedFolder('/x'));
      expect(calls, isEmpty, reason: 'Android has nothing to keep open');
    },
  );

  test('pickFolder cancelled: null, nothing stored', () async {
    final d = device();
    expect(await d.pickFolder(), isNull);
    expect(settings.musicFolder, isNull);
    expect(saves, 0);
  });

  test('pickFolder refused when not local', () async {
    native = (c) async => throw PlatformException(code: 'not_local');
    await expectLater(
      device().pickFolder(),
      throwsA(isA<FolderNotLocalException>()),
    );
    expect(settings.musicFolder, isNull);
  });

  test('iOS: bookmark resolved at launch, stale one renewed', () async {
    settings.musicFolder = 'old';
    native = (c) async => c.method == 'openBookmark'
        ? {'path': '/private/iCloud/Music', 'bookmark': 'new'}
        : null;
    final d = device(ios: true);
    expect((await d.musicRoot()).path, '/private/iCloud/Music');
    expect(settings.musicFolder, 'new');
    expect(saves, 1);
  });

  test('iOS: unresolvable bookmark falls back to default', () async {
    settings.musicFolder = 'old';
    native = (c) async => c.method == 'openBookmark'
        ? throw PlatformException(code: 'bookmark')
        : '${tmp.path}/def';
    final d = device(ios: true);
    expect((await d.musicRoot()).path, '${tmp.path}/def');
    expect(await d.rootReachable(), false);
  });

  test(
    'freeBytes and announce go to the channel; iOS announce is a no-op',
    () async {
      native = (c) async => c.method == 'freeBytes' ? 42 : null;
      expect(await device().freeBytes('/x'), 42);
      await device().announce('/x/a.mp3');
      expect(calls.last.method, 'announce');
      calls.clear();
      await device(ios: true).announce('/x/a.mp3');
      expect(calls, isEmpty);
    },
  );

  test('pickFolder not writable maps to its exception', () async {
    native = (c) async => throw PlatformException(code: 'not_writable');
    await expectLater(
      device().pickFolder(),
      throwsA(isA<FolderNotWritableException>()),
    );
    expect(settings.musicFolder, isNull);
  });

  test('concurrent musicRoot calls both get the chosen folder (iOS)', () async {
    settings.musicFolder = 'old';
    native = (c) async {
      if (c.method != 'openBookmark') return '${tmp.path}/def';
      await Future<void>.delayed(const Duration(milliseconds: 20));
      return {'path': '/private/iCloud/Music'};
    };
    final d = device(ios: true);
    final r = await Future.wait([
      d.musicRoot(),
      d.musicRoot(),
      d.rootReachable(),
    ]);
    expect((r[0] as Directory).path, '/private/iCloud/Music');
    expect((r[1] as Directory).path, '/private/iCloud/Music');
    expect(r[2], true);
    expect(calls.where((c) => c.method == 'openBookmark').length, 1);
  });

  test('missing plugin falls back to default, unreachable', () async {
    settings.musicFolder = 'old';
    native = (c) async => c.method == 'openBookmark'
        ? throw MissingPluginException()
        : '${tmp.path}/def';
    final d = device(ios: true);
    expect((await d.musicRoot()).path, '${tmp.path}/def');
    expect(await d.rootReachable(), false);
  });

  test('ensureAccess maps the channel answer; iOS is always true', () async {
    native = (c) async => c.method == 'ensureAccess' ? false : null;
    expect(await device().ensureAccess(readOthers: true), false);
    expect(calls.last.arguments, {'readOthers': true});
    native = (c) async => true;
    expect(await device().ensureAccess(), true);
    calls.clear();
    expect(await device(ios: true).ensureAccess(readOthers: true), true);
    expect(calls, isEmpty);
  });
}
