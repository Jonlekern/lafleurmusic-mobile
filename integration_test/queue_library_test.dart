// Plan 8, tâche 5 : la file et la bibliothèque sur le téléphone, avec des fichiers posés à la main
// (la bibliothèque essayée) ; le premier compte demandé au lancement vient d'un faux serveur.
//
//   flutter test integration_test/queue_library_test.dart -d <phone>
//
// Glisser à droite → bulle « Ajouté à la file » → Annuler ; glisser de nouveau → À suivre → Vider →
// confirmation : les ajouts partent, la suite de l'album reste ; « Aller à l'album » depuis En cours ;
// un tri d'albums choisi est gardé dans settings.json.
//
// Clean start every time: a library folder of its own (deleted first), and the files this run puts
// in the phone's folder (under `P8-e2e/`) are removed when it ends. The fake server (fake_subsonic.dart) only gets the first launch past the account screen.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_taglib/flutter_taglib.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lafleurmusic/main.dart';
import 'package:lafleurmusic/player/queue.dart' show Repeat;
import 'package:lafleurmusic/settings.dart';
import 'package:lafleurmusic/sources/secret_store.dart';
import 'package:lafleurmusic/ui/dialog_frame.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart' show MpvAudioKit;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'fake_subsonic.dart';
import 'fixture_bytes.dart';
import 'ui_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MpvAudioKit.ensureInitialized();

  late FakeSubsonic server;
  late Directory support;
  late Directory mine; // nos fichiers dans le dossier du téléphone

  // (titre, artiste, album, n°) : deux albums, le tri par artiste met Beta devant Alpha
  const songs = [
    ('Alpha 1', 'Zed', 'Alpha Album', 1),
    ('Alpha 2', 'Zed', 'Alpha Album', 2),
    ('Alpha 3', 'Zed', 'Alpha Album', 3),
    ('Alpha 4', 'Zed', 'Alpha Album', 4),
    ('Beta 1', 'Amy', 'Beta Album', 1),
    ('Beta 2', 'Amy', 'Beta Album', 2),
  ];

  setUpAll(() async {
    server = await FakeSubsonic.start(topPlays: false);
    support = Directory(
      '${(await getTemporaryDirectory()).path}/lafleurmusic-e2e-p8',
    );
    if (support.existsSync()) support.deleteSync(recursive: true);
    support.createSync(recursive: true);
    await testStorage.deleteAll();
    mine = Directory(p.join((await deviceRoot()).path, 'P8-e2e'));
    if (mine.existsSync()) mine.deleteSync(recursive: true);
    mine.createSync(recursive: true);
    for (final (title, artist, album, no) in songs) {
      final f = File(p.join(mine.path, '$title.flac'))
        ..writeAsBytesSync(base64Decode(aFlacBase64));
      final tag = TagLibFile.open(f.path)!;
      tag.title = title;
      tag.artist = artist;
      tag.album = album;
      tag.track = no;
      expect(tag.save(), isTrue);
      tag.close();
    }
  });

  tearDownAll(() async {
    if (mine.existsSync()) mine.deleteSync(recursive: true);
    await testStorage.deleteAll();
    await server.close();
  });

  testWidgets('local files: swipe, undo, clear, go to album, kept sort', (
    tester,
  ) async {
    final app = await mountGuarded(
      () => buildLafleurApp(
        support: support,
        secrets: SecureSecretStore(testStorage),
      ),
    );
    final s = app.strings;
    final player = app.player;
    await tester.pumpWidget(app);

    List<String> titles(Iterable<dynamic> tracks) => [
      for (final t in tracks) t.title as String,
    ];
    List<String> upcoming() {
      final q = player.queue!;
      return titles(q.order.sublist(q.position + 1));
    }

    // the phone asks for a first account (screen 7): a fake server, whose album is not used here;
    // the library under test is the files placed by hand
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
    await tapVisible(tester, find.text(s.save));

    // Home: the files placed by hand are in the library next to the server's album
    final alpha = find.text('Alpha Album');
    // the scan reads the folder, then the list shows the albums (it builds lazily: reveal scrolls)
    await tester.pump(const Duration(seconds: 3));
    await reveal(tester, alpha);
    expect(find.byKey(const ValueKey('account-address')), findsNothing);
    await tapVisible(tester, alpha.first);

    // play the first song: the rest of the album follows
    await pumpUntil(tester, find.text('Alpha 1'));
    await tapVisible(tester, find.text('Alpha 1'));
    final end = DateTime.now().add(const Duration(seconds: 15));
    while (player.current.track?.title != 'Alpha 1' || player.queue == null) {
      if (DateTime.now().isAfter(end)) fail('Alpha 1 did not start');
      await tester.pump(const Duration(milliseconds: 100));
    }
    // the sound is 3 s long: repeat this song, or the queue moves on while the test goes
    while (player.queue!.repeat != Repeat.one) {
      await player.cycleRepeat();
    }
    expect(upcoming(), ['Alpha 2', 'Alpha 3', 'Alpha 4']);

    // swipe right → bubble → Undo takes the addition back
    await tester.drag(find.text('Alpha 3'), const Offset(220, 0));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('queueToast')), findsOneWidget);
    expect(find.text(s.queueAdded), findsOneWidget);
    expect(player.queue!.addedCount, 1);
    expect(upcoming().first, 'Alpha 3'); // added songs come first
    await tester.tap(find.text(s.queueUndo));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('queueToast')), findsNothing);
    expect(player.queue!.addedCount, 0);
    expect(upcoming(), ['Alpha 2', 'Alpha 3', 'Alpha 4']);

    // swipe right twice more, then « Voir la file » opens Now playing
    await tester.drag(find.text('Alpha 4'), const Offset(220, 0));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.drag(find.text('Alpha 3'), const Offset(220, 0));
    await tester.pump(const Duration(milliseconds: 400));
    expect(player.queue!.addedCount, 2);
    expect(upcoming().take(2), ['Alpha 4', 'Alpha 3']);
    await tester.tap(find.text(s.queueView));
    await pumpUntil(tester, find.byKey(const Key('now-toggle')));
    await pumpUntil(tester, find.text(s.addedByYou));

    // Clear → confirmation → cancel keeps them, confirm removes only the additions
    await tapVisible(tester, find.text(s.clearQueue).first);
    await pumpUntil(tester, find.text(s.clearAddedTitle));
    expect(find.text(s.clearAddedBody(2)), findsOneWidget);
    await tester.tap(find.text(s.cancel));
    await tester.pump(const Duration(milliseconds: 400));
    expect(player.queue!.addedCount, 2);
    await tapVisible(tester, find.text(s.clearQueue).first);
    await pumpUntil(tester, find.text(s.clearAddedTitle));
    await tester.tap(
      find.descendant(
        of: find.byType(DialogFrame),
        matching: find.text(s.clearQueue),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(player.queue!.addedCount, 0);
    expect(find.text(s.addedByYou), findsNothing);
    // the album continuation is kept, the current song goes on
    expect(upcoming(), ['Alpha 2', 'Alpha 3', 'Alpha 4']);
    expect(player.current.track?.title, 'Alpha 1');

    // Now playing → ⋯ → Go to album
    await tester.tap(find.byIcon(Icons.more_horiz_rounded));
    await pumpUntil(tester, find.text(s.goToAlbum));
    expect(find.text(s.goToArtist), findsOneWidget);
    await tester.tap(find.text(s.goToAlbum));
    await pumpUntil(tester, find.text('Alpha 2'));
    await tester.pump(const Duration(seconds: 1)); // Now playing slides away
    expect(find.byKey(const Key('now-toggle')), findsNothing);

    // Home → ALBUMS title → Albums screen: recently played, then pick a sort
    for (final e in find.byType(Navigator).evaluate().toList().reversed) {
      (e as StatefulElement).state is NavigatorState
          ? ((e.state as NavigatorState)..popUntil((r) => r.isFirst))
          : null;
    }
    await tester.pump(const Duration(seconds: 2));
    await tapVisible(tester, find.text(s.playlists));
    await pumpUntil(tester, find.byKey(const Key('album-grid')));
    await pumpUntil(
      tester,
      find.byKey(const Key('recent-albums')),
    ); // a listen is counted at half the song
    expect(find.byKey(const Key('recent-albums')), findsOneWidget);
    double left(String name) => tester
        .getTopLeft(
          find.descendant(
            of: find.byKey(const Key('album-grid')),
            matching: find.text(name),
          ),
        )
        .dx;
    await pumpUntil(
      tester,
      find.descendant(
        of: find.byKey(const Key('album-grid')),
        matching: find.text('Beta Album'),
      ),
    );
    expect(left('Alpha Album'), lessThan(left('Beta Album'))); // by name
    await tapVisible(tester, find.byKey(const Key('sort-artist')));
    await tester.pump(const Duration(milliseconds: 600));
    expect(left('Beta Album'), lessThan(left('Alpha Album'))); // Amy before Zed
    expect(app.settings.albumSort, AlbumSort.artist);

    // « relaunch »: what a new launch reads back from settings.json
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 1)),
    );
    final again = await tester.runAsync(
      () => AppSettings.load(File(p.join(support.path, 'settings.json'))),
    );
    expect(again!.albumSort, AlbumSort.artist);
  });
}
