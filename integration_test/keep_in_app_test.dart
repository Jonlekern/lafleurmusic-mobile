// End-to-end run of plan 10 (music inside the app): the real app against the fake Subsonic
// server, through the real « Sur mon iPhone » screen.
//
//   flutter test integration_test/keep_in_app_test.dart -d <phone>
//
// Account → keep an album (the ⬇ pill) → its files are in the visible LAFLEURMUSIC folder →
// « Sur mon iPhone » › « Dans l'appli seulement » › « Déplacer » → the visible folder no longer
// has them, they are in the app's private folder (keys `app://`) → the server is cut → a kept
// song plays from its copy → « Dans un dossier visible » › « Déplacer » → the files are back in
// the visible folder at the same relative paths. A file put there by hand never moves and stays
// in the library the whole time.
//
// Same clean start and cleanup as the other runs (`mountGuarded`); the hand-placed file is
// removed at the end, and nothing else of the phone's folders is touched.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lafleurmusic/library/db.dart' show OfflineRow;
import 'package:lafleurmusic/library/models.dart';
import 'package:lafleurmusic/main.dart';
import 'package:lafleurmusic/offline/device.dart' show appScheme;
import 'package:lafleurmusic/sources/secret_store.dart';
import 'package:lafleurmusic/sources/source.dart';
import 'package:lafleurmusic/ui/keep_actions.dart' show onIphone;
import 'package:mpv_audio_kit/mpv_audio_kit.dart' show MpvAudioKit;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'fake_subsonic.dart';
import 'fixture_bytes.dart';
import 'offline_test.dart' show waitFor;
import 'ui_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MpvAudioKit.ensureInitialized();

  late FakeSubsonic server;
  late Directory support;

  setUpAll(() async {
    server = await FakeSubsonic.start();
    support = Directory(
      '${(await getTemporaryDirectory()).path}/lafleurmusic-e2e-keep-in-app',
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
    'kept album → into the app → plays offline → back to the visible folder',
    (tester) async {
      final app = await mountGuarded(
        () => buildLafleurApp(
          support: support,
          secrets: SecureSecretStore(testStorage),
        ),
      );
      // if the run fails while in app mode, mountGuarded still forgets its copies: forget
      // deletes in the kept root, which is the private folder at that point
      final s = app.strings;
      final device = app.downloader.device;
      await tester.pumpWidget(app);

      // account (screen 7), as in offline_test.dart
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

      // a file put by hand in the visible folder (the test removes it at the end)
      final visible = await device.visibleRoot();
      visible.createSync(recursive: true);
      final hand = File(p.join(visible.path, 'Plan10 e2e tone.flac'));
      expect(hand.existsSync(), isFalse, reason: 'not a file of the phone');
      hand.writeAsBytesSync(base64Decode(aFlacBase64), flush: true);
      addTearDown(() {
        if (hand.existsSync()) hand.deleteSync();
      });
      Future<bool> handListed() async => (await app.db.localTracks()).any(
        (t) => p.basename(t.path) == 'Plan10 e2e tone.flac',
      );
      await app.localFolder.rescan();
      await waitFor(tester, handListed, 'the hand-placed file is listed');

      // keep the whole album: the ⬇ pill of the album screen
      await tapVisible(tester, studio.first);
      final surf = find.text('Surf Break');
      await pumpUntil(tester, surf);
      final keepPill = find.byTooltip(s.keepOnDevice(onIphone));
      await pumpUntil(tester, keepPill.hitTestable());
      await tester.pump(
        const Duration(milliseconds: 600),
      ); // the page has stopped sliding
      await tester.tap(keepPill.hitTestable().first);
      await tester.pump();

      final albums = await app.library.albums().first;
      final tracks = await app.library
          .albumTracks(albums.firstWhere((a) => a.name == 'Studio Lafleur').key)
          .first;
      expect(tracks, hasLength(2));
      final track = tracks.firstWhere((t) => t.title == 'Surf Break');
      Future<Map<String, OfflineRow>> rows() async =>
          (await app.db.watchOffline().first);
      await waitFor(
        tester,
        () async {
          final r = await rows();
          return tracks.every(
            (t) => r[t.path]?.state == OfflineState.done.name,
          );
        },
        'album kept',
        timeout: const Duration(seconds: 60),
        why: () async =>
            'rows: ${[for (final r in (await rows()).values) '${r.trackPath} ${r.state}']}, '
            'access denied: ${app.downloader.accessDenied}, '
            'last error: ${app.downloader.lastError}',
      );
      await app.downloader.whenIdle();

      // every kept file is in the visible folder
      final kept = {
        for (final r in (await rows()).values)
          if (r.state == OfflineState.done.name) r.trackPath: r.filePath!,
      };
      expect(kept.keys, containsAll(tracks.map((t) => t.path)));
      for (final rel in kept.values) {
        expect(
          File(p.join(visible.path, rel)).existsSync(),
          isTrue,
          reason: '$rel in the visible folder',
        );
      }
      expect(app.settings.keepInApp, isFalse);
      debugPrint(
        'PREUVE gardé : ${kept.values.join(', ')} dans le dossier visible',
      );

      // home › « Sur mon iPhone »
      Future<void> openOnDevice() async {
        await tapVisible(tester, find.text(s.onDevice(onIphone)));
        await pumpUntil(tester, find.text(s.keepInApp));
        await tester.pump(const Duration(milliseconds: 600));
      }

      Future<void> switchTo(String card, {required bool inApp}) async {
        await tapVisible(tester, find.byKey(Key(card)));
        final yes = find.byKey(const Key('moveKept'));
        await pumpUntil(tester, yes.hitTestable());
        expect(find.text(s.moveAction), findsOneWidget);
        await tester.pump(
          const Duration(milliseconds: 400),
        ); // the dialog is still opening
        await tester.tap(yes.hitTestable().first);
        await tester.pump();
        await waitFor(
          tester,
          () async =>
              app.settings.keepInApp == inApp && !app.downloader.isMoving,
          'moved (in the app: $inApp)',
          timeout: const Duration(seconds: 60),
          why: () async =>
              'keepInApp ${app.settings.keepInApp}, '
              'moving ${app.downloader.isMoving}, '
              'last error: ${app.downloader.lastError}',
        );
        await tester.pump(const Duration(seconds: 1));
      }

      await tapVisible(tester, find.text(s.albumsBack));
      await tester.pump(const Duration(milliseconds: 500));
      await openOnDevice();
      await switchTo('keepInApp', inApp: true);

      // the visible folder no longer has them; the private folder does, under `app://` keys
      final private = await device.privateRoot(create: false);
      expect(p.isWithin(visible.path, private.path), isFalse);
      final after = await rows();
      for (final e in kept.entries) {
        expect(
          after[e.key]?.filePath,
          e.value,
          reason: 'rows keep the same relative path',
        );
        expect(
          File(p.join(visible.path, e.value)).existsSync(),
          isFalse,
          reason: '${e.value} left the visible folder',
        );
        final moved = File(p.join(private.path, e.value));
        expect(
          moved.existsSync(),
          isTrue,
          reason: '${e.value} in the private folder',
        );
        expect(await moved.length(), after[e.key]!.size);
        final key = await device.keyFor(moved.path);
        expect(key, '$appScheme${e.value}');
        expect(await device.absolutePath(key), moved.path);
      }
      expect((await device.keptRoot()).path, private.path);
      expect((await device.visibleRoot()).path, visible.path);
      if (Platform.isAndroid) {
        // Android 7–10: the media scanner skips a folder with a .nomedia file
        expect(
          File(p.join(private.path, '.nomedia')).existsSync(),
          isTrue,
          reason: 'the private folder is never indexed by the media scanner',
        );
      }
      expect(hand.existsSync(), isTrue, reason: 'the hand-placed file stays');
      expect(await handListed(), isTrue, reason: 'and still in the library');
      debugPrint('PREUVE dans l\'appli : ${private.path}');

      // the server is cut: the kept song plays from the private folder
      await tapVisible(tester, find.text(s.home));
      await tester.pump(const Duration(milliseconds: 500));
      server.down = true;
      await app.accountService.checkAccounts();
      await waitFor(
        tester,
        () async => app.accountService.offline,
        'account unreachable',
      );
      expect(app.accountService.playableNow(track), isTrue);
      await tapVisible(tester, studio.first);
      await pumpUntil(tester, surf);
      final streamsBefore = server.requests
          .where((r) => r.method == 'stream')
          .length;
      await tester.tap(surf.first);
      final player = app.player;
      await waitFor(
        tester,
        () async =>
            player.current.track?.path == track.path &&
            player.current.position > const Duration(milliseconds: 500),
        'plays offline from the app',
        timeout: const Duration(seconds: 30),
      );
      expect(
        server.requests.where((r) => r.method == 'stream').length,
        streamsBefore,
        reason: 'played from the copy, not streamed',
      );
      if (player.current.playing) await player.toggle();
      debugPrint(
        'PREUVE hors ligne : ${player.current.track?.title} à '
        '${player.current.position}',
      );
      server.down = false;
      await app.accountService.checkAccounts();

      // back to the visible folder, through the screen
      await tapVisible(tester, find.text(s.albumsBack));
      await tester.pump(const Duration(milliseconds: 500));
      await openOnDevice();
      await switchTo('keepVisible', inApp: false);

      final back = await rows();
      for (final e in kept.entries) {
        expect(back[e.key]?.filePath, e.value);
        final file = File(p.join(visible.path, e.value));
        expect(
          file.existsSync(),
          isTrue,
          reason: '${e.value} back at the same relative path',
        );
        expect(await file.length(), back[e.key]!.size);
        expect(
          File(p.join(private.path, e.value)).existsSync(),
          isFalse,
          reason: '${e.value} left the app',
        );
      }
      expect((await device.keptRoot()).path, visible.path);
      expect(hand.existsSync(), isTrue);
      expect(await handListed(), isTrue);
      expect(
        (await app.db.localTracks()).where(
          (t) => kept.values.any((rel) => t.path.endsWith(rel)),
        ),
        isEmpty,
        reason: 'no kept copy came back as a hand-placed file',
      );
      debugPrint(
        'PREUVE retour : ${kept.values.join(', ')} dans le dossier visible',
      );
    },
  );
}
