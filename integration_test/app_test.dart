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
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lafleurmusic/main.dart';
import 'package:lafleurmusic/sources/secret_store.dart';
import 'package:lafleurmusic/sources/source.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart' show MpvAudioKit;
import 'package:path_provider/path_provider.dart';

import 'fake_subsonic.dart';
import 'ui_helpers.dart';

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
    await testStorage.deleteAll();
  });

  tearDownAll(() async {
    await testStorage.deleteAll();
    await server.close();
  });

  testWidgets('first launch → account → Home → album → plays', (tester) async {
    final app = await buildLafleurApp(
      support: support,
      secrets: SecureSecretStore(testStorage),
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

    // the song came from the server: streamed, or already kept by the Top 100 (it has plays
    // on the server, the fake is « at home ») and read from that copy
    final served = server.requests.where(
      (r) => r.method == 'stream' || r.method == 'download',
    );
    expect(served, isNotEmpty);
    expect(served.first.params['id'], 's-1');
    // every request carried the header and a good token
    expect(server.requests.where((r) => r.status != 200), isEmpty);

    await player.toggle(); // pause
    await tester.pump(const Duration(milliseconds: 200));

    // the copies made go to the phone's own folder: remove them
    await app.downloader.forget([...(await app.db.watchOffline().first).keys]);
  });
}
