import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/demo/demo_library.dart';
import 'package:lafleurmusic/library/db.dart';
import 'package:lafleurmusic/library/models.dart';
import 'package:lafleurmusic/library/playlist_store.dart';
import 'package:lafleurmusic/sources/subsonic.dart';
import 'package:lafleurmusic/ui/phone/add_to_playlist_sheet.dart';
import 'package:lafleurmusic/ui/phone/now_screen.dart';

import '../../sources/fake_playlist_servers.dart';
import '../fonts.dart';
import '../phone_fixture.dart';

final _surf =
    DemoLibrary.playing; // Lafleur Surf, the song playing in the fixture
final _golden = DemoLibrary.studio[2];
final _swim = DemoLibrary.studio[3];

Widget _opener(List<Track> tracks) => Builder(
  builder: (ctx) => Scaffold(
    body: TextButton(
      onPressed: () => showAddToPlaylist(ctx, tracks),
      child: const Text('go'),
    ),
  ),
);

class _Setup {
  _Setup(this.tester, this.f, this.store);
  final WidgetTester tester;
  final PhoneFixture f;
  final PlaylistStore store;

  Future<T> run<T>(Future<T> Function() fn) =>
      tester.runAsync(fn).then((v) => v as T);

  Future<List<String>> keys(PlaylistRef r) =>
      run(() async => [for (final (k, _) in await store.items(r).first) k]);

  Future<void> tapKey(String key) async {
    await tester.tap(find.byKey(Key(key)));
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 400));
  }
}

Future<_Setup> _pump(
  WidgetTester tester, {
  required Widget home,
  bool withAccounts = true,
  PlaylistStore Function(LibraryDb)? make,
  Future<void> Function(LibraryDb, dynamic)? seed,
}) async {
  late PlaylistStore store;
  final f = await pumpPhone(
    tester,
    home: home,
    withAccounts: withAccounts,
    playlists: (db) => store = (make ?? PlaylistStore.new)(db),
    seed: seed,
  );
  return _Setup(tester, f, store);
}

