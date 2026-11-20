import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/offline/device.dart';
import 'package:lafleurmusic/settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const ch = MethodChannel('studio.lafleur/device');
  late List<MethodCall> calls;
  Object? answer;

  ChannelDevice device({bool android = true, bool ios = false}) =>
      ChannelDevice(
        settings: AppSettings(),
        saveSettings: () async {},
        channel: ch,
        ios: ios,
        android: android,
      );

  setUp(() {
    calls = [];
    answer = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ch, (c) async {
          calls.add(c);
          return answer;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ch, null);
  });

  test(
    'Android: calls installApk with the path and returns its answer',
    () async {
      expect(await device().installApk('/cache/updates/a.apk'), isTrue);
      expect(calls.single.method, 'installApk');
      expect(calls.single.arguments, {'path': '/cache/updates/a.apk'});
    },
  );

  test('Android: a refusal (false) or no answer is false', () async {
    answer = false;
    expect(await device().installApk('/x.apk'), isFalse);
    answer = null;
    expect(await device().installApk('/x.apk'), isFalse);
  });

  test('iOS and others: false without calling the channel', () async {
    expect(
      await device(android: false, ios: true).installApk('/x.apk'),
      isFalse,
    );
    expect(await device(android: false).installApk('/x.apk'), isFalse);
    expect(calls, isEmpty);
  });
}
