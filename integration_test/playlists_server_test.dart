// End-to-end run of plan 9 (editable playlists) against a fake Navidrome that keeps the
// playlists it is told to write (fake_subsonic.dart).
//
//   flutter test integration_test/playlists_server_test.dart -d <phone>
//
// Account → « Ajouter à une playlist » › « Nouvelle playlist » › the server's name › OK: the
// playlist exists on the server with the song → a second song is ticked into it → the same
// song again: « Déjà dans … », « Ignorer »: the server still has two songs → « Trier » (the
// order reversed) → the server's own list is in the new order, and so is the app's after a sync.
//
// One test, one app (a second app in the same process would need a second OS media session).
// Same clean start as the other runs (own library folder, own keychain namespace) and the same
// safe cleanup (`mountGuarded`).
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lafleurmusic/library/db.dart' show TrackRow;
import 'package:lafleurmusic/library/models.dart' show Track;
import 'package:lafleurmusic/main.dart';
import 'package:lafleurmusic/sources/account_service.dart';
import 'package:lafleurmusic/sources/secret_store.dart';
import 'package:lafleurmusic/ui/phone/add_to_playlist_sheet.dart';
import 'package:lafleurmusic/ui/phone/playlist_screen.dart' show openPlaylist;
import 'package:mpv_audio_kit/mpv_audio_kit.dart' show MpvAudioKit;
import 'package:path_provider/path_provider.dart';

