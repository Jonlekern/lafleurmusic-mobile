// End-to-end run of plan 9 (editable playlists), no account at all: the real app with only the
// music on the phone.
//
//   flutter test integration_test/playlists_phone_test.dart -d <phone>
//
// First launch → « Juste la musique de mon iPhone » → a file put by hand in the LAFLEURMUSIC
// folder shows → « Ajouter à une playlist » › « Nouvelle playlist » makes a playlist on the
// phone → it is kept: `Playlists/<name>.m3u8` is written → « Modifier » renames it: the file is
// renamed → « Modifier » › « Supprimer la playlist »: the `.m3u8` is gone, the song is still there.
//
// One test, one app (a second app in the same process would need a second OS media session).
// Same clean start as the other runs (own library folder, own keychain namespace) and the same
// safe cleanup (`mountGuarded`): the `.m3u8` the app made is removed, and the one file this test
// put in the folder; nothing else of the phone's folder is touched.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lafleurmusic/main.dart';
import 'package:lafleurmusic/sources/secret_store.dart';
import 'package:lafleurmusic/ui/phone/add_to_playlist_sheet.dart';
import 'package:lafleurmusic/ui/phone/playlist_screen.dart' show openPlaylist;
import 'package:mpv_audio_kit/mpv_audio_kit.dart' show MpvAudioKit;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'fixture_bytes.dart';
import 'offline_test.dart' show waitFor;
import 'ui_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MpvAudioKit.ensureInitialized();

  late Directory support;

  setUpAll(() async {
    support = Directory(
      '${(await getTemporaryDirectory()).path}/lafleurmusic-e2e-playlists-phone',
    );
    if (support.existsSync()) support.deleteSync(recursive: true);
    support.createSync(recursive: true);
    await testStorage.deleteAll();
  });

  tearDownAll(() async {
    await testStorage.deleteAll();
  });

  testWidgets(
    'no account: a phone playlist → kept → .m3u8 → renamed → deleted',
    (tester) async {
      final app = await mountGuarded(
        () => buildLafleurApp(
          support: support,
          secrets: SecureSecretStore(testStorage),
        ),
      );
      final s = app.strings;
      await tester.pumpWidget(app);

      // first launch: the account screen, and its way out
      await pumpUntil(tester, find.byKey(const Key('justThePhoneMusic')));
      await tapVisible(tester, find.byKey(const Key('justThePhoneMusic')));
      await pumpUntil(tester, find.text(s.noMusicYet));
      expect(await app.accounts.watch().first, isEmpty);

      // a file put by hand in the phone's folder (the test removes it at the end)
      final root = await deviceRoot();
      root.createSync(recursive: true);
      final file = File(p.join(root.path, 'Plan9 e2e tone.flac'));
      expect(file.existsSync(), isFalse, reason: 'not a file of the phone');
      file.writeAsBytesSync(base64Decode(aFlacBase64), flush: true);
      addTearDown(() {
        if (file.existsSync()) file.deleteSync();
      });
      await app.localFolder.rescan();
      await waitFor(
        tester,
        () async => (await app.db.localTracks()).any(
          (t) => p.basename(t.path) == 'Plan9 e2e tone.flac',
        ),
        'the local file is in the library',
      );
      await pumpUntil(tester, find.byType(ListView));
      await waitFor(
        tester,
        () async => find.text(s.noMusicYet).evaluate().isEmpty,
        'Home leaves the « no music » screen',
      );
      final song = (await app.db.localTracks()).firstWhere(
        (t) => p.basename(t.path) == 'Plan9 e2e tone.flac',
      );

      BuildContext screen() => tester.element(find.byType(Scaffold).first);
      Future<void> tapKey(Key k) async {
        // on screen (a page still sliding in is not), then tapped
        await pumpUntil(tester, find.byKey(k).hitTestable());
        await tester.tap(find.byKey(k).hitTestable().first);
        await tester.pump(const Duration(milliseconds: 300));
      }

      // « Ajouter à une playlist » › « Nouvelle playlist » (no account: the playlist stays on the phone)
      unawaited(showAddToPlaylist(screen(), [song]));
      await tapKey(const Key('addNew'));
      await pumpUntil(tester, find.byKey(const Key('newPlaylistName')));
      expect(
        find.text(s.whereToKeep),
        findsNothing,
        reason: 'no account: no place to choose',
      );
      await tester.enterText(
        find.byKey(const Key('newPlaylistName')),
        'Plan9 Phone e2e',
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tapKey(const Key('newPlaylistCreate'));
      await tapKey(const Key('addOk'));
      await waitFor(
        tester,
        () async => (await app.db.watchPlaylists().first).any(
          (l) => l.onPhone && l.name == 'Plan9 Phone e2e' && l.songCount == 1,
        ),
        'the phone playlist holds the song',
      );
      final made = (await app.db.watchPlaylists().first).singleWhere(
        (l) => l.onPhone,
      );

      // kept: its `.m3u8` is under Playlists/
      final dir = Directory(p.join(root.path, 'Playlists'));
      File m3u8(String name) => File(p.join(dir.path, '$name.m3u8'));
      List<String> names() => dir.existsSync()
          ? [
              for (final f in dir.listSync().whereType<File>())
                p.basename(f.path),
            ]
          : const [];
      final kept = await app.downloader.keepPlaylist(made.accountId, made.id);
      expect(kept.ok, isTrue);
      await waitFor(
        tester,
        () async =>
            m3u8('Plan9 Phone e2e').existsSync() &&
            m3u8('Plan9 Phone e2e').readAsStringSync().contains('.flac'),
        '.m3u8 written',
        timeout: const Duration(seconds: 30),
        why: () async => 'files: ${names()}',
      );
      expect(names(), ['Plan9 Phone e2e.m3u8']);
      expect(
        m3u8('Plan9 Phone e2e').readAsStringSync().startsWith('#EXTM3U'),
        isTrue,
      );
      debugPrint(
        'PREUVE playlist du téléphone : Playlists/Plan9 Phone e2e.m3u8 écrit',
      );

      // « Modifier » › the name › OK: the file follows
      unawaited(openPlaylist(screen(), made));
      await tapKey(const Key('plEdit'));
      await pumpUntil(tester, find.byKey(const Key('editName')));
      await tester.enterText(
        find.byKey(const Key('editName')),
        'Plan9 Renamed',
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tapKey(const Key('editOk'));
      await waitFor(
        tester,
        () async =>
            m3u8('Plan9 Renamed').existsSync() &&
            !m3u8('Plan9 Phone e2e').existsSync(),
        'the .m3u8 is renamed',
        timeout: const Duration(seconds: 30),
        why: () async => 'files: ${names()}',
      );
      expect(names(), ['Plan9 Renamed.m3u8']);
      debugPrint('PREUVE renommée : Playlists/Plan9 Renamed.m3u8');

      // « Modifier » › « Supprimer la playlist » › yes: the `.m3u8` is gone, the song stays
      await tapKey(const Key('plEdit'));
      await tapKey(const Key('editDelete'));
      await tapKey(const Key('questionYes'));
      await waitFor(
        tester,
        () async =>
            names().isEmpty && (await app.db.watchPlaylists().first).isEmpty,
        'playlist and .m3u8 deleted',
        timeout: const Duration(seconds: 30),
        why: () async => 'files: ${names()}',
      );
      expect(
        file.existsSync(),
        isTrue,
        reason: 'the song is still on the phone',
      );
      expect(
        (await app.db.localTracks()).any((t) => t.path == song.path),
        isTrue,
        reason: 'and in the library',
      );
      expect(await app.db.keptPlaylistRows(), isEmpty);
      debugPrint('PREUVE suppression : .m3u8 parti, le morceau est resté');
    },
  );
}
