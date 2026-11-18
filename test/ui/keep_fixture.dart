import 'dart:io';

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/app_scope.dart';
import 'package:lafleurmusic/demo/demo_library.dart';
import 'package:lafleurmusic/demo/demo_offline.dart';
import 'package:lafleurmusic/l10n/strings.dart';
import 'package:lafleurmusic/library/db.dart';
import 'package:lafleurmusic/library/models.dart';
import 'package:lafleurmusic/player/equalizer.dart';
import 'package:lafleurmusic/player/player.dart';
import 'package:lafleurmusic/player/queue.dart';
import 'package:lafleurmusic/offline/local_folder.dart';
import 'package:lafleurmusic/settings.dart';
import 'package:lafleurmusic/sources/account_service.dart';
import 'package:lafleurmusic/sources/accounts.dart';
import 'package:lafleurmusic/theme/lafleur_theme.dart';
import 'package:lafleurmusic/ui/phone/phone_shell.dart';

import '../sources/fake_secret_store.dart';
import 'fake_player.dart';
import 'morceaux_golden_test.dart' show ReadyCovers;
import 'phone_fixture.dart';

class KeepFixture {
  KeepFixture(this.db, this.player, this.downloader);
  final LibraryDb db;
  final FakePlayer player;
  final DemoDownloader downloader;
}

/// Le téléphone sur la bibliothèque d'un serveur (maquette 2, écran 8) : Lafleur Surf gardé, les morceaux
/// de [notOnPhone] non jouables, [downloader] qui répond comme on le veut. [images] : pochettes et logo
/// décodés d'avance (images de référence).
Future<KeepFixture> pumpKeep(
  WidgetTester tester, {
  Widget home = const PhoneShell(),
  bool images = false,
  Set<String>? notOnPhone,
  DemoDownloader? downloader,
  Locale locale = const Locale('fr'),
  List<Track> extra = const [],
  Future<void> Function(LibraryDb)? seed,
  DemoDevice? device,
  LocalFolder? localFolder,
  AppSettings? settings,
  VoidCallback? saveSettings,
  AccountService Function(Accounts, LibraryDb)? makeService,
}) async {
  phoneSize(tester);
  final dir = Directory.systemTemp.createTempSync('keep');
  final files = DemoLibrary.writeCovers(
    dir,
    images: {...DemoLibrary.coverImages(), ...DemoLibrary.remoteCoverImages()},
  );
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
  if (images) {
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    final ctx = tester.element(find.byType(Scaffold));
    await tester.runAsync(() async {
      for (final file in files.values.toSet()) {
        await precacheImage(FileImage(file), ctx);
      }
      for (final a in [
        'assets/fleur-tile.png',
        'assets/logo-texte-grand.png',
      ]) {
        await precacheImage(AssetImage(a), ctx);
      }
    });
  }
  final accounts = Accounts(db, FakeSecretStore());
  await tester.runAsync(() async {
    await (seed ?? seedKeepDemo)(db);
    await db.upsertTracks(extra);
    await accounts.add(
      type: AccountType.subsonic,
      name: 'Navidrome',
      base: Uri.parse('https://music.example'),
      user: 'demo',
      password: 'demo',
    );
  });
  final service =
      makeService?.call(accounts, db) ??
      DemoAccountService(
        accounts,
        db: db,
        notOnPhone: notOnPhone ?? DemoLibrary.notOnPhonePaths.toSet(),
      );
  final fake = downloader ?? DemoDownloader();
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
      strings: Strings.of(locale),
      equalizer: ValueNotifier(Equalizer.named('flat')),
      settings: settings ?? AppSettings(),
      saveSettings: saveSettings ?? () {},
      accounts: accounts,
      accountService: service,
      downloader: fake,
      device: device,
      localFolder: localFolder,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: lafleurTheme(),
        home: home,
      ),
    ),
  );
  await settle(tester);
  return KeepFixture(db, player, fake);
}