import 'fake_subsonic.dart';
import 'offline_test.dart' show waitFor;
import 'ui_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MpvAudioKit.ensureInitialized();

  late FakeSubsonic server;
  late Directory support;

  setUpAll(() async {
    server = await FakeSubsonic.start(topPlays: false);
    support = Directory(
      '${(await getTemporaryDirectory()).path}/lafleurmusic-e2e-playlists-server',
    );
    if (support.existsSync()) support.deleteSync(recursive: true);
    support.createSync(recursive: true);
    await testStorage.deleteAll();
  });

  tearDownAll(() async {
    await testStorage.deleteAll();
    await server.close();
  });

  testWidgets('server playlist: create → add → no duplicate → sort → read back', (
    tester,
  ) async {
    final app = await mountGuarded(
      () => buildLafleurApp(
        support: support,
        secrets: SecureSecretStore(testStorage),
      ),
    );
    final s = app.strings;
    await tester.pumpWidget(app);
    await tester.pump(const Duration(seconds: 1));

    final id = (await app.accountService.save(
      AccountDraft(
        name: 'Fake Navidrome',
        address: server.address,
        user: server.user,
        password: server.password,
        headers: const {fakeHeader: fakeHeaderValue},
      ),
    )).id;
    Future<List<TrackRow>> rows() => app.db.select(app.db.tracks).get();
    await waitFor(
      tester,
      () async => (await rows()).length >= 2,
      'library synced',
      why: () async => 'server: ${server.requests}',
    );
    // the album and its two songs show (the rows land a little before the album does)
    Future<List<Track>> albumSongs() async {
      final album = (await app.library.albums().first)
          .where((a) => a.name == 'Studio Lafleur')
          .firstOrNull;
      return album == null
          ? const []
          : await app.library.albumTracks(album.key).first;
    }

    await waitFor(
      tester,
      () async => (await albumSongs()).length == 2,
      'the album shows with its two songs',
    );
    final songs = await albumSongs();
    final nightDrive = songs.singleWhere((t) => t.title == 'Night Drive');
    final surfBreak = songs.singleWhere((t) => t.title == 'Surf Break');

    // the Home of the account is on screen
    await pumpUntil(tester, find.text('Studio Lafleur'));
    BuildContext screen() => tester.element(find.byType(Scaffold).first);
    Future<void> tapKey(Key k) async {
      // on screen (a page still sliding in is not), then tapped
      await pumpUntil(tester, find.byKey(k).hitTestable());
      await tester.tap(find.byKey(k).hitTestable().first);
      await tester.pump(const Duration(milliseconds: 300));
    }

    List<String> onServer() =>
        server.playlists.values.singleOrNull?.$2 ?? const [];

    // 1. a new playlist, kept on the server, with Night Drive
    unawaited(showAddToPlaylist(screen(), [nightDrive]));
    await tapKey(const Key('addNew'));
    await pumpUntil(tester, find.byKey(const Key('newPlaylistName')));
    await tester.enterText(
      find.byKey(const Key('newPlaylistName')),
      'Plan9 Server e2e',
    );
    await tester.pump(const Duration(milliseconds: 300));
    // « Où la ranger » shows once the server is known to let us write
    await tapKey(Key('where-$id'));
    await tapKey(const Key('newPlaylistCreate'));
    await tapKey(const Key('addOk'));
    await waitFor(
      tester,
      () async => onServer().length == 1,
      'playlist created on the server',
      why: () async =>
          'playlists: ${server.playlists}, requests: ${server.requests}',
    );
    expect(server.playlists.values.single.$1, 'Plan9 Server e2e');
    expect(onServer(), ['s-1']);
    // sheet closing
    await waitFor(
      tester,
      () async => find.byKey(const Key('addOk')).evaluate().isEmpty,
      'the sheet is closed',
    );
    final plId = server.playlists.keys.single;
    await waitFor(
      tester,
      () async => (await app.db.watchPlaylists().first).any(
        (l) => l.accountId == id && l.id == plId,
      ),
      'the app stores it',
    );
    debugPrint(
      'PREUVE création : playlist $plId sur le serveur, ${onServer()}',
    );

    // 2. Surf Break ticked into it
    unawaited(showAddToPlaylist(screen(), [surfBreak]));
    await tapKey(Key('pl-$id/$plId'));
    await tapKey(const Key('addOk'));
    await waitFor(
      tester,
      () async => onServer().length == 2,
      'second song written',
      why: () async => 'requests: ${server.requests}',
    );
    expect(onServer(), ['s-1', 's-2']);
    await waitFor(
      tester,
      () async => find.byKey(const Key('addOk')).evaluate().isEmpty,
      'the sheet is closed',
    );

    // 3. Night Drive again: « Déjà dans … », « Ignorer »: nothing is written
    final writes = server.requests
        .where((r) => r.method == 'updatePlaylist')
        .length;
    unawaited(showAddToPlaylist(screen(), [nightDrive]));
    await tapKey(Key('pl-$id/$plId'));
    await tapKey(const Key('addOk'));
    await pumpUntil(tester, find.text(s.alreadyInTitle('Plan9 Server e2e')));
    await tapKey(const Key('questionNo')); // « Ignorer »
    await waitFor(
      tester,
      () async => find.byKey(const Key('addOk')).evaluate().isEmpty,
      'the sheet is closed after « Ignorer »',
    );
    expect(onServer(), ['s-1', 's-2'], reason: 'the duplicate was not added');
    expect(
      server.requests.where((r) => r.method == 'updatePlaylist').length,
      writes,
    );
    debugPrint(
      'PREUVE doublon : « Déjà dans … », ignoré, le serveur garde ${onServer()}',
    );

    // 4. « Trier » › the order reversed: the server's list is written again
    final pl = (await app.db.watchPlaylists().first).singleWhere(
      (l) => l.accountId == id && l.id == plId,
    );
    unawaited(openPlaylist(screen(), pl));
    await pumpUntil(tester, find.text('Surf Break'));
    await pumpUntil(tester, find.byKey(const Key('plSort')));
    // the edit buttons wait for the server's yes
    await waitFor(
      tester,
      () async => find.byKey(const Key('plAdd')).evaluate().isNotEmpty,
      'the playlist is editable',
    );
    await tapKey(const Key('plSort'));
    await tapKey(const Key('sort-reverse'));
    await pumpUntil(
      tester,
      find.text(s.sortServerQuestion('Plan9 Server e2e')),
    );
    await tapKey(const Key('questionYes'));
    await waitFor(
      tester,
      () async => onServer().join(',') == 's-2,s-1',
      'server order reversed',
      why: () async => 'now: ${onServer()}, requests: ${server.requests}',
    );

    // read back from the fake: its own list, then the app's after a sync
    expect(server.playlists[plId]!.$2, ['s-2', 's-1']);
    await app.accountService.sync(id);
    await waitFor(tester, () async {
      final titles = [
        for (final (_, t) in await app.db.watchPlaylistItems(id, plId).first)
          t?.title,
      ];
      return titles.join(',') == 'Surf Break,Night Drive';
    }, 'the app reads the new order back');
    debugPrint('PREUVE tri : le serveur a ${server.playlists[plId]!.$2}');
  });
}
