// End-to-end run of plan 3 (several accounts merged): the real app against TWO fake Subsonic
// servers at once (fake_subsonic.dart), which carry the same album.
//
//   flutter test integration_test/accounts_test.dart -d <phone>
//
// Two accounts → the album shows once (its songs once) → the first server is cut → the song
// plays from the second one and the listen goes to the second one → the first comes back →
// a server playlist is kept → its `.m3u8` file is under Playlists/ of the LAFLEURMUSIC folder.
//
// Same clean start as the other runs (own library folder, own keychain namespace) and the
// same safe cleanup (`mountGuarded`): the copies and the `.m3u8` the run made are removed,
// nothing else in the phone's folder is touched.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lafleurmusic/library/db.dart' show TrackRow;
import 'package:lafleurmusic/main.dart';
import 'package:lafleurmusic/sources/account_service.dart';
import 'package:lafleurmusic/sources/secret_store.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart' show MpvAudioKit;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'fake_subsonic.dart';
import 'offline_test.dart' show waitFor;
import 'ui_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MpvAudioKit.ensureInitialized();

  late FakeSubsonic first, second;
  late Directory support;

  setUpAll(() async {
    // no play counts: the Top 100 keeps nothing by itself, only what the run asks for
    first = await FakeSubsonic.start(
      topPlays: false,
      password: 'first-e2e',
      playlists: {
        'pl-1': ('Road Trip', ['s-2', 's-1']),
      },
    );
    second = await FakeSubsonic.start(topPlays: false, password: 'second-e2e');
    support = Directory(
      '${(await getTemporaryDirectory()).path}/lafleurmusic-e2e-accounts',
    );
    if (support.existsSync()) support.deleteSync(recursive: true);
    support.createSync(recursive: true);
    await testStorage.deleteAll();
  });

  tearDownAll(() async {
    await testStorage.deleteAll();
    await first.close();
    await second.close();
  });

  testWidgets(
    'two accounts: album once → first cut → plays and listens on the second → '
    'kept playlist → .m3u8',
    (tester) async {
      final app = await mountGuarded(
        () => buildLafleurApp(
          support: support,
          secrets: SecureSecretStore(testStorage),
        ),
      );
      await tester.pumpWidget(app);
      await tester.pump(const Duration(seconds: 1));

      // the two accounts, as the form saves them (the form itself is driven by app_test.dart)
      Future<String> add(String name, FakeSubsonic s) async =>
          (await app.accountService.save(
            AccountDraft(
              name: name,
              address: s.address,
              user: s.user,
              password: s.password,
              headers: const {fakeHeader: fakeHeaderValue},
            ),
          )).id;
      final id1 = await add('First', first);
      final id2 = await add('Second', second);

      // both synced: four rows (two songs on each account)…
      Future<List<TrackRow>> rows() => app.db.select(app.db.tracks).get();
      await waitFor(
        tester,
        () async => (await rows()).length >= 4,
        'both libraries synced',
        why: () async =>
            'rows: ${(await rows()).length}, '
            'first: ${first.requests}, second: ${second.requests}',
      );
      expect((await rows()).map((t) => t.accountId).toSet(), {id1, id2});

      // …but the album and its songs show once
      final albums = await app.library.albums().first;
      expect(albums.where((a) => a.name == 'Studio Lafleur'), hasLength(1));
      final album = albums.firstWhere((a) => a.name == 'Studio Lafleur');
      final songs = await app.library.albumTracks(album.key).first;
      expect(songs.map((t) => t.title), ['Night Drive', 'Surf Break']);
      debugPrint(
        'PREUVE fusion : ${(await rows()).length} lignes, '
        '${albums.length} album(s), ${songs.length} morceaux',
      );

      // the first server is cut: the app notices, and the song comes from the second one
      first.down = true;
      await app.accountService.checkAccounts();
      await waitFor(
        tester,
        () async => app.accountService.stateOf(id1) == AccountState.absent,
        'first account unreachable',
      );
      final nightDrive = songs.first;
      final streams1 = first.requests.where((r) => r.method == 'stream').length;
      await app.player.playTracks(songs, 0);
      final player = app.player;
      await waitFor(
        tester,
        () async =>
            player.current.track?.title == 'Night Drive' &&
            player.current.position > const Duration(milliseconds: 500),
        'plays from the second server',
        timeout: const Duration(seconds: 30),
        why: () async =>
            'at ${player.current.position}, second: ${second.requests}',
      );
      expect(
        second.requests
            .where((r) => r.method == 'stream')
            .map((r) => r.params['id']),
        contains('s-1'),
      );
      expect(
        first.requests.where((r) => r.method == 'stream').length,
        streams1,
        reason: 'nothing streamed from the cut server',
      );

      // the listen (counted at half of the song) goes to the second server, none to the first
      await waitFor(
        tester,
        () async => second.requests.any((r) => r.method == 'scrobble'),
        'listen sent to the second server',
        timeout: const Duration(seconds: 60),
      );
      final scrobbles = second.requests
          .where((r) => r.method == 'scrobble')
          .toList();
      expect(scrobbles.first.params['id'], 's-1');
      expect(first.requests.where((r) => r.method == 'scrobble'), isEmpty);
      debugPrint(
        'PREUVE écoute : ${nightDrive.title} lu depuis le 2e serveur, '
        'écoute reçue par lui (${scrobbles.length}), aucune par le 1er',
      );
      if (player.current.playing) await player.toggle();

      // the first server comes back; its playlist is stored, then kept
      first.down = false;
      await app.accountService.checkAccounts();
      await waitFor(
        tester,
        () async => app.accountService.stateOf(id1) != AccountState.absent,
        'first account back',
      );
      await app.accountService.sync(id1);
      await waitFor(
        tester,
        () async => (await app.db.playlistsOf(id1)).any((l) => l.id == 'pl-1'),
        'playlist stored',
      );
      final r = await app.downloader.keepPlaylist(id1, 'pl-1');
      expect(r.ok, isTrue);

      // its file is under Playlists/, with the songs in the server's order
      final root = await deviceRoot();
      final dir = Directory(p.join(root.path, 'Playlists'));
      List<File> files() => dir.existsSync()
          ? dir
                .listSync()
                .whereType<File>()
                .where((f) => f.path.endsWith('.m3u8'))
                .toList()
          : const [];
      await waitFor(
        tester,
        () async {
          final f = files();
          return f.isNotEmpty &&
              f.first.readAsStringSync().contains('Night Drive');
        },
        '.m3u8 written',
        timeout: const Duration(seconds: 60),
        why: () async =>
            'files: $files, kept: ${(await app.db.keptPlaylistRows()).length}',
      );
      final text = files().single.readAsStringSync();
      expect(p.basename(files().single.path), 'Road Trip.m3u8');
      expect(text.startsWith('#EXTM3U'), isTrue);
      expect(text.indexOf('Surf Break'), lessThan(text.indexOf('Night Drive')));
      expect(
        (await app.db.keptPlaylistRows()).single.fileName,
        'Road Trip.m3u8',
      );
      debugPrint('PREUVE playlist : Playlists/Road Trip.m3u8 écrit');

      // clean up what we made (mountGuarded also does it if anything above failed)
      await app.downloader.forgetPlaylist(id1, 'pl-1');
      expect(files(), isEmpty);
    },
  );
}
