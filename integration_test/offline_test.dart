// End-to-end run of plan 2 (offline): the real app against the fake Subsonic server, which
// the test cuts and brings back.
//
//   flutter test integration_test/offline_test.dart -d <phone>
//
// Account → open the album → long-press a song → « Garder sur mon iPhone » → the copy is `done`
// and its file is under the LAFLEURMUSIC folder → the server is cut → the song plays from its copy
// while the other one is greyed out → that listen is queued → the server comes back → it
// receives the listen, with its original time.
//
// Same clean start as app_test.dart (own library folder, own keychain namespace). The copies go
// to the phone's real LAFLEURMUSIC folder (iOS: Documents, Android: Music): the test removes
// the one it made.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lafleurmusic/library/models.dart';
import 'package:lafleurmusic/main.dart';
import 'package:lafleurmusic/sources/secret_store.dart';
import 'package:lafleurmusic/sources/source.dart';
import 'package:lafleurmusic/ui/keep_actions.dart' show onIphone;
import 'package:mpv_audio_kit/mpv_audio_kit.dart' show MpvAudioKit;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'fake_subsonic.dart';
import 'ui_helpers.dart';

/// Waits (pumping frames) until [done] says yes, at most [timeout].
Future<void> waitFor(
  WidgetTester tester,
  Future<bool> Function() done,
  String what, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final end = DateTime.now().add(timeout);
  while (!await done()) {
    if (DateTime.now().isAfter(end)) {
      throw TestFailure('Not within $timeout: $what');
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MpvAudioKit.ensureInitialized();

  late FakeSubsonic server;
  late Directory support;

  setUpAll(() async {
    server = await FakeSubsonic.start(secondAlbum: true);
    support = Directory(
      '${(await getTemporaryDirectory()).path}/lafleurmusic-e2e-offline',
    );
    if (support.existsSync()) support.deleteSync(recursive: true);
    support.createSync(recursive: true);
    await testStorage.deleteAll();
  });

  tearDownAll(() async {
    await testStorage.deleteAll();
    await server.close();
  });

  testWidgets(
    'keep a song → server cut → plays from the copy → listen sent on return',
    (tester) async {
      final app = await buildLafleurApp(
        support: support,
        secrets: SecureSecretStore(testStorage),
      );
      final s = app.strings;
      await tester.pumpWidget(app);

      // account (screen 7), as in app_test.dart
      await pumpUntil(tester, find.byKey(const ValueKey('account-address')));
      await typeInto(tester, 'account-name', 'Fake Navidrome');
      await typeInto(tester, 'account-address', server.address);
      await typeInto(tester, 'account-user', server.user);
      await typeInto(tester, 'account-password', server.password);
      await tapVisible(tester, find.text(s.addHeader));
      await typeInto(tester, 'header-0-name', fakeHeader);
      await typeInto(tester, 'header-0-value', fakeHeaderValue);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump(const Duration(milliseconds: 500));
      await tapVisible(tester, find.text(s.testAction));
      await pumpUntil(tester, find.text(s.testResult(TestResult.ok)));
      await tapVisible(tester, find.text(s.save));
      final studio = find.text('Studio Lafleur');
      await pumpUntil(tester, studio);
      await pumpUntil(tester, find.text('Lafleur Surf'));
      await tapVisible(tester, studio.first);
      final surf = find.text('Surf Break');
      await pumpUntil(tester, surf);

      // long-press a song → keep it on the phone. (« Night Drive » has plays on the server: the
      // Top 100 may keep it by itself at home, so it is not the one to watch.)
      await tester.longPress(surf.first);
      await pumpUntil(tester, find.text(s.keepOnDevice(onIphone)));
      await waitFor(
        tester,
        () async =>
            tester.getCenter(find.text(s.keepOnDevice(onIphone))).dy <
            tester.view.physicalSize.height / tester.view.devicePixelRatio,
        'the sheet slid up',
      );
      await tester.tap(find.text(s.keepOnDevice(onIphone)));
      await tester.pump();

      final tracks = await app.db.watchAlbumTracks('Studio Lafleur').first;
      final track = tracks.firstWhere((t) => t.title == 'Surf Break');
      final other =
          (await app.db.watchAlbumTracks('Lafleur Surf').first).single;
      await waitFor(
        tester,
        () async =>
            (await app.db.offlineOf(track.path))?.state ==
            OfflineState.done.name,
        'copy done',
      );

      // the file is under the LAFLEURMUSIC folder, whole
      final row = (await app.db.offlineOf(track.path))!;
      final root = await const MethodChannel('studio.lafleur/device')
          .invokeMethod<String>('defaultRoot');
      final file = File(p.join(root!, row.filePath!));
      expect(file.existsSync(), isTrue, reason: 'file under $root');
      expect(await file.length(), row.size);
      expect(await file.length(), greaterThan(10000));
      final downloaded = server.requests
          .where((r) => r.method == 'download')
          .map((r) => r.params['id']);
      expect(downloaded, contains('s-2'));
      expect(downloaded, isNot(contains('s-3')));
      expect(server.requests.where((r) => r.status != 200), isEmpty);
      debugPrint('PREUVE copie : ${row.filePath} (${row.size} octets)');

      // the server is cut: the app notices (the path the network changing takes)
      server.down = true;
      final id = (await app.accounts.watch().first).first.id;
      await app.accountService.checkAccounts();
      await waitFor(
        tester,
        () async => app.accountService.offline,
        'account unreachable',
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(app.accountService.playableNow(track), isTrue);
      expect(app.accountService.playableNow(other), isFalse);

      // the album never kept: its song is greyed, « Johnny · pas sur l'iPhone »
      await tapVisible(tester, find.text(s.albumsBack));
      await tester.pump(const Duration(milliseconds: 500));
      await pumpUntil(tester, find.text('Lafleur Surf'));
      await tapVisible(tester, find.text('Lafleur Surf').first);
      await pumpUntil(tester, find.text('Wave Rider'));
      expect(find.text(s.notOnDevice(other.artist, onIphone)), findsOneWidget);
      await tapVisible(tester, find.text(s.albumsBack));
      await tester.pump(const Duration(milliseconds: 500));
      await tapVisible(tester, studio.first);
      await pumpUntil(tester, surf);
      expect(find.text(s.notOnDevice(track.artist, onIphone)), findsNothing);

      // the kept song plays from its copy (3 s: a listen counts after 1.5 s)
      final before = DateTime.now();
      final streamsBefore = server.requests
          .where((r) => r.method == 'stream')
          .length;
      await tester.tap(surf.first);
      final player = app.player;
      await waitFor(
        tester,
        () async =>
            player.current.track?.path == track.path &&
            player.current.position > const Duration(seconds: 2),
        'plays offline past 2 s',
        timeout: const Duration(seconds: 15),
      );
      expect(player.current.playing, isTrue);
      expect(
        server.requests.where((r) => r.method == 'stream').length,
        streamsBefore,
        reason: 'played from the copy, not streamed',
      );
      await player.toggle();
      debugPrint(
        'PREUVE hors ligne : ${player.current.track?.title} à '
        '${player.current.position}, ${server.refused} connexions coupées',
      );

      // the listen waits in the queue (the server can't be told)
      await waitFor(
        tester,
        () async => (await app.db.pending(id)).isNotEmpty,
        'listen pending',
      );
      expect((await app.db.pending(id)).map((q) => q.remoteId), ['s-2']);
      expect(server.requests.where((r) => r.method == 'scrobble'), isEmpty);
      final beforeBack = DateTime.now();

      // the server comes back: the next check sends it, dated when it was heard
      server.down = false;
      await app.accountService.checkAccounts();
      await waitFor(
        tester,
        () async => server.requests.any((r) => r.method == 'scrobble'),
        'scrobble received',
      );
      final scrobbles = server.requests
          .where((r) => r.method == 'scrobble')
          .toList();
      expect(scrobbles, hasLength(1));
      expect(scrobbles.single.params['id'], 's-2');
      final at = DateTime.fromMillisecondsSinceEpoch(
        int.parse(scrobbles.single.params['time']!),
      );
      expect(
        at.isAfter(before) && at.isBefore(beforeBack),
        isTrue,
        reason: '$at',
      );
      await waitFor(
        tester,
        () async => (await app.db.pending(id)).isEmpty,
        'pending emptied',
      );
      debugPrint(
        'PREUVE scrobble : reçu, daté $at (écouté entre $before et $beforeBack)',
      );

      // clean up the copy we made
      await app.downloader.forget([
        ...(await app.db.watchOffline().first).keys,
      ]);
      expect(file.existsSync(), isFalse);
    },
  );
}
