import 'dart:io';

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/app_scope.dart';
import 'package:lafleurmusic/demo/demo_library.dart';
import 'package:lafleurmusic/l10n/strings.dart';
import 'package:lafleurmusic/library/db.dart';
import 'package:lafleurmusic/library/playlist_store.dart';
import 'package:lafleurmusic/offline/downloader.dart' show Downloader;
import 'package:lafleurmusic/player/equalizer.dart';
import 'package:lafleurmusic/player/player.dart';
import 'package:lafleurmusic/player/queue.dart';
import 'package:lafleurmusic/settings.dart';
import 'package:lafleurmusic/sources/accounts.dart';
import 'package:lafleurmusic/theme/colors.dart';
import 'package:lafleurmusic/theme/lafleur_theme.dart';
import 'package:lafleurmusic/ui/phone/phone_shell.dart';

import '../sources/fake_secret_store.dart';
import 'fake_player.dart';
import 'morceaux_golden_test.dart' show ReadyCovers;

/// iPhone debout : 390 × 844, barre d'état 44, barre d'accueil 30 (comme la maquette 1).
void phoneSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  const pad = FakeViewPadding(top: 44, bottom: 30);
  tester.view.padding = pad;
  tester.view.viewPadding = pad;
  addTearDown(tester.view.reset);
}

/// Le réglage clair / sombre du téléphone pour ce test (remis à zéro après).
void phoneBrightness(WidgetTester tester, Brightness brightness) {
  tester.platformDispatcher.platformBrightnessTestValue = brightness;
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
}

/// L'appli comme au lancement (thème clair, thème sombre, réglage du téléphone) ; vérifie que
/// l'écran porte bien les couleurs du mode demandé (un oubli ne retombe pas en sombre muet).
Widget lafleurTestApp(Widget home) => lafleurMaterialApp(home: home);

void expectMode(WidgetTester tester, Brightness brightness) {
  final ctx = tester.element(find.byType(Navigator).first);
  expect(
    Theme.of(ctx).extension<LafleurColors>(),
    brightness == Brightness.light ? LafleurColors.light : LafleurColors.dark,
    reason: 'le thème du test ne porte pas les couleurs du mode $brightness',
  );
}

/// Le même iPhone couché : 844 × 390, encoche à gauche, barre d'accueil en bas.
void landscapeSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(844, 390);
  tester.view.devicePixelRatio = 1;
  const pad = FakeViewPadding(left: 47, right: 47, bottom: 21);
  tester.view.padding = pad;
  tester.view.viewPadding = pad;
  addTearDown(tester.view.reset);
}

class PhoneFixture {
  PhoneFixture(this.db, this.player, this.covers);
  final LibraryDb db;
  final FakePlayer player;
  final Map<String, File> covers;
}

/// Laisse la base répondre (ses flux passent hors de l'horloge simulée).
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
}

/// Le téléphone sur la bibliothèque de la maquette : Lafleur Surf en cours, Nightcall ajouté à la file,
/// deux comptes (Navidrome, Jellyfin). [images] : pochettes et logo décodés d'avance (images de référence).
Future<PhoneFixture> pumpPhone(
  WidgetTester tester, {
  bool images = false,
  Widget home = const PhoneShell(),
  ValueNotifier<bool>? classicMode,
  Downloader? downloader,
  bool withAccounts = true,
  PlaylistStore Function(LibraryDb db)? playlists,
  Future<void> Function(LibraryDb db, Accounts accounts)? seed,
  Brightness brightness = Brightness.dark,
}) async {
  phoneSize(tester);
  phoneBrightness(tester, brightness);
  final dir = Directory.systemTemp.createTempSync('phone');
  final files = DemoLibrary.writeCovers(dir);
  final db = LibraryDb(
    DatabaseConnection(
      NativeDatabase.memory(),
      closeStreamsSynchronously: true,
    ),
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(db.close);
    dir.deleteSync(recursive: true);
  });
  if (images) await _precache(tester, files);
  final accounts = Accounts(db, FakeSecretStore());
  await tester.runAsync(() async {
    await db.upsertTracks(DemoLibrary.tracks);
    for (final (type, name)
        in withAccounts
            ? [
                (AccountType.subsonic, 'Navidrome'),
                (AccountType.jellyfin, 'Jellyfin'),
              ]
            : const <(AccountType, String)>[]) {
      await accounts.add(
        type: type,
        name: name,
        base: Uri.parse('https://music.example'),
        user: 'demo',
        password: 'demo',
      );
    }
    await seed?.call(db, accounts);
  });
  final player = FakePlayer()
    ..queue = (PlayQueue(DemoLibrary.studio, index: 1)
      ..enqueue([DemoLibrary.nightcall]))
    ..current = PlayerState(
      track: DemoLibrary.playing,
      position: DemoLibrary.position,
      duration: Duration(milliseconds: DemoLibrary.playing.durationMs),
      playing: true,
    );
  await tester.pumpWidget(
    AppScope(
      db: db,
      player: player,
      covers: ReadyCovers(files),
      strings: Strings.of(const Locale('fr')),
      equalizer: ValueNotifier(Equalizer.named('flat')),
      classicMode: classicMode,
      settings: AppSettings(),
      saveSettings: () {},
      accounts: accounts,
      playlists: playlists?.call(db),
      downloader: downloader,
      child: lafleurTestApp(home),
    ),
  );
  await settle(tester);
  expectMode(tester, brightness);
  return PhoneFixture(db, player, files);
}

/// Les images (pochettes, logo, fleur) se décodent hors de l'horloge simulée : avant que l'écran les demande.
Future<void> _precache(WidgetTester tester, Map<String, File> covers) async {
  await tester.pumpWidget(const MaterialApp(home: Scaffold()));
  final ctx = tester.element(find.byType(Scaffold));
  await tester.runAsync(() async {
    for (final file in covers.values.toSet()) {
      await precacheImage(FileImage(file), ctx);
    }
    for (final a in [
      'assets/fleur-tile.png',
      'assets/logo-texte-grand.png',
      'assets/logo-texte-grand-noir.png',
    ]) {
      await precacheImage(AssetImage(a), ctx);
    }
  });
}
