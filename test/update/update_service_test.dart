import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lafleurmusic/settings.dart';
import 'package:lafleurmusic/update/update_service.dart';

final apkBytes = List<int>.generate(1000, (i) => i % 251);
final apkSha = sha256.convert(apkBytes).toString();

String release({String tag = 'v0.11.0', int? size, String? digest}) =>
    jsonEncode({
      'tag_name': tag,
      'html_url':
          'https://github.com/Jonlekern/lafleurmusic-mobile/releases/tag/$tag',
      'draft': false,
      'body':
          '![shot](https://x/y.png)\n\n## What\'s new in 0.11.0\n'
          '- **Update inside the app**, no more manual download\n'
          '- **Faster start**, the library opens at once\n\n'
          '## Install in 1 minute\n- Android: open the APK\n',
      'assets': [
        {
          'name': 'LAFLEURMUSIC-android.apk',
          'size': size ?? apkBytes.length,
          'digest': digest ?? 'sha256:$apkSha',
          'browser_download_url': 'https://dl/apk',
        },
        {
          'name': 'LAFLEURMUSIC-iphone-unsigned.ipa',
          'size': 5,
          'digest': 'sha256:abc',
          'browser_download_url': 'https://dl/ipa',
        },
      ],
    });

void main() {
  late Directory dir;
  late AppSettings settings;
  late int saves;
  late DateTime clock;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('upd');
    settings = AppSettings();
    saves = 0;
    clock = DateTime(2026, 11, 20, 12);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  UpdateService make(
    http.Client c, {
    String current = '0.10.2',
    Duration? timeout,
  }) => UpdateService(
    transferTimeout: timeout ?? const Duration(seconds: 30),
    client: c,
    settings: settings,
    saveSettings: () async => saves++,
    now: () => clock,
    current: current,
  );

  MockClient ok(String body, [void Function(http.Request)? spy]) =>
      MockClient((r) async {
        spy?.call(r);
        return http.Response(body, 200);
      });

  group('isNewerVersion', () {
    test('compares the three numbers', () {
      expect(isNewerVersion('0.11.0', '0.10.2'), isTrue);
      expect(isNewerVersion('0.10.10', '0.10.9'), isTrue);
      expect(isNewerVersion('0.10.2', '0.10.2'), isFalse);
      expect(isNewerVersion('0.9.9', '0.10.2'), isFalse);
      expect(isNewerVersion('1.0.0', '0.99.99'), isTrue);
      expect(isNewerVersion('v0.11.0', '0.10.2'), isTrue);
      expect(isNewerVersion('abc', '0.10.2'), isFalse);
      expect(isNewerVersion('0.11', '0.10.2'), isFalse);
    });
  });

  group('check', () {
    test('parses the release', () async {
      late http.Request seen;
      final s = make(ok(release(), (r) => seen = r));
      final u = await s.checkDaily();
      expect(u, isNotNull);
      expect(u!.version, '0.11.0');
      expect(u.notes, [
        'Update inside the app, no more manual download',
        'Faster start, the library opens at once',
      ]);
      expect(u.pageUrl, contains('/releases/tag/v0.11.0'));
      expect(u.apkUrl, 'https://dl/apk');
      expect(u.apkSize, 1000);
      expect(u.apkSha256, apkSha);
      expect(u.ipaUrl, 'https://dl/ipa');
      expect(s.available.value, same(u));
      expect(seen.headers['User-Agent'], startsWith('LAFLEURMUSIC/'));
      expect(seen.headers['Accept'], 'application/vnd.github+json');
    });

    test('no request within 24 h, one after; failure counts', () async {
      var calls = 0;
      final s = make(
        MockClient((r) async {
          calls++;
          return http.Response('{}', 403);
        }),
      );
      expect(await s.checkDaily(), isNull);
      expect(calls, 1);
      expect(settings.lastUpdateCheck, clock.millisecondsSinceEpoch);
      expect(saves, 1);
      clock = clock.add(const Duration(hours: 23));
      await s.checkDaily();
      expect(calls, 1);
      clock = clock.add(const Duration(hours: 2));
      await s.checkDaily();
      expect(calls, 2);
    });

    test(
      '403, broken JSON, wrong shape, exception: null and no throw',
      () async {
        for (final c in <http.Client>[
          MockClient((r) async => http.Response('{}', 403)),
          ok('{not json'),
          ok('[]'),
          ok('{"tag_name": 3}'),
          MockClient((r) async => throw const SocketException('off')),
        ]) {
          final s = make(c);
          expect(await s.checkDaily(), isNull);
          expect(s.available.value, isNull);
        }
      },
    );

    test('timeout gives null', () {
      fakeAsync((fa) {
        final s = make(MockClient((r) => Completer<http.Response>().future));
        UpdateInfo? got = UpdateInfo(
          version: 'x',
          notes: const [],
          pageUrl: '',
        );
        var done = false;
        s.checkDaily().then((u) {
          got = u;
          done = true;
        });
        fa.elapse(const Duration(seconds: 16));
        expect(done, isTrue);
        expect(got, isNull);
      });
    });

    test('same or older version: nothing', () async {
      expect(await make(ok(release(tag: 'v0.10.2'))).checkDaily(), isNull);
      expect(await make(ok(release(tag: 'v0.9.9'))).checkDaily(), isNull);
    });

    test('dismissed version stays hidden, newer one comes back', () async {
      settings.dismissedUpdate = '0.11.0';
      final s = make(ok(release()));
      expect(await s.checkDaily(), isNull);
      expect(s.available.value, isNull);
      clock = clock.add(const Duration(days: 2));
      final s2 = make(ok(release(tag: 'v0.11.1')));
      expect((await s2.checkDaily())?.version, '0.11.1');
    });

    test('dismiss clears and saves', () async {
      final s = make(ok(release()));
      final u = (await s.checkDaily())!;
      final before = saves;
      s.dismiss(u);
      await Future<void>.delayed(Duration.zero);
      expect(s.available.value, isNull);
      expect(settings.dismissedUpdate, '0.11.0');
      expect(saves, before + 1);
    });

    test(
      'checkNow on a dismissed version: newer, latest set, available null',
      () async {
        settings.dismissedUpdate = '0.11.0';
        final s = make(ok(release()));
        expect(s.latest, isNull);
        expect(await s.checkNow(), UpdateCheck.newer);
        expect(s.latest?.version, '0.11.0');
        expect(s.available.value, isNull);
      },
    );

    test('lastUpdateCheck in the future counts as due', () async {
      settings.lastUpdateCheck = clock
          .add(const Duration(days: 90))
          .millisecondsSinceEpoch;
      final s = make(ok(release()));
      expect((await s.checkDaily())?.version, '0.11.0');
      expect(settings.lastUpdateCheck, clock.millisecondsSinceEpoch);
    });

    group('after a relaunch', () {
      Future<void> found() async {
        await make(ok(release())).checkDaily();
        expect(settings.lastFoundUpdate, isNotNull);
        clock = clock.add(const Duration(minutes: 10));
      }

      MockClient noHttp() => MockClient((r) async => fail('no request'));

      test('same release restored without request', () async {
        await found();
        final s = make(noHttp());
        final u = await s.checkDaily();
        expect(u?.version, '0.11.0');
        expect(u?.apkSha256, apkSha);
        expect(u?.notes, hasLength(2));
        expect(s.available.value?.version, '0.11.0');
        expect(s.latest?.version, '0.11.0');
      });

      test('survives a settings file round-trip', () async {
        await found();
        final f = File('${dir.path}/s.json');
        await settings.save(f);
        settings = await AppSettings.load(f);
        expect((await make(noHttp()).checkDaily())?.version, '0.11.0');
      });

      test('dismissed: null', () async {
        await found();
        settings.dismissedUpdate = '0.11.0';
        expect(await make(noHttp()).checkDaily(), isNull);
      });

      test('app already updated: null', () async {
        await found();
        expect(await make(noHttp(), current: '0.11.0').checkDaily(), isNull);
      });

      test('broken saved JSON ignored', () async {
        await found();
        for (final bad in <Map<String, Object?>>[
          {'version': 3},
          {
            'version': '0.11.0',
            'pageUrl': 'p',
            'notes': [1],
          },
          {},
        ]) {
          settings.lastFoundUpdate = bad;
          expect(await make(noHttp()).checkDaily(), isNull);
        }
      });
    });

    test('checkNow: newer / upToDate / offline', () async {
      final s = make(ok(release()));
      expect(await s.checkNow(), UpdateCheck.newer);
      expect(s.available.value?.version, '0.11.0');
      expect(
        await make(ok(release(tag: 'v0.10.2'))).checkNow(),
        UpdateCheck.upToDate,
      );
      expect(
        await make(MockClient((r) async => http.Response('', 500))).checkNow(),
        UpdateCheck.offline,
      );
      expect(await make(ok('oops')).checkNow(), UpdateCheck.offline);
    });
  });

  group('downloadApk', () {
    UpdateInfo info({int? size, String? sha}) => UpdateInfo(
      version: '0.11.0',
      notes: const [],
      pageUrl: 'p',
      apkUrl: 'https://dl/apk',
      apkSize: size ?? apkBytes.length,
      apkSha256: sha ?? apkSha,
    );

    MockClient streaming(List<int> bytes, {int chunk = 250}) =>
        MockClient.streaming((req, _) async {
          Stream<List<int>> gen() async* {
            for (var i = 0; i < bytes.length; i += chunk) {
              yield bytes.sublist(i, (i + chunk).clamp(0, bytes.length));
            }
          }

          return http.StreamedResponse(gen(), 200, contentLength: bytes.length);
        });

    test('progress up to 1, file in updates/', () async {
      final s = make(streaming(apkBytes));
      final seen = <double>[];
      final f = await s.downloadApk(info(), dir, onProgress: seen.add);
      expect(f.parent.path, '${dir.path}/updates');
      expect(await f.readAsBytes(), apkBytes);
      expect(seen.last, 1.0);
      for (var i = 1; i < seen.length; i++) {
        expect(seen[i], greaterThanOrEqualTo(seen[i - 1]));
      }
      expect(seen.first, lessThan(1.0));
    });

    test('wrong size: throws, file deleted', () async {
      final s = make(streaming(apkBytes));
      await expectLater(
        s.downloadApk(info(size: 1200), dir),
        throwsA(isA<Exception>()),
      );
      expect(Directory('${dir.path}/updates').listSync(), isEmpty);
    });

    test('wrong sha: throws, file deleted', () async {
      final s = make(streaming(apkBytes));
      await expectLater(
        s.downloadApk(info(sha: 'deadbeef'), dir),
        throwsA(isA<Exception>()),
      );
      expect(Directory('${dir.path}/updates').listSync(), isEmpty);
    });

    test('HTTP error: throws, nothing left', () async {
      final s = make(MockClient((r) async => http.Response('no', 404)));
      await expectLater(s.downloadApk(info(), dir), throwsA(anything));
      expect(Directory('${dir.path}/updates').listSync(), isEmpty);
    });

    test('cancel stops and deletes', () async {
      final s = make(streaming(apkBytes));
      final token = CancelToken();
      await expectLater(
        s.downloadApk(
          info(),
          dir,
          cancel: token,
          onProgress: (p) {
            if (p >= 0.5) token.cancel();
          },
        ),
        throwsA(anything),
      );
      expect(Directory('${dir.path}/updates').listSync(), isEmpty);
    });

    MockClient stalled({List<int> first = const []}) =>
        MockClient.streaming((req, _) async {
          Stream<List<int>> gen() async* {
            if (first.isNotEmpty) yield first;
            await Completer<void>().future; // ne rend plus rien
          }

          return http.StreamedResponse(gen(), 200);
        });

    test('stalled body times out, file deleted', () async {
      final s = make(
        stalled(first: apkBytes.sublist(0, 100)),
        timeout: const Duration(milliseconds: 100),
      );
      await expectLater(
        s.downloadApk(info(), dir),
        throwsA(isA<TimeoutException>()),
      );
      expect(Directory('${dir.path}/updates').listSync(), isEmpty);
    });

    test('send that never answers times out', () async {
      final s = make(
        MockClient.streaming(
          (r, _) => Completer<http.StreamedResponse>().future,
        ),
        timeout: const Duration(milliseconds: 100),
      );
      await expectLater(
        s.downloadApk(info(), dir),
        throwsA(isA<TimeoutException>()),
      );
      expect(Directory('${dir.path}/updates').listSync(), isEmpty);
    });

    test('cancel during a stall stops at once, file deleted', () async {
      final s = make(stalled(first: [1, 2, 3]));
      final token = CancelToken();
      final sw = Stopwatch()..start();
      final f = s.downloadApk(info(), dir, cancel: token);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      token.cancel();
      await expectLater(f, throwsA(anything));
      expect(sw.elapsed, lessThan(const Duration(seconds: 5)));
      expect(Directory('${dir.path}/updates').listSync(), isEmpty);
    });

    test('two downloads do not clobber each other', () async {
      final s = make(streaming(apkBytes));
      final r = await Future.wait([
        s.downloadApk(info(), dir),
        s.downloadApk(info(), dir),
      ]);
      for (final f in r) {
        expect(await f.readAsBytes(), apkBytes);
      }
      expect(Directory('${dir.path}/updates').listSync().length, 1);
    });

    test('clearDownloads empties updates/', () async {
      final d = Directory('${dir.path}/updates')..createSync();
      File('${d.path}/a.apk').writeAsBytesSync([1]);
      await UpdateService.clearDownloads(dir);
      expect(d.listSync(), isEmpty);
      await UpdateService.clearDownloads(Directory('${dir.path}/none'));
    });
  });

  test('settings round-trip', () async {
    final f = File('${dir.path}/s.json');
    final s = AppSettings()
      ..lastUpdateCheck = 123
      ..dismissedUpdate = '0.11.0';
    await s.save(f);
    final back = await AppSettings.load(f);
    expect(back.lastUpdateCheck, 123);
    expect(back.dismissedUpdate, '0.11.0');
    expect(AppSettings().lastUpdateCheck, isNull);
  });
}
