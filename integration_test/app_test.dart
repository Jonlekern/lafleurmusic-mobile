// End-to-end run (plan 1, task 10): the real app, first launch with no account, against a fake
// Subsonic server in the test process (fake_subsonic.dart).
//
//   flutter test integration_test/app_test.dart -d <phone>
//
// Screen 7 (add an account) → address, user, password, header `X-Lafleur-Test: ok` → Test → it works
// → Save → the album shows on Home after the sync → open it, tap the first song → it plays past 1 s.
//
// Clean start every time: a library folder of its own (deleted first) and a keychain / Keystore
// namespace of its own (emptied first and last), so the app's real accounts are never read or touched.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lafleurmusic/main.dart';
import 'package:lafleurmusic/sources/secret_store.dart';
import 'package:lafleurmusic/sources/source.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart' show MpvAudioKit;
import 'package:path_provider/path_provider.dart';

import 'fake_subsonic.dart';

/// Test-only secure storage: another keychain service on iOS, another preferences file on Android.
const _testStorage = FlutterSecureStorage(
  iOptions: IOSOptions(accountName: 'lafleurmusic.e2e-test'),
  aOptions: AndroidOptions(sharedPreferencesName: 'lafleurmusic_e2e_test'),
);

/// Pumps frames until [finder] finds something, for at most [timeout].
Future<void> pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final end = DateTime.now().add(timeout);
  while (finder.evaluate().isEmpty) {
    if (DateTime.now().isAfter(end)) {
      throw TestFailure('Not found within $timeout: $finder');
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Scrolls the screen's list until [finder] is built and on screen: lists build lazily, a small
/// phone (the 320×640 Android emulator) shows only the top of the form, and the real keyboard
/// takes half the screen. Down first, then up (the keyboard may have pushed it above).
Future<void> reveal(WidgetTester tester, Finder finder) async {
  final list = find
      .descendant(
        of: find.byType(ListView),
        matching: find.byType(Scrollable),
      )
      .first;
  for (var attempt = 0; attempt < 4; attempt++) {
    await tester.pump();
    for (final delta in const [150.0, -150.0]) {
      if (finder.evaluate().isNotEmpty) break;
      try {
        await tester.scrollUntilVisible(
          finder,
          delta,
          scrollable: list,
          maxScrolls: 60,
        );
      } on StateError {
        // not in this direction
      }
    }
    if (finder.evaluate().isNotEmpty) {
      await tester.ensureVisible(finder);
      await tester.pump(const Duration(milliseconds: 300));
      if (finder.hitTestable().evaluate().isNotEmpty) return;
    }
  }
  throw TestFailure('Could not bring on screen: $finder');
}

/// Taps a button: the keyboard goes away first, so the whole screen is free on a small phone.
Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump(const Duration(milliseconds: 500));
  await reveal(tester, finder);
  await tester.tap(finder.hitTestable().first);
  await tester.pump();
}

Future<void> typeInto(WidgetTester tester, String key, String text) async {
  final field = find.byKey(ValueKey(key));
  await reveal(tester, field);
  await tester.enterText(field, text);
  await tester.pump(const Duration(milliseconds: 300)); // keyboard up: the list may move
  await reveal(tester, field);
  await tester.pump();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MpvAudioKit.ensureInitialized();

  late FakeSubsonic server;
  late Directory support;

  setUpAll(() async {
    server = await FakeSubsonic.start();
    support = Directory(
      '${(await getTemporaryDirectory()).path}/lafleurmusic-e2e',
    );
    if (support.existsSync()) support.deleteSync(recursive: true);
    support.createSync(recursive: true);
    await _testStorage.deleteAll();
  });

  tearDownAll(() async {
    await _testStorage.deleteAll();
    await server.close();
  });

  testWidgets('first launch → account → Home → album → plays', (tester) async {
    final app = await buildLafleurApp(
      support: support,
      secrets: SecureSecretStore(_testStorage),
    );
    final s = app.strings;
    await tester.pumpWidget(app);

    // screen 7: no account yet
    await pumpUntil(tester, find.byKey(const ValueKey('account-address')));
    expect(find.text(s.firstAccount), findsOneWidget);

    await typeInto(tester, 'account-name', 'Fake Navidrome');
    await typeInto(tester, 'account-address', server.address);
    await typeInto(tester, 'account-user', server.user);
    await typeInto(tester, 'account-password', server.password);
    await tapVisible(tester, find.text(s.addHeader));
    await typeInto(tester, 'header-0-name', fakeHeader);
    await typeInto(tester, 'header-0-value', fakeHeaderValue);
    FocusManager.instance.primaryFocus?.unfocus(); // the keyboard goes away
    await tester.pump(const Duration(milliseconds: 500));

    // Test → « Ça marche ! »
    await tapVisible(tester, find.text(s.testAction));
    await pumpUntil(tester, find.text(s.testResult(TestResult.ok)));
    expect(server.requests.map((r) => r.method), contains('ping'));

    // Save → Home, the album appears once synced
    await tapVisible(tester, find.text(s.save));
    final album = find.text('Studio Lafleur');
    await pumpUntil(tester, album);
    expect(find.byKey(const ValueKey('account-address')), findsNothing);

    // open the album, tap the first song
    await tapVisible(tester, album.first);
    final song = find.text('Night Drive');
    await pumpUntil(tester, song);
    await tapVisible(tester, song.first);

    // it plays: past 1 s within 10 s, read through the app's player
    final player = app.player;
    final end = DateTime.now().add(const Duration(seconds: 10));
    while (!(player.current.track?.title == 'Night Drive' &&
        player.current.position > const Duration(seconds: 1))) {
      if (DateTime.now().isAfter(end)) {
        fail(
          'Not past 1 s within 10 s: ${player.current.track?.title} '
          'at ${player.current.position}; server saw ${server.requests}',
        );
      }
      await tester.pump(const Duration(milliseconds: 100));
    }
    debugPrint(
      'PREUVE bout en bout : ${player.current.track?.title} à '
      '${player.current.position} ; serveur : ${server.requests}',
    );
    expect(player.current.playing, isTrue);

    final streams = server.requests.where((r) => r.method == 'stream');
    expect(streams, isNotEmpty);
    expect(streams.first.params['id'], 's-1');
    // every request carried the header and a good token
    expect(server.requests.where((r) => r.status != 200), isEmpty);

    await player.toggle(); // pause
    await tester.pump(const Duration(milliseconds: 200));
  });
}
