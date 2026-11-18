import 'dart:io';

import 'package:flutter/services.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/library/db.dart';
import 'package:lafleurmusic/library/models.dart';
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

  Future<void> Function()? save;

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
    tmp = Directory.systemTemp.createTempSync('dev');
    settings = AppSettings();
    saves = 0;
    save = null;
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

  test('commitFolder: a failed save changes nothing, native side untouched', () async {
    final x = Directory('${tmp.path}/X')..createSync();
    settings.musicFolder = x.path;
    final d = device(ios: true);
    native = (c) async => switch (c.method) {
      'openBookmark' => {'path': x.path},
      _ => null,
    };
    expect((await d.musicRoot()).path, x.path);
    save = () async => throw const FileSystemException('disk full');
    calls.clear();
    await expectLater(
      d.commitFolder(const PickedFolder('/new', 'Ym0=')),
      throwsA(isA<FileSystemException>()),
    );
    expect(settings.musicFolder, x.path);
    expect(calls.map((c) => c.method), isNot(contains('commitFolder')));
    expect((await d.musicRoot()).path, x.path);
  });

  test('commitFolder: a native failure puts the old choice back, saved', () async {
    settings.musicFolder = 'old';
    native = (c) async => switch (c.method) {
      'openBookmark' => {'path': '${tmp.path}/old'},
      'commitFolder' => throw PlatformException(code: 'no_candidate'),
      _ => '${tmp.path}/def',
    };
    final d = device(ios: true);
    await expectLater(
      d.commitFolder(const PickedFolder('/new', 'Ym0=')),
      throwsA(isA<PlatformException>()),
    );
    expect(settings.musicFolder, 'old');
    expect(saves, 2, reason: 'new value saved, then the old one again');
    expect((await d.musicRoot()).path, '${tmp.path}/old');
  });

  test('ensureAccess: one native request at a time, busy waits', () async {
    var inFlight = 0, most = 0, busyOnce = true;
    native = (c) async {
      if (c.method != 'ensureAccess') return null;
      if (busyOnce) {
        busyOnce = false;
        throw PlatformException(code: 'busy');
      }
      inFlight++;
      most = inFlight > most ? inFlight : most;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      inFlight--;
      return true;
    };
    final d = device();
    final r = await Future.wait([
      d.ensureAccess(readOthers: true),
      d.ensureAccess(),
    ]);
    expect(r, [true, true]);
    expect(most, 1);
  });

  group('docs:// keys', () {
    test('iPhone: a file in Documents gets docs://rel, others stay absolute', () async {
      native = (c) async => c.method == 'defaultRoot' ? '${tmp.path}/Documents/LAFLEURMUSIC' : null;
      final d = device(ios: true);
      expect(await d.keyFor('${tmp.path}/Documents/LAFLEURMUSIC/Art/a.mp3'), 'docs://LAFLEURMUSIC/Art/a.mp3');
      expect(await d.keyFor('${tmp.path}/Elsewhere/a.mp3'), '${tmp.path}/Elsewhere/a.mp3');
      expect(await d.keyFor('${tmp.path}/Documentsx/a.mp3'), '${tmp.path}/Documentsx/a.mp3');
      expect(await d.absolutePath('docs://LAFLEURMUSIC/Art/a.mp3'), '${tmp.path}/Documents/LAFLEURMUSIC/Art/a.mp3');
      expect(await d.absolutePath('/x/y.mp3'), '/x/y.mp3');
    });

    test('Android: nothing is rewritten', () async {
      native = (c) async => c.method == 'defaultRoot' ? '${tmp.path}/Music/LAFLEURMUSIC' : null;
      final d = device();
      expect(await d.keyFor('${tmp.path}/Music/LAFLEURMUSIC/a.mp3'), '${tmp.path}/Music/LAFLEURMUSIC/a.mp3');
    });

    test('an orphan on iPhone keeps a key that still resolves after the app container moves', () async {
      final db = LibraryDb(NativeDatabase.memory());
      addTearDown(db.close);
      final before = '${tmp.path}/container1/Documents/LAFLEURMUSIC';
      native = (c) async => c.method == 'defaultRoot' ? before : null;
      File('$before/Art/a.mp3')
        ..createSync(recursive: true)
        ..writeAsBytesSync([1]);
      const k = 'subsonic://acc/s1';
      await db.upsertTrack(const Track(
        path: k, accountId: 'acc', remoteId: 's1', title: 'T', artist: 'A', album: 'B', durationMs: 1, hasCover: false, size: 1,
      ));
      await db.queueOffline([k], OfflineReason.user);
      await db.markOfflineDone(k, 'Art/a.mp3', 1);
      final d1 = device(ios: true);
      await db.dropServerTracks([k], root: CopyRoot(before, d1.keyFor));
      final key = (await db.select(db.tracks).get()).single.path;
      expect(key, 'docs://LAFLEURMUSIC/Art/a.mp3');
      // update / restore: same files, another container path
      Directory('${tmp.path}/container1').renameSync('${tmp.path}/container2');
      native = (c) async => c.method == 'defaultRoot' ? '${tmp.path}/container2/Documents/LAFLEURMUSIC' : null;
      final now = await device(ios: true).absolutePath(key);
      expect(now, '${tmp.path}/container2/Documents/LAFLEURMUSIC/Art/a.mp3');
      expect(File(now).existsSync(), isTrue);
    });
  });
}