void main() {
  setUpAll(loadFonts);

  testWidgets('no account at all: « + » in the player, a new playlist on the '
      'phone, no « Où la ranger », the bubble', (tester) async {
    final s = await _pump(tester, home: const NowScreen(), withAccounts: false);
    await tester.tap(find.byKey(const Key('nowPlus')));
    await settle(tester);
    await tester.pumpAndSettle();
    expect(find.text('Ajouter à une playlist'), findsOneWidget);
    expect(find.text('Chercher une playlist'), findsOneWidget);
    await tester.tap(find.byKey(const Key('addNew')));
    await tester.pumpAndSettle();
    expect(find.text('Donne un nom à ta playlist'), findsOneWidget);
    expect(find.text('Où la ranger :'), findsNothing);
    await tester.enterText(find.byKey(const Key('newPlaylistName')), 'Soirée');
    await tester.pump();
    await s.tapKey('newPlaylistCreate');
    await tester.pumpAndSettle();
    // back on the list: the new playlist, ticked
    expect(find.text('Soirée'), findsOneWidget);
    expect(find.byKey(const Key('checked')), findsOneWidget);
    await s.tapKey('addOk');
    await tester.pumpAndSettle();
    final lists = await s.run(() => s.f.db.watchPlaylists().first);
    expect(lists.map((p) => p.name), ['Soirée']);
    expect(await s.keys(lists.single.ref), [_surf.path]);
    expect(find.byKey(const Key('playlistToast')), findsOneWidget);
    expect(find.text('Ajouté à 1 playlist'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets(
    'tick two playlists: both get the song, « Ajouté à 2 playlists »',
    (tester) async {
      late PlaylistRef a, b;
      final s = await _pump(
        tester,
        home: _opener([_golden]),
        withAccounts: false,
      );
      await s.run(() async {
        a = await s.store.create('Road Trip');
        b = await s.store.create('Calme');
        await s.store.create('Sport');
      });
      await tester.tap(find.text('go'));
      await settle(tester);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(Key('pl-phone/${(a as PhonePlaylistRef).id}')),
      );
      await tester.tap(
        find.byKey(Key('pl-phone/${(b as PhonePlaylistRef).id}')),
      );
      await tester.pump();
      expect(find.byKey(const Key('checked')), findsNWidgets(2));
      await s.tapKey('addOk');
      await tester.pumpAndSettle();
      expect(await s.keys(a), [_golden.path]);
      expect(await s.keys(b), [_golden.path]);
      expect(find.text('Ajouté à 2 playlists'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    },
  );

  testWidgets('review focus 1: one song to 3 playlists, one has it: one '
      'question, for that playlist only; « Ignorer » is the default', (
    tester,
  ) async {
    late PlaylistRef a, b, c;
    final s = await _pump(
      tester,
      home: _opener([_golden]),
      withAccounts: false,
    );
    await s.run(() async {
      a = await s.store.create('Road Trip');
      b = await s.store.create('Calme');
      c = await s.store.create('Sport');
      await s.store.add(b, [_golden.path]);
    });
    await tester.tap(find.text('go'));
    await settle(tester);
    await tester.pumpAndSettle();
    for (final r in [a, b, c]) {
      await tester.tap(
        find.byKey(Key('pl-phone/${(r as PhonePlaylistRef).id}')),
      );
    }
    await tester.pump();
    await s.tapKey('addOk');
    await tester.pumpAndSettle();
    expect(find.text('Déjà dans « Calme »'), findsOneWidget);
    expect(find.text('Déjà dans « Road Trip »'), findsNothing);
    expect(find.text('Déjà dans « Sport »'), findsNothing);
    expect(find.text('« Golden Hour » y est déjà.'), findsOneWidget);
    await tester.tap(find.text('Ignorer'));
    await settle(tester);
    await tester.pumpAndSettle();
    expect(await s.keys(a), [_golden.path]);
    expect(await s.keys(b), [_golden.path]); // not twice
    expect(await s.keys(c), [_golden.path]);
    expect(find.text('Ajouté à 2 playlists'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('« Ajouter quand même » puts the song twice', (tester) async {
    late PlaylistRef b;
    final s = await _pump(
      tester,
      home: _opener([_golden]),
      withAccounts: false,
    );
    await s.run(() async {
      b = await s.store.create('Calme');
      await s.store.add(b, [_golden.path]);
    });
    await tester.tap(find.text('go'));
    await settle(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('pl-phone/${(b as PhonePlaylistRef).id}')));
    await tester.pump();
    await s.tapKey('addOk');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ajouter quand même'));
    await settle(tester);
    await tester.pumpAndSettle();
    expect(await s.keys(b), [_golden.path, _golden.path]);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('several songs: « 2 morceaux sur 3 sont déjà dedans »; Ignorer '
      'adds only the new one', (tester) async {
    late PlaylistRef b;
    final s = await _pump(
      tester,
      home: _opener([_surf, _golden, _swim]),
      withAccounts: false,
    );
    await s.run(() async {
      b = await s.store.create('Calme');
      await s.store.add(b, [_surf.path, _swim.path]);
    });
    await tester.tap(find.text('go'));
    await settle(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('pl-phone/${(b as PhonePlaylistRef).id}')));
    await tester.pump();
    await s.tapKey('addOk');
    await tester.pumpAndSettle();
    expect(find.text('2 morceaux sur 3 sont déjà dedans'), findsOneWidget);
    await tester.tap(find.text('Ignorer'));
    await settle(tester);
    await tester.pumpAndSettle();
    expect(await s.keys(b), [_surf.path, _swim.path, _golden.path]);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets(
    'search narrows the list; OK does nothing until a box is ticked',
    (tester) async {
      final s = await _pump(
        tester,
        home: _opener([_golden]),
        withAccounts: false,
      );
      await s.run(() async {
        await s.store.create('Road Trip');
        await s.store.create('Calme');
      });
      await tester.tap(find.text('go'));
      await settle(tester);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('addSearch')), 'cal');
      await tester.pump();
      expect(find.text('Calme'), findsOneWidget);
      expect(find.text('Road Trip'), findsNothing);
      await tester.tap(find.byKey(const Key('addOk')));
      await tester.pumpAndSettle();
      expect(find.text('Ajouter à une playlist'), findsOneWidget); // still here
      await tester.tap(find.byKey(const Key('addCancel')));
      await tester.pumpAndSettle();
      expect(find.text('Ajouter à une playlist'), findsNothing);
    },
  );

  testWidgets('a new playlist then « Annuler »: nothing is made', (
    tester,
  ) async {
    final s = await _pump(
      tester,
      home: _opener([_golden]),
      withAccounts: false,
    );
    await tester.tap(find.text('go'));
    await settle(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('addNew')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('newPlaylistName')), 'Soirée');
    await tester.pump();
    await s.tapKey('newPlaylistCreate');
    await tester.pumpAndSettle();
    expect(find.text('Soirée'), findsOneWidget); // the draft, ticked
    await tester.tap(find.byKey(const Key('addCancel')));
    await tester.pumpAndSettle();
    expect(await s.run(() => s.f.db.watchPlaylists().first), isEmpty);
    expect(find.byKey(const Key('playlistToast')), findsNothing);
  });

  group('with a server', () {
    late FakeNavidrome nav;
    var acc = '';
    Future<_Setup> pumpServer(
      WidgetTester tester,
      List<Track> Function() tracks,
    ) async {
      nav = FakeNavidrome()..lists['pl2'] = (name: 'Others', songs: <String>[]);
      late final _Setup s;
      s = await _pump(
        tester,
        home: Builder(builder: (ctx) => _opener(tracks())),
        make: (db) => PlaylistStore(
          db,
          sourceOf: (id) async {
            if (id != acc) throw StateError('no account $id');
            return SubsonicSource(
              accountId: id,
              base: Uri.parse('https://music.example.com'),
              user: 'u',
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
            Track(
              path: 'subsonic://$acc/s1',
              accountId: acc,
              remoteId: 's1',
              title: 'Remote song',
              artist: 'x',
              album: 'R',
              durationMs: 1000,
              hasCover: false,
              size: 1,
            ),
          ]);
          await db.replacePlaylists(acc, [
            (id: 'pl1', name: 'Road', paths: ['subsonic://$acc/s1']),
            (id: 'pl2', name: 'Others', paths: <String>[]),
          ]);
        },
      );
      return s;
    }

    Track song() => Track(
      path: 'subsonic://$acc/s1',
      accountId: acc,
      remoteId: 's1',
      title: 'Remote song',
      artist: 'x',
      album: 'R',
      durationMs: 1000,
      hasCover: false,
      size: 1,
    );

    testWidgets('« Où la ranger » offers the phone and the accounts that can '
        'write; a new playlist is made on the chosen server', (tester) async {
      final s = await pumpServer(tester, () => [_surf]);
      await tester.tap(find.text('go'));
      await settle(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('addNew')));
      await tester.pumpAndSettle();
      await settle(tester);
      expect(find.text('Où la ranger :'), findsOneWidget);
      expect(find.byKey(const Key('where-phone')), findsOneWidget);
      expect(find.byKey(Key('where-$acc')), findsOneWidget);
      // the Jellyfin account has no writer in this setup: not offered
      expect(find.text('Jellyfin'), findsNothing);
      await tester.enterText(
        find.byKey(const Key('newPlaylistName')),
        'Soirée',
      );
      await tester.pump();
      await tester.tap(find.byKey(Key('where-$acc')));
      await tester.pump();
      await s.tapKey('newPlaylistCreate');
      await tester.pumpAndSettle();
      expect(find.textContaining('nouvelle'), findsOneWidget);
      await s.tapKey('addOk');
      await tester.pumpAndSettle();
      expect(nav.lists.values.map((l) => l.name), contains('Soirée'));
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('the server refuses: its message, the screen stays, nothing '
        'is lost', (tester) async {
      final s = await pumpServer(tester, () => [song()]);
      nav.readOnly = true;
      await tester.tap(find.text('go'));
      await settle(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('pl-$acc/pl2')));
      await tester.pump();
      await s.tapKey('addOk');
      await tester.pumpAndSettle();
      expect(
        find.text('Ce serveur ne te laisse pas modifier cette playlist.'),
        findsOneWidget,
      );
      expect(find.text('Ajouter à une playlist'), findsOneWidget);
      // a playlist the server refused is no longer offered
      expect(find.byKey(Key('pl-$acc/pl2')), findsNothing);
    });

    testWidgets('a duplicate on a server playlist asks once (a twin counts)', (
      tester,
    ) async {
      final s = await pumpServer(tester, () => [song()]);
      await tester.tap(find.text('go'));
      await settle(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('pl-$acc/pl1')));
      await tester.tap(find.byKey(Key('pl-$acc/pl2')));
      await tester.pump();
      await s.tapKey('addOk');
      await tester.pumpAndSettle();
      expect(find.text('Déjà dans « Road »'), findsOneWidget);
      await tester.tap(find.text('Ignorer'));
      await settle(tester);
      await tester.pumpAndSettle();
      expect(nav.lists['pl1']!.songs, ['s1', 's2', 's3']); // not twice
      expect(nav.lists['pl2']!.songs, ['s1']);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('a new server playlist refused while a phone playlist gets the '
        'song: the message, the draft stays; OK again makes it; the bubble '
        'counts both rounds', (tester) async {
      final s = await pumpServer(tester, () => [song()]);
      final sport = await s.run(() => s.store.create('Sport'));
      await tester.tap(find.text('go'));
      await settle(tester);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(Key('pl-phone/${(sport as PhonePlaylistRef).id}')),
      );
      await tester.tap(find.byKey(const Key('addNew')));
      await tester.pumpAndSettle();
      await settle(tester);
      await tester.enterText(
        find.byKey(const Key('newPlaylistName')),
        'Soirée',
      );
      await tester.pump();
      await tester.tap(find.byKey(Key('where-$acc')));
      await tester.pump();
      await s.tapKey('newPlaylistCreate');
      await tester.pumpAndSettle();
      nav.readOnly = true; // the server refuses to create
      await s.tapKey('addOk');
      await tester.pumpAndSettle();
      expect(
        find.text('Ce serveur ne te laisse pas modifier cette playlist.'),
        findsOneWidget,
      );
      expect(await s.keys(sport), [song().path]);
      expect(nav.lists.values.map((l) => l.name), isNot(contains('Soirée')));
      expect(find.textContaining('nouvelle'), findsOneWidget); // still there
      expect(find.text('Ajouté à 1 playlist'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      nav.readOnly = false;
      await s.tapKey('addOk');
      await tester.pumpAndSettle();
      expect(find.text('Ajouter à une playlist'), findsNothing);
      expect(nav.lists.values.map((l) => l.name), contains('Soirée'));
      expect(await s.keys(sport), [song().path]); // not added twice
      expect(find.text('Ajouté à 2 playlists'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });
  });
}
