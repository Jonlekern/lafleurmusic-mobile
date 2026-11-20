// End-to-end run of plans 3 to 5 (several accounts merged): the real app against TWO fake
// Subsonic servers (fake_subsonic.dart, both "Navidrome") and then a fake Jellyfin
// (fake_jellyfin.dart) and a fake Plex (fake_plex.dart), all carrying the same album.
//
//   flutter test integration_test/accounts_test.dart -d <phone>
//
// Two accounts → the album shows once (its songs once) → the first server is cut → the song
// plays from the second one and the listen goes to the second one → the first comes back →
// a server playlist is kept → its `.m3u8` file is under Playlists/ of the LAFLEURMUSIC folder.
// Plan 4: a Jellyfin account is added → the album still shows once (same album artist) → both
// Navidrome servers are cut → the song plays from Jellyfin, the best source left, and the
// listen goes to the Jellyfin account, none to Navidrome.
//
// Plan 5: a Plex account is added through the real code screen (the fake plex.tv validates the
// code at the first poll) → the album still shows once → the other three are cut → the song
// plays from Plex and the listen goes to Plex (none to the others) → a song is kept on the phone,
// copied from Plex.
//
// One test, one app: a second app in the same process would need a second OS media session.
//
// Same clean start as the other runs (own library folder, own keychain namespace) and the
// same safe cleanup (`mountGuarded`): the copies and the `.m3u8` the run made are removed,
// nothing else in the phone's folder is touched.
import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart' show CupertinoPageRoute;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lafleurmusic/library/db.dart' show OfflineRow, TrackRow;
import 'package:lafleurmusic/library/models.dart' show OfflineState;
import 'package:lafleurmusic/main.dart';
import 'package:lafleurmusic/offline/paths.dart' show isPartialName;
import 'package:lafleurmusic/ui/phone/account_form.dart';
import 'package:lafleurmusic/sources/account_service.dart';
import 'package:lafleurmusic/sources/accounts.dart' show AccountType;
import 'package:lafleurmusic/sources/plex_link.dart' show PlexLink;
import 'package:lafleurmusic/sources/secret_store.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart' show MpvAudioKit;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'fake_jellyfin.dart';
import 'fake_plex.dart';
import 'fake_subsonic.dart';
import 'offline_test.dart' show waitFor;
import 'ui_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MpvAudioKit.ensureInitialized();

  late FakeSubsonic first, second;
  late FakeJellyfin jellyfin;
  late FakePlex plex;
  late Directory support;

  setUpAll(() async {
    // no play counts: the Top 100 keeps nothing by itself, only what the run asks for
    first = await FakeSubsonic.start(
      topPlays: false,
      password: 'first-e2e',
      playlists: {
        'pl-1': ('Road Trip e2e', ['s-2', 's-1']),
      },
    );
    second = await FakeSubsonic.start(topPlays: false, password: 'second-e2e');
    jellyfin = await FakeJellyfin.start();
    plex = await FakePlex.start();
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
    await jellyfin.close();
    await plex.close();
  });

  testWidgets('two accounts: album once → first cut → plays and listens on the second → '
      'kept playlist → .m3u8 → Jellyfin → Plex', (tester) async {
    final app = await mountGuarded(
      () => buildLafleurApp(
        support: support,
        secrets: SecureSecretStore(testStorage),
        // the code screen talks to the fake plex.tv, never the real one
        plexLink: (id) => PlexLink(
          clientId: id,
          plexTv: plex.plexTv,
          pollEvery: const Duration(milliseconds: 300),
        ),
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
    // the app writes `<name>.lafleur-part.m3u8` then renames it: wait for the final name, with
    // nothing half-written left (the partial already holds the whole text before the rename)
    final want = File(p.join(dir.path, 'Road Trip e2e.m3u8'));
    await waitFor(
      tester,
      () async =>
          want.existsSync() &&
          want.readAsStringSync().contains('Night Drive') &&
          files().every((f) => !isPartialName(f.path)),
      '.m3u8 written',
      timeout: const Duration(seconds: 60),
      why: () async =>
          'files: ${files()}, kept: ${(await app.db.keptPlaylistRows()).length}',
    );
    expect(files().map((f) => p.basename(f.path)), ['Road Trip e2e.m3u8']);
    final text = want.readAsStringSync();
    expect(text.startsWith('#EXTM3U'), isTrue);
    expect(text.indexOf('Surf Break'), lessThan(text.indexOf('Night Drive')));
    expect(
      (await app.db.keptPlaylistRows()).single.fileName,
      'Road Trip e2e.m3u8',
    );
    debugPrint('PREUVE playlist : Playlists/Road Trip e2e.m3u8 écrit');

    // clean up what we made (mountGuarded also does it if anything above failed)
    await app.downloader.forgetPlaylist(id1, 'pl-1');
    expect(files(), isEmpty);

    // ---- plan 4: a Jellyfin account with the same album ----
    final idJf = (await app.accountService.save(
      AccountDraft(
        type: AccountType.jellyfin,
        name: 'Jellyfin',
        address: jellyfin.address,
        user: jellyfin.user,
        password: jellyfin.password,
        headers: const {fakeHeader: fakeHeaderValue},
      ),
    )).id;
    Future<List<TrackRow>> jfRows() async =>
        (await rows()).where((t) => t.accountId == idJf).toList();
    await waitFor(
      tester,
      () async => (await jfRows()).length >= 2,
      'Jellyfin library synced',
      why: () async => 'jellyfin: ${jellyfin.requests}',
    );
    expect(
      (await jfRows()).every((t) => t.path.startsWith('jellyfin://')),
      isTrue,
    );

    // still one album (same name, same album artist), its songs once
    final albumsJf = await app.library.albums().first;
    expect(albumsJf.where((a) => a.name == 'Studio Lafleur'), hasLength(1));
    final albumJf = albumsJf.firstWhere((a) => a.name == 'Studio Lafleur');
    final songsJf = await app.library.albumTracks(albumJf.key).first;
    expect(songsJf.map((t) => t.title), ['Night Drive', 'Surf Break']);
    debugPrint(
      'PREUVE fusion Jellyfin : ${(await rows()).length} lignes, '
      '${albumsJf.where((a) => a.name == 'Studio Lafleur').length} album, '
      '${songsJf.length} morceaux',
    );

    // both Navidrome servers cut: Jellyfin is the best source left
    first.down = true;
    second.down = true;
    await app.accountService.checkAccounts();
    await waitFor(
      tester,
      () async =>
          app.accountService.stateOf(id1) == AccountState.absent &&
          app.accountService.stateOf(id2) == AccountState.absent,
      'both Navidrome accounts unreachable',
    );
    expect(app.accountService.stateOf(idJf), isNot(AccountState.absent));
    int navidromeCalls(String method) => [
      ...first.requests,
      ...second.requests,
    ].where((r) => r.method == method).length;
    final ndStreams = navidromeCalls('stream');
    final ndScrobbles = navidromeCalls('scrobble');
    await app.player.playTracks(songsJf, 0);
    await waitFor(
      tester,
      () async =>
          jellyfin.requests.any(
            (r) => r.method == 'stream' && r.params['id'] == 'jf-s-1',
          ) &&
          player.current.track?.title == 'Night Drive' &&
          player.current.playing &&
          player.current.position > const Duration(milliseconds: 500),
      'plays from Jellyfin',
      timeout: const Duration(seconds: 30),
      why: () async =>
          'at ${player.current.position}, jellyfin: ${jellyfin.requests}',
    );
    expect(
      navidromeCalls('stream'),
      ndStreams,
      reason: 'nothing streamed from the cut servers',
    );

    // the listen goes to the Jellyfin account, none to Navidrome
    await waitFor(
      tester,
      () async => jellyfin.playCount('jf-s-1') > 0,
      'listen sent to Jellyfin',
      timeout: const Duration(seconds: 60),
      why: () async => 'jellyfin: ${jellyfin.requests}',
    );
    expect(navidromeCalls('scrobble'), ndScrobbles);
    debugPrint(
      'PREUVE écoute Jellyfin : Night Drive lu depuis Jellyfin, écoute reçue '
      'par lui (${jellyfin.playCount('jf-s-1')}), aucune par Navidrome',
    );
    if (player.current.playing) await player.toggle();
    first.down = false;
    second.down = false;

    // ---- plan 5: a Plex account, added through the real code screen ----
    final s = app.strings;
    final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
    unawaited(
      nav.push<void>(
        CupertinoPageRoute(builder: (_) => const AccountFormScreen()),
      ),
    );
    await pumpUntil(tester, find.text(s.typeName(AccountType.plex)));
    await tapVisible(tester, find.text(s.typeName(AccountType.plex)));
    await typeInto(tester, 'account-name', 'Plex e2e');
    await tapVisible(tester, find.text(s.plexSignIn));
    // the code screen asks plex.tv for a code, polls it, finds the one server, and saves
    await waitFor(
      tester,
      () async =>
          (await app.accounts.watch().first).any((a) => a.name == 'Plex e2e'),
      'Plex account saved by the code screen',
      timeout: const Duration(seconds: 30),
      why: () async => 'plex.tv: ${plex.tvRequests}, plex: ${plex.requests}',
    );
    await tester.pump(const Duration(seconds: 1));
    expect(
      find.byType(AccountFormScreen),
      findsNothing,
      reason: 'screens closed',
    );
    final idPlex = (await app.accounts.watch().first)
        .firstWhere((a) => a.name == 'Plex e2e')
        .id;
    expect(plex.tvRequests.map((r) => r.method), containsAll(['pin', 'poll']));
    Future<List<TrackRow>> plexRows() async =>
        (await rows()).where((t) => t.accountId == idPlex).toList();
    await waitFor(
      tester,
      () async => (await plexRows()).length >= 2,
      'Plex library synced',
      why: () async => 'plex: ${plex.requests}',
    );
    expect(
      (await plexRows()).every((t) => t.path.startsWith('plex://')),
      isTrue,
    );

    // still one album, its songs once
    final albumsPx = await app.library.albums().first;
    expect(albumsPx.where((a) => a.name == 'Studio Lafleur'), hasLength(1));
    final albumPx = albumsPx.firstWhere((a) => a.name == 'Studio Lafleur');
    final songsPx = await app.library.albumTracks(albumPx.key).first;
    expect(songsPx.map((t) => t.title), ['Night Drive', 'Surf Break']);
    debugPrint(
      'PREUVE fusion Plex : ${(await rows()).length} lignes, '
      '${albumsPx.where((a) => a.name == 'Studio Lafleur').length} album, '
      '${songsPx.length} morceaux',
    );

    // the three others cut: Plex is the only source left
    first.down = true;
    second.down = true;
    jellyfin.down = true;
    await app.accountService.checkAccounts();
    await waitFor(
      tester,
      () async =>
          app.accountService.stateOf(id1) == AccountState.absent &&
          app.accountService.stateOf(id2) == AccountState.absent &&
          app.accountService.stateOf(idJf) == AccountState.absent,
      'the other three accounts unreachable',
    );
    expect(app.accountService.stateOf(idPlex), isNot(AccountState.absent));
    int othersCalls(String method) =>
        [
          ...first.requests,
          ...second.requests,
        ].where((r) => r.method == method).length +
        jellyfin.requests
            .where(
              (r) => r.method == (method == 'scrobble' ? 'played' : method),
            )
            .length;
    final otherStreams = othersCalls('stream');
    final otherScrobbles = othersCalls('scrobble');
    // a song (never played yet) is kept on the phone: the copy comes from Plex
    final surf = songsPx.firstWhere((t) => t.title == 'Surf Break');
    final kept = await app.downloader.keep([surf]);
    expect(kept.ok, isTrue);
    // the copy is filed under the Plex address of the song (the source it came from)
    Future<(String, OfflineRow)?> plexCopy() async =>
        (await app.db.watchOffline().first).entries
            .where((e) => e.key.startsWith('plex://'))
            .map((e) => (e.key, e.value))
            .firstOrNull;
    await waitFor(
      tester,
      () async => (await plexCopy())?.$2.state == OfflineState.done.name,
      'copy from Plex done',
      timeout: const Duration(seconds: 60),
      why: () async =>
          'copy: ${(await plexCopy())?.$2.state}, '
          'last error: ${app.downloader.lastError}, plex: ${plex.requests}',
    );
    final (copyPath, row) = (await plexCopy())!;
    final file = File(p.join(root.path, row.filePath!));
    expect(file.existsSync(), isTrue);
    expect(await file.length(), row.size);
    expect(
      plex.requests.any(
        (r) => r.method == 'download' && r.params['part'] == '9002',
      ),
      isTrue,
      reason:
          'plex: ${plex.requests.map((r) => '${r.method} ${r.params}').join(' ; ')}; '
          'row: $copyPath ${row.filePath}',
    );
    // forgotten again, so the next step plays it from Plex
    await app.downloader.forget([copyPath]);
    expect(file.existsSync(), isFalse);
    debugPrint('PREUVE copie Plex : ${row.filePath} (${row.size} octets)');

    // Surf Break: Night Drive was just played from Jellyfin and may still be on the phone's cache
    await app.player.playTracks(songsPx, 1);
    await waitFor(
      tester,
      () async => plex.requests.any(
        (r) => r.method == 'stream' && r.params['part'] == '9002',
      ),
      'plays from Plex',
      timeout: const Duration(seconds: 30),
      why: () async =>
          '${player.current.track?.title} playing ${player.current.playing} at '
          '${player.current.position}, plex: ${plex.requests.where((r) => r.method == 'stream' || r.method == 'download').map((r) => '${r.method} ${r.params}').join(' ; ')}',
    );
    expect(
      othersCalls('stream'),
      otherStreams,
      reason: 'nothing streamed from the cut servers',
    );

    // the listen goes to Plex, none to the others. A listen is counted when the position
    // crosses half of the song after being seen below it: the test tone is 3 s long, and on a slow
    // emulator (API 28) one play was seen not to be counted (Plex had answered the stream 200
    // all the same; likely a first position already past half). Then the song is played again from the start, up to three times: what is
    // proved is unchanged (a real play, counted by the app, received by Plex and by no other
    // server), the test only no longer depends on one lucky first play.
    var plays = 1;
    for (;;) {
      try {
        await waitFor(
          tester,
          () async => plex.playCount('322') > 0,
          'listen sent to Plex',
          timeout: const Duration(seconds: 40),
          why: () async => 'plex: ${plex.requests}',
        );
        break;
      } on TestFailure {
        if (plays == 3) rethrow;
        plays++;
        debugPrint('PREUVE écoute Plex : pas comptée, lecture $plays');
        await app.player.playTracks(songsPx, 1);
        await waitFor(
          tester,
          () async =>
              player.current.track?.title == 'Surf Break' &&
              player.current.position > const Duration(milliseconds: 300),
          'Surf Break plays again',
          timeout: const Duration(seconds: 30),
        );
      }
    }
    expect(othersCalls('scrobble'), otherScrobbles);
    // a replay did not reach for a cut server either
    expect(
      othersCalls('stream'),
      otherStreams,
      reason: 'nothing streamed from the cut servers, replays included',
    );
    debugPrint(
      'PREUVE écoute Plex : Surf Break lu depuis Plex, écoute reçue par lui '
      '(${plex.playCount('322')}), aucune par les autres',
    );
    if (player.current.playing) await player.toggle();

    jellyfin.down = false;
    first.down = false;
    second.down = false;
  });
}
