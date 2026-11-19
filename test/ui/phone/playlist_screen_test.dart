import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/demo/demo_offline.dart';
import 'package:lafleurmusic/library/db.dart';
import 'package:lafleurmusic/settings.dart';
import 'package:lafleurmusic/ui/phone/phone_shell.dart';

import '../fonts.dart';
import '../keep_fixture.dart';
import 'keep_screen_test.dart' show confirmRemoval, done, longPress, phoneTest;
import 'on_device_screen_test.dart' show scrollTo;

/// Les comptes de la maquette 7 (ids fixes) et leurs playlists.
Future<void> seedPlaylists(LibraryDb db) async {
  await seedKeepDemo(db);
  for (final (i, (id, name)) in [
    ('demo', 'Navidrome'),
    ('jelly', 'Jellyfin'),
  ].indexed) {
    await db
        .into(db.accountRows)
        .insert(
          AccountRowsCompanion.insert(
            id: id,
            type: 'subsonic',
            name: name,
            base: 'https://music.example',
            user: 'demo',
            position: i,
          ),
        );
  }
  await seedPlaylistDemo(db, navidrome: 'demo', jellyfin: 'jelly');
}

Future<KeepFixture> pumpPlaylists(
  WidgetTester tester, {
  AppSettings? settings,
  bool images = false,
  Widget home = const PhoneShell(),
}) => pumpKeep(
  tester,
  seed: seedPlaylists,
  addAccount: false,
  settings: settings,
  images: images,
  home: home,
);

Future<void> openSoiree(WidgetTester tester) async {
  await scrollTo(tester, find.text('Soirée'));
  await tester.tap(find.text('Soirée'));
  await done(tester);
}

/// Le nom du compte en petit dans la ligne de la playlist.
Finder tagOf(String acc, String id, String name) => find.descendant(
  of: find.byKey(ValueKey('playlist-$acc-$id')),
  matching: find.text(name),
);

