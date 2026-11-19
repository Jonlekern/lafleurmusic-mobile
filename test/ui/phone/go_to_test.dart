import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/demo/demo_library.dart';
import 'package:lafleurmusic/library/merge.dart';
import 'package:lafleurmusic/library/models.dart';
import 'package:lafleurmusic/player/player.dart';
import 'package:lafleurmusic/ui/phone/album_screen.dart';
import 'package:lafleurmusic/ui/phone/mini_player.dart';
import 'package:lafleurmusic/ui/phone/now_screen.dart';
import 'package:lafleurmusic/ui/phone/phone_shell.dart';

import '../fonts.dart';
import '../keep_fixture.dart';
import '../phone_fixture.dart';
import 'keep_screen_test.dart' show done, phoneTest;

Track _track({
  String album = 'Studio Lafleur',
  String artist = 'LAFLEURSTUDIO',
  String albumArtist = '',
  String accountId = 'local',
  String? group,
}) => Track(
  path: accountId == 'local' ? '/m/x.flac' : 'subsonic://$accountId/x',
  accountId: accountId,
  albumArtist: albumArtist,
  title: 'Lafleur Surf',
  artist: artist,
  album: album,
  durationMs: 245000,
  hasCover: true,
  size: 1,
  albumGroup: group,
);

/// Ouvre En cours sur [t], puis le menu ⋯.
Future<PhoneFixture> openMenu(WidgetTester tester, Track t) async {
  final f = await pumpPhone(tester);
  f.player.show(
    PlayerState(
      track: t,
      duration: Duration(milliseconds: t.durationMs),
      playing: true,
    ),
  );
  await done(tester);
  await tester.tap(find.byType(MiniPlayer));
  await done(tester);
  await tester.tap(find.byIcon(Icons.more_horiz_rounded));
  await done(tester);
  return f;
}

Object? argsOf(WidgetTester tester, Type screen) =>
    ModalRoute.of(tester.element(find.byType(screen)))!.settings.arguments;

void main() {
  setUpAll(loadFonts);

  phoneTest(
    'le menu ⋯ commence par Aller à l’album et Aller à l’artiste',
    TargetPlatform.iOS,
    (tester) async {
      await openMenu(tester, DemoLibrary.playing);
      final y = [
        for (final l in [
          "Aller à l'album",
          "Aller à l'artiste",
          'Lire ensuite',
          'Ajouter à la file',
        ])
          tester.getTopLeft(find.text(l)).dy,
      ];
      expect(y, orderedEquals([...y]..sort()));
    },
  );

  phoneTest(
    'Aller à l’album ouvre l’album et ferme En cours',
    TargetPlatform.iOS,
    (tester) async {
      await openMenu(tester, DemoLibrary.playing);
      await tester.tap(find.text("Aller à l'album"));
      await done(tester);
      expect(find.byType(NowScreen), findsNothing);
      expect(find.byType(AlbumScreen), findsOneWidget);
      expect(argsOf(tester, AlbumScreen), albumKeyOf(DemoLibrary.playing));
      expect(find.text('Studio Lafleur'), findsWidgets);
    },
  );

  phoneTest(
    'Aller à l’artiste ouvre la page de l’artiste',
    TargetPlatform.iOS,
    (tester) async {
      await openMenu(tester, DemoLibrary.playing);
      await tester.tap(find.text("Aller à l'artiste"));
      await done(tester);
      expect(find.byType(NowScreen), findsNothing);
      final a = tester.widget<AlbumScreen>(find.byType(AlbumScreen));
      expect(a.artist, 'LAFLEURSTUDIO');
      expect(argsOf(tester, AlbumScreen), 'LAFLEURSTUDIO');
    },
  );

  phoneTest(
    'morceau du compte B : l’album fusionné, celui de A',
    TargetPlatform.iOS,
    (tester) async {
      final a = _track(accountId: 'a', albumArtist: 'LAFLEURSTUDIO');
      final b = _track(
        accountId: 'b',
        albumArtist: 'LAFLEURSTUDIO',
        group: albumMergeKey(a),
      );
      await openMenu(tester, b);
      await tester.tap(find.text("Aller à l'album"));
      await done(tester);
      expect(argsOf(tester, AlbumScreen), albumMergeKey(a));
    },
  );

  phoneTest(
    'fichier local sans album : pas de « Aller à l’album »',
    TargetPlatform.iOS,
    (tester) async {
      await openMenu(tester, _track(album: ''));
      expect(find.text("Aller à l'album"), findsNothing);
      expect(find.text("Aller à l'artiste"), findsOneWidget);
      expect(find.text('Lire ensuite'), findsOneWidget);
    },
  );

  phoneTest('sans artiste : pas de « Aller à l’artiste »', TargetPlatform.iOS, (
    tester,
  ) async {
    await openMenu(tester, _track(artist: ''));
    expect(find.text("Aller à l'artiste"), findsNothing);
    expect(find.text("Aller à l'album"), findsOneWidget);
  });

  phoneTest(
    'sans aucun compte : fichiers locaux seulement',
    TargetPlatform.iOS,
    (tester) async {
      await pumpKeep(
        tester,
        addAccount: false,
        seed: (db) => db.upsertTracks(DemoLibrary.studio),
        home: const PhoneShell(debugStart: 'now'),
      );
      await done(tester);
      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      await done(tester);
      await tester.tap(find.text("Aller à l'album"));
      await done(tester);
      expect(find.byType(NowScreen), findsNothing);
      expect(argsOf(tester, AlbumScreen), albumKeyOf(DemoLibrary.playing));
    },
  );

  phoneTest('en anglais : Go to album / Go to artist', TargetPlatform.iOS, (
    tester,
  ) async {
    await pumpKeep(
      tester,
      locale: const Locale('en'),
      home: const PhoneShell(debugStart: 'now'),
    );
    await done(tester);
    await tester.tap(find.byIcon(Icons.more_horiz_rounded));
    await done(tester);
    expect(find.text('Go to album'), findsOneWidget);
    expect(find.text('Go to artist'), findsOneWidget);
  });
}
