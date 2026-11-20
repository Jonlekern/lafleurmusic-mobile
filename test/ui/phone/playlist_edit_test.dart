import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/demo/demo_library.dart';
import 'package:lafleurmusic/library/db.dart';
import 'package:lafleurmusic/library/models.dart';
import 'package:lafleurmusic/library/playlist_store.dart';
import 'package:lafleurmusic/sources/subsonic.dart';
import 'package:lafleurmusic/ui/phone/playlist_edit_screen.dart';
import 'package:lafleurmusic/ui/phone/playlist_screen.dart';

import '../../sources/fake_playlist_servers.dart';
import '../fonts.dart';
import '../phone_fixture.dart';

final _ocean = DemoLibrary.studio[0]; // Ocean Drive · Johnny
final _surf = DemoLibrary.studio[1]; // Lafleur Surf · LAFLEURSTUDIO
final _golden = DemoLibrary.studio[2]; // Golden Hour · Divers

class _Setup {
  _Setup(this.tester, this.f, this.store);
  final WidgetTester tester;
  final PhoneFixture f;
  final PlaylistStore store;

  Future<T> run<T>(Future<T> Function() fn) =>
      tester.runAsync(fn).then((v) => v as T);

  Future<List<String>> keys(PlaylistRef r) =>
      run(() async => [for (final (k, _) in await store.items(r).first) k]);

  Future<void> tap(Key key) async {
    await tester.tap(find.byKey(key));
    await settle(tester);
    await tester.pumpAndSettle();
    await settle(tester);
  }

  /// Opens the playlist screen of [ref] (from a button, like the Home list does).
  Future<void> open(PlaylistRef ref) async {
    final p = await run(
      () async =>
          (await f.db.watchPlaylists().first).firstWhere((l) => l.ref == ref),
    );
    _target = p;
    await tester.tap(find.text('go'));
    await settle(tester);
    await tester.pumpAndSettle();
    await settle(tester);
    await tester.pumpAndSettle();
  }
}

ServerPlaylist? _target;

final _opener = Builder(
  builder: (ctx) => Scaffold(
    body: TextButton(
      onPressed: () => openPlaylist(ctx, _target!),
      child: const Text('go'),
    ),
  ),
);

Future<_Setup> _pump(
  WidgetTester tester, {
  bool withAccounts = false,
  PlaylistStore Function(LibraryDb)? make,
  Future<void> Function(LibraryDb, dynamic)? seed,
}) async {
  late PlaylistStore store;
  final f = await pumpPhone(
    tester,
    home: _opener,
    withAccounts: withAccounts,
    playlists: (db) => store = (make ?? PlaylistStore.new)(db),
    seed: seed,
  );
  return _Setup(tester, f, store);
}

/// A phone playlist « Road Trip »: Ocean Drive, Lafleur Surf, Golden Hour.
Future<PlaylistRef> _road(_Setup s) => s.run(
  () => s.store.create(
    'Road Trip',
    songs: [_ocean.path, _surf.path, _golden.path],
  ),
);