void main() {
  setUpAll(loadFonts);

  group('Accueil : PLAYLISTS DU SERVEUR', () {
    phoneTest(
      'sous les albums, le compte en petit en mode Tout',
      TargetPlatform.iOS,
      (tester) async {
        await pumpPlaylists(tester);
        await scrollTo(tester, find.text('Chill du dimanche'));
        expect(find.text('PLAYLISTS DU SERVEUR'), findsOneWidget);
        final albums = tester.getTopLeft(find.text('ALBUMS')).dy;
        final section = tester.getTopLeft(find.text('PLAYLISTS DU SERVEUR')).dy;
        expect(section, greaterThan(albums));
        expect(tagOf('demo', 'soiree', 'Navidrome'), findsOneWidget);
        expect(tagOf('demo', 'running', 'Navidrome'), findsOneWidget);
        expect(tagOf('jelly', 'chill', 'Jellyfin'), findsOneWidget);
        // l'ordre : les comptes dans l'ordre de l'écran Comptes, puis celui du serveur
        final ys = [
          for (final n in ['Soirée', 'Running', 'Chill du dimanche'])
            tester.getTopLeft(find.text(n)).dy,
        ];
        expect(ys, orderedEquals([...ys]..sort()));
      },
    );

    phoneTest('mode Un compte : pas de nom de compte', TargetPlatform.iOS, (
      tester,
    ) async {
      await pumpPlaylists(
        tester,
        settings: AppSettings()
          ..displayMode = DisplayMode.one
          ..oneAccount = 'demo',
      );
      await scrollTo(tester, find.text('Running'));
      // plus le nom en petit à côté des playlists
      expect(tagOf('demo', 'running', 'Navidrome'), findsNothing);
      expect(tagOf('demo', 'soiree', 'Navidrome'), findsNothing);
    });

    phoneTest('⬇ rose sur la playlist gardée seulement', TargetPlatform.iOS, (
      tester,
    ) async {
      await pumpPlaylists(tester);
      await scrollTo(tester, find.text('Chill du dimanche'));
      Finder arrowIn(String name) => find.descendant(
        of: find.byKey(
          ValueKey(
            'playlist-${name == 'Chill du dimanche' ? 'jelly' : 'demo'}-'
            '${{'Soirée': 'soiree', 'Running': 'running', 'Chill du dimanche': 'chill'}[name]}',
          ),
        ),
        matching: find.byIcon(Icons.arrow_downward_rounded),
      );
      expect(arrowIn('Running'), findsOneWidget);
      expect(arrowIn('Soirée'), findsNothing);
      expect(arrowIn('Chill du dimanche'), findsNothing);
    });

    phoneTest(
      'appui long sur la playlist gardée → Retirer → la question → '
      'la playlist entière',
      TargetPlatform.iOS,
      (tester) async {
        final f = await pumpPlaylists(tester);
        f.downloader.playlistSongs = ['subsonic://demo/Night Drive/2'];
        await scrollTo(tester, find.text('Running'));
        await longPress(tester, find.text('Running'));
        await tester.tap(find.text('Retirer du téléphone'));
        await done(tester);
        expect(find.text('Retirer du téléphone ?'), findsOneWidget);
        await confirmRemoval(tester);
        expect(f.downloader.forgottenPlaylists, [('demo', 'running')]);
        expect(f.downloader.forgotten, isEmpty, reason: 'not song by song');
      },
    );
  });

  phoneTest(
    'playlist notée mais un morceau pas gardé (ajouté sur le serveur) : '
    'la feuille propose « Garder », pas « Retirer »',
    TargetPlatform.iOS,
    (tester) async {
      final f = await pumpPlaylists(tester);
      await tester.runAsync(
        () => f.db.removeOffline(['subsonic://demo/Night Drive/2']),
      );
      await scrollTo(tester, find.text('Running'));
      await longPress(tester, find.text('Running'));
      expect(find.text('Garder sur mon iPhone'), findsOneWidget);
      expect(find.text('Retirer du téléphone'), findsNothing);
      await tester.tap(find.text('Garder sur mon iPhone'));
      await done(tester);
      expect(f.downloader.keptPlaylists, [('demo', 'running')]);
    },
  );

  phoneTest(
    'Q13 : retirer un album depuis l\'Accueil retire sa raison « album », '
    'un morceau seul est retiré tel quel',
    TargetPlatform.iOS,
    (tester) async {
      final f = await pumpPlaylists(tester);
      await longPress(tester, find.text('Lafleur Surf').first);
      await tester.tap(find.text('Retirer du téléphone'));
      await done(tester);
      await confirmRemoval(tester);
      expect(f.downloader.forgottenOrigins, hasLength(1));
      expect(f.downloader.forgottenOrigins.single, startsWith('album:'));
    },
  );

  phoneTest('Q13 : ⬇ d\'un album le garde « album »', TargetPlatform.iOS, (
    tester,
  ) async {
    final f = await pumpPlaylists(tester);
    await scrollTo(tester, find.text('Summer Mix'));
    await tester.tap(find.text('Summer Mix'));
    await done(tester);
    await tester.tap(find.byIcon(Icons.arrow_downward_rounded));
    await done(tester);
    expect(f.downloader.origins.single.single, startsWith('album:'));
  });

  phoneTest(
    'N3 : une playlist dont tout est gardé autrement : pas de question, un mot, '
    'la playlist part quand même',
    TargetPlatform.iOS,
    (tester) async {
      final f = await pumpPlaylists(tester);
      await scrollTo(tester, find.text('Running'));
      await longPress(tester, find.text('Running'));
      await tester.tap(find.text('Retirer du téléphone'));
      await done(tester);
      expect(find.text('Retirer du téléphone ?'), findsNothing);
      expect(
        find.text('Toujours gardé par un autre album ou une playlist.'),
        findsOneWidget,
      );
      expect(f.downloader.forgottenPlaylists, [('demo', 'running')]);
    },
  );

  phoneTest(
    'N3 : un album dont tout est gardé autrement : pas de question, un mot',
    TargetPlatform.iOS,
    (tester) async {
      final f = await pumpPlaylists(tester);
      f.downloader.fromOrigin = const [];
      await longPress(tester, find.text('Lafleur Surf').first);
      await tester.tap(find.text('Retirer du téléphone'));
      await done(tester);
      expect(find.text('Retirer du téléphone ?'), findsNothing);
      expect(
        find.text('Toujours gardé par un autre album ou une playlist.'),
        findsOneWidget,
      );
      expect(f.downloader.forgottenOrigins.single, startsWith('album:'));
    },
  );

  group('écran Playlist', () {
    phoneTest(
      'un morceau seul (appui long) se retire tel quel, sans raison',
      TargetPlatform.iOS,
      (tester) async {
        final f = await pumpPlaylists(tester);
        await openSoiree(tester);
        await longPress(tester, find.text('Lafleur Surf').first);
        await tester.tap(find.text('Retirer du téléphone'));
        await done(tester);
        await confirmRemoval(tester);
        expect(f.downloader.forgotten, [
          ['subsonic://demo/Lafleur Surf/1'],
        ]);
        expect(f.downloader.forgottenOrigins, isEmpty);
      },
    );

    phoneTest(
      'PLAYLIST · compte, l\'ordre du serveur, le doublon deux fois, '
      'l\'absent grisé (Review Focus 4)',
      TargetPlatform.iOS,
      (tester) async {
        await pumpPlaylists(tester);
        await openSoiree(tester);
        expect(find.text('PLAYLIST · NAVIDROME'), findsOneWidget);
        expect(find.text('7 morceaux · 33 min'), findsOneWidget);
        expect(find.text('Ocean Drive'), findsNWidgets(2));
        expect(find.text('Johnny · Studio Lafleur'), findsNWidgets(2));
        expect(find.text('Divers · Summer Mix'), findsOneWidget);
        expect(find.text('Kavinsky · pas sur l\'iPhone'), findsOneWidget);
        await scrollTo(tester, find.text('Morceau absent'));
        expect(find.text('absent de Navidrome'), findsOneWidget);
        final ys = [
          for (final t in [
            'Lafleur Surf',
            'Nightcall',
            'Night Swim',
            'Golden Hour',
          ])
            tester.getTopLeft(find.text(t).first).dy,
        ];
        expect(ys, orderedEquals([...ys]..sort()));
      },
    );

    phoneTest(
      'Lecture joue la playlist sans l\'absent, le doublon deux fois',
      TargetPlatform.iOS,
      (tester) async {
        final f = await pumpPlaylists(tester);
        await openSoiree(tester);
        await tester.tap(find.text('Lecture'));
        await done(tester);
        expect(
          [for (final t in f.player.lastTracks!) t.title],
          [
            'Ocean Drive',
            'Lafleur Surf',
            'Nightcall',
            'Night Swim',
            'Golden Hour',
            'Ocean Drive',
          ],
        );
        expect(f.player.lastIndex, 0);
      },
    );

    phoneTest(
      'toucher le second « Ocean Drive » joue à partir de lui',
      TargetPlatform.iOS,
      (tester) async {
        final f = await pumpPlaylists(tester);
        await openSoiree(tester);
        await tester.tap(find.text('Ocean Drive').last);
        await done(tester);
        expect(f.player.lastIndex, 5);
        expect(f.player.lastTracks!.length, 6);
      },
    );

    phoneTest(
      'l\'absent ne joue rien et n\'a pas de menu',
      TargetPlatform.iOS,
      (tester) async {
        final f = await pumpPlaylists(tester);
        await openSoiree(tester);
        await scrollTo(tester, find.text('Morceau absent'));
        await tester.tap(find.text('Morceau absent'));
        await tester.longPress(find.text('Morceau absent'));
        await done(tester);
        expect(f.player.lastTracks, isNull);
        expect(find.text('Lire ensuite'), findsNothing);
      },
    );

    phoneTest('⬇ garde toute la playlist', TargetPlatform.iOS, (tester) async {
      final f = await pumpPlaylists(tester);
      await openSoiree(tester);
      await tester.tap(find.byIcon(Icons.arrow_downward_rounded));
      await done(tester);
      expect(f.downloader.keptPlaylists, [('demo', 'soiree')]);
      expect(f.downloader.kept, isEmpty, reason: 'through keepPlaylist');
    });

    phoneTest('Android : « pas sur le téléphone »', TargetPlatform.android, (
      tester,
    ) async {
      await pumpPlaylists(tester);
      await openSoiree(tester);
      expect(find.text('Kavinsky · pas sur le téléphone'), findsOneWidget);
    });
  });
}