void main() {
  setUpAll(loadFonts);

  testWidgets('no account: a phone playlist shows Ajouter · Modifier · Trier '
      'and the play button', (tester) async {
    final s = await _pump(tester);
    await s.open(await _road(s));
    expect(find.text('Ajouter'), findsOneWidget);
    expect(find.text('Modifier'), findsOneWidget);
    expect(find.text('Trier'), findsOneWidget);
    await tester.tap(find.byKey(const Key('plPlay')));
    await tester.pump();
    expect(s.f.player.calls, contains('play'));
    expect(s.f.player.lastTracks?.map((t) => t.path), [
      _ocean.path,
      _surf.path,
      _golden.path,
    ]);
  });

  testWidgets('« Ajouter »: search in your music, a touch adds the song; '
      'already there: « Ignorer » by default, « Ajouter quand même » adds it '
      'again', (tester) async {
    final s = await _pump(tester);
    final ref = await _road(s);
    await s.open(ref);
    await s.tap(const Key('plAdd'));
    expect(find.text('Chercher dans ta musique'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('addSongsSearch')), 'swim');
    await settle(tester);
    await tester.pumpAndSettle();
    final swim = DemoLibrary.studio[3];
    await s.tap(ValueKey('addSong-${swim.path}'));
    expect(await s.keys(ref), [
      _ocean.path,
      _surf.path,
      _golden.path,
      swim.path,
    ]);
    expect(find.text('Ajouté à « Road Trip »'), findsOneWidget);
    // again: the question, « Ignorer » leaves it once
    await s.tap(ValueKey('addSong-${swim.path}'));
    expect(find.text('Déjà dans « Road Trip »'), findsOneWidget);
    expect(find.text('« Night Swim » y est déjà.'), findsOneWidget);
    await s.tap(const Key('questionNo'));
    expect((await s.keys(ref)).where((k) => k == swim.path), hasLength(1));
    await s.tap(ValueKey('addSong-${swim.path}'));
    await s.tap(const Key('questionYes'));
    expect((await s.keys(ref)).where((k) => k == swim.path), hasLength(2));
  });

  testWidgets('« Modifier »: rename, remove (−), move (≡), OK writes it all; '
      'the screen shows the new name', (tester) async {
    final s = await _pump(tester);
    final ref = await _road(s);
    await s.open(ref);
    await s.tap(const Key('plEdit'));
    expect(find.text('Changer la pochette'), findsOneWidget);
    expect(find.text('Supprimer la playlist'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('editName')), 'Trip');
    // − on Lafleur Surf
    await tester.tap(find.byKey(const Key('editRemove-1')));
    await tester.pump();
    expect(find.text('Lafleur Surf'), findsNothing);
    // ≡ of Golden Hour (now the 2nd row) dragged above Ocean Drive
    final handle = find.byKey(const Key('editMove-1'));
    await tester.timedDrag(
      handle,
      const Offset(0, -90),
      const Duration(milliseconds: 500),
    );
    await tester.pumpAndSettle();
    await s.tap(const Key('editOk'));
    expect(await s.keys(ref), [_golden.path, _ocean.path]);
    expect(find.text('Trip'), findsOneWidget);
    expect(find.text('Road Trip'), findsNothing);
  });

  testWidgets('the keyboard up on the Android emulator\'s phone (Pixel 6): '
      'OK is still there and saves the new name', (tester) async {
    final s = await _pump(tester);
    tester.view.physicalSize = const Size(411, 914);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final ref = await _road(s);
    await s.open(ref);
    await s.tap(const Key('plEdit'));
    await tester.tap(find.byKey(const Key('editName')));
    // the soft keyboard takes the bottom of the screen
    tester.view.viewInsets = const FakeViewPadding(bottom: 330);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('editName')), 'Trip');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('editOk')).hitTestable(), findsOneWidget);
    await s.tap(const Key('editOk'));
    final names = await s.run(
      () async => [for (final l in await s.f.db.watchPlaylists().first) l.name],
    );
    expect(names, ['Trip']);
  });

  testWidgets('a narrow phone (320×568): Ajouter · Modifier · Trier · ▶ fit '
      'on one row, all still there and tappable', (tester) async {
    final s = await _pump(tester);
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await s.open(await _road(s));
    expect(tester.takeException(), isNull, reason: 'no overflow');
    for (final k in const ['plAdd', 'plEdit', 'plSort', 'plPlay']) {
      final b = find.byKey(Key(k));
      expect(b.hitTestable(), findsOneWidget, reason: k);
      expect(tester.getRect(b).right, lessThanOrEqualTo(320), reason: k);
    }
    await s.tap(const Key('plEdit'));
    expect(find.byKey(const Key('editOk')), findsOneWidget);
  });

  testWidgets('an empty name at OK: « Donne un nom à ta playlist. », '
      'nothing written, the screen stays', (tester) async {
    final s = await _pump(tester);
    final ref = await _road(s);
    await s.open(ref);
    await s.tap(const Key('plEdit'));
    await tester.enterText(find.byKey(const Key('editName')), '   ');
    await tester.tap(find.byKey(const Key('editRemove-0')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('editOk')));
    await settle(tester);
    await tester.pump();
    expect(find.text('Donne un nom à ta playlist.'), findsOneWidget);
    expect(find.byKey(const Key('editOk')), findsOneWidget);
    expect(await s.keys(ref), [_ocean.path, _surf.path, _golden.path]);
  });

  testWidgets('a chosen cover shows on the playlist screen', (tester) async {
    final support = Directory.systemTemp.createTempSync('covers');
    addTearDown(() => support.deleteSync(recursive: true));
    final s = await _pump(
      tester,
      make: (db) => PlaylistStore(db, supportDir: () async => support),
    );
    final ref = await _road(s);
    await s.run(() => s.store.setCover(ref, s.f.covers.values.first));
    await s.open(ref);
    expect(find.byKey(const Key('chosenCover')), findsOneWidget);
  });

  testWidgets('« Annuler » changes nothing', (tester) async {
    final s = await _pump(tester);
    final ref = await _road(s);
    await s.open(ref);
    await s.tap(const Key('plEdit'));
    await tester.enterText(find.byKey(const Key('editName')), 'Trip');
    await tester.tap(find.byKey(const Key('editRemove-0')));
    await tester.pump();
    await s.tap(const Key('editCancel'));
    expect(await s.keys(ref), [_ocean.path, _surf.path, _golden.path]);
    expect(find.text('Road Trip'), findsOneWidget);
  });

  testWidgets('cover: a photo chosen in the system picker becomes the '
      'playlist\'s cover at OK (a copy in the app folder)', (tester) async {
    final support = Directory.systemTemp.createTempSync('covers');
    addTearDown(() => support.deleteSync(recursive: true));
    final s = await _pump(
      tester,
      make: (db) => PlaylistStore(db, supportDir: () async => support),
    );
    final ref = await _road(s);
    final photo = s.f.covers.values.first;
    var asked = 0;
    final before = pickPlaylistCover;
    pickPlaylistCover = () async {
      asked++;
      return photo;
    };
    addTearDown(() => pickPlaylistCover = before);
    await s.open(ref);
    await s.tap(const Key('plEdit'));
    await tester.tap(find.byKey(const Key('editCover')));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(asked, 1);
    await s.tap(const Key('editOk'));
    final cover = await s.run(() => s.store.coverOf(ref));
    expect(cover, isNotNull);
    expect(await s.run(() => cover!.exists()), isTrue);
    expect(cover!.path, startsWith(support.path));
    expect(photo.existsSync(), isTrue); // the photo itself is never touched
  });

  testWidgets('« Supprimer la playlist »: a question first; « Annuler » keeps '
      'it; « Supprimer » deletes it and closes its screen', (tester) async {
    final s = await _pump(tester);
    final ref = await _road(s);
    await s.open(ref);
    await s.tap(const Key('plEdit'));
    await s.tap(const Key('editDelete'));
    expect(find.text('Supprimer « Road Trip » ?'), findsOneWidget);
    expect(
      find.textContaining('Ses morceaux restent dans ta musique'),
      findsOneWidget,
    );
    await s.tap(const Key('questionNo'));
    expect(await s.run(() => s.f.db.watchPlaylists().first), hasLength(1));
    await s.tap(const Key('editDelete'));
    await s.tap(const Key('questionYes'));
    expect(await s.run(() => s.f.db.watchPlaylists().first), isEmpty);
    expect(find.text('go'), findsOneWidget); // back where it was opened
    expect(find.text('Supprimer la playlist'), findsNothing);
  });

  testWidgets('« Trier » par titre / artiste / ordre d\'ajout inverse '
      'rewrites the order', (tester) async {
    final s = await _pump(tester);
    final ref = await _road(s);
    await s.open(ref);
    await s.tap(const Key('plSort'));
    expect(find.text('Trier par'), findsOneWidget);
    expect(find.text('Album'), findsOneWidget);
    await s.tap(const Key('sort-title'));
    // Golden Hour, Lafleur Surf, Ocean Drive
    expect(await s.keys(ref), [_golden.path, _surf.path, _ocean.path]);
    await s.tap(const Key('plSort'));
    await s.tap(const Key('sort-artist'));
    // Divers, Johnny, LAFLEURSTUDIO
    expect(await s.keys(ref), [_golden.path, _ocean.path, _surf.path]);
    await s.tap(const Key('plSort'));
    expect(find.text("Inverser l'ordre"), findsOneWidget);
    await s.tap(const Key('sort-reverse'));
    expect(await s.keys(ref), [_surf.path, _ocean.path, _golden.path]);
  });

  test('sortOrder: absent songs last, in their order', () {
    final items = <(String, Track?)>[
      ('x1', null),
      (_surf.path, _surf),
      ('x2', null),
      (_golden.path, _golden),
    ];
    expect(sortOrder(items, PlaylistSort.title), [3, 1, 0, 2]);
    expect(sortOrder(items, PlaylistSort.reverse), [3, 2, 1, 0]);
  });

  group('a server playlist', () {
    late FakeNavidrome nav;
    var acc = '';

    Future<_Setup> pumpServer(WidgetTester tester) async {
      nav = FakeNavidrome();
      return _pump(
        tester,
        withAccounts: true,
        make: (db) => PlaylistStore(
          db,
          sourceOf: (id) async {
            if (id != acc) throw StateError('no account $id');
            return SubsonicSource(
              accountId: id,
              base: Uri.parse('https://music.example.com'),
              user: 'johnny',
              password: 'p',
              client: nav.client(),
              salt: () => 'abc',
            );
          },
        ),
        seed: (db, accounts) async {
          final list = await (accounts as dynamic).watch().first as List;
          acc = list.first.id as String;
          await db.upsertTracks([
            for (final (id, title, artist) in [
              ('s1', 'Zebra', 'b'),
              ('s2', 'Apple', 'c'),
              ('s3', 'Mango', 'a'),
            ])
              Track(
                path: 'subsonic://$acc/$id',
                accountId: acc,
                remoteId: id,
                title: title,
                artist: artist,
                album: 'R',
                durationMs: 1000,
                hasCover: false,
                size: 1,
              ),
          ]);
          await db.replacePlaylists(acc, [
            (
              id: 'pl1',
              name: 'Road',
              paths: [
                for (final i in [1, 2, 3]) 'subsonic://$acc/s$i',
              ],
            ),
          ]);
        },
      );
    }

    testWidgets('its server lets us: the buttons; no cover choice; « Trier » '
        'asks first, then the server gets the new order', (tester) async {
      final s = await pumpServer(tester);
      await s.open(PlaylistRef.server(acc, 'pl1'));
      expect(find.text('Modifier'), findsOneWidget);
      await s.tap(const Key('plSort'));
      await s.tap(const Key('sort-title'));
      expect(find.text('Trier « Road » ?'), findsOneWidget);
      expect(
        find.text('Le nouvel ordre sera écrit sur « Navidrome ».'),
        findsOneWidget,
      );
      await s.tap(const Key('questionNo'));
      expect(nav.lists['pl1']!.songs, ['s1', 's2', 's3']);
      await s.tap(const Key('plSort'));
      await s.tap(const Key('sort-title'));
      await s.tap(const Key('questionYes'));
      expect(nav.lists['pl1']!.songs, ['s2', 's3', 's1']);
      await s.tap(const Key('plEdit'));
      expect(find.text('Changer la pochette'), findsNothing);
      expect(find.text('Supprimer la playlist'), findsOneWidget);
    });

    testWidgets('an account whose server refused a new playlist still edits '
        'its own playlists', (tester) async {
      final s = await pumpServer(tester);
      nav.readOnly = true;
      await s.run(() async {
        try {
          await s.store.create('New', accountId: acc);
        } on PlaylistWriteException {
          // refused: the account is no longer offered to create
        }
      });
      nav.readOnly = false;
      expect(await s.run(() => s.store.canWrite(acc)), isFalse);
      await s.open(PlaylistRef.server(acc, 'pl1'));
      expect(find.text('Modifier'), findsOneWidget);
      expect(find.text('Trier'), findsOneWidget);
    });

    testWidgets('« Trier » on Subsonic: the whole order in one write', (
      tester,
    ) async {
      final s = await pumpServer(tester);
      await s.open(PlaylistRef.server(acc, 'pl1'));
      nav.log.clear();
      await s.tap(const Key('plSort'));
      await s.tap(const Key('sort-title'));
      await s.tap(const Key('questionYes'));
      expect(nav.lists['pl1']!.songs, ['s2', 's3', 's1']);
      expect(
        nav.log.where((r) => r.url.path.contains('createPlaylist')),
        hasLength(1),
      );
    });

    testWidgets('another user\'s playlist (read-only): no Ajouter, Modifier, '
        'Trier — only listen', (tester) async {
      final s = await pumpServer(tester);
      nav.readonlyFlag = {'pl1'};
      await s.open(PlaylistRef.server(acc, 'pl1'));
      expect(find.text('Modifier'), findsNothing);
      expect(find.text('Ajouter'), findsNothing);
      expect(find.text('Trier'), findsNothing);
      expect(find.text('Lecture'), findsOneWidget);
    });

    testWidgets('the server refuses a change: its message, nothing changed '
        'here', (tester) async {
      final s = await pumpServer(tester);
      await s.open(PlaylistRef.server(acc, 'pl1'));
      nav.readOnly = true;
      await s.tap(const Key('plEdit'));
      await tester.tap(find.byKey(const Key('editRemove-0')));
      await tester.pump();
      await s.tap(const Key('editOk'));
      expect(
        find.text('Ce serveur ne te laisse pas modifier cette playlist.'),
        findsOneWidget,
      );
      expect(nav.lists['pl1']!.songs, ['s1', 's2', 's3']);
      // refused: the edit buttons go
      expect(find.text('Modifier'), findsNothing);
    });
  });
}
