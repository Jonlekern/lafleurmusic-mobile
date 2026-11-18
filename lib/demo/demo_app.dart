import 'dart:io';
import 'dart:ui';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../l10n/strings.dart';
import '../library/covers.dart';
import '../library/db.dart';
import '../player/equalizer.dart';
import '../player/player.dart';
import '../player/queue.dart';
import '../settings.dart';
import '../sources/accounts.dart';
import '../sources/secret_store.dart';
import '../theme/lafleur_theme.dart';
import '../ui/phone/phone_shell.dart';
import 'demo_library.dart';
import 'demo_player.dart';

/// Mode démo (debug seulement, `--dart-define=LAFLEUR_DEMO=true`) : la bibliothèque des maquettes en
/// mémoire, deux comptes factices, un lecteur muet sur « Lafleur Surf ». Rien n'est enregistré.
/// `--dart-define=LAFLEUR_DEMO_SCREEN=album|now` ouvre l'Album ou En cours au lancement (captures).
Future<Widget> demoApp() async {
  final db = LibraryDb(NativeDatabase.memory());
  await db.upsertTracks(DemoLibrary.tracks);
  final accounts = Accounts(db, _MemorySecrets());
  for (final (type, name) in [
    (AccountType.subsonic, 'Navidrome'),
    (AccountType.jellyfin, 'Jellyfin'),
  ]) {
    await accounts.add(
      type: type,
      name: name,
      base: Uri.parse('https://music.example'),
      user: 'demo',
      password: 'demo',
    );
  }
  final dir = await Directory.systemTemp.createTemp('lafleur-demo');
  final player = DemoPlayer(
    PlayerState(
      track: DemoLibrary.playing,
      position: DemoLibrary.position,
      duration: Duration(milliseconds: DemoLibrary.playing.durationMs),
      playing: true,
    ),
    PlayQueue(DemoLibrary.studio, index: 1)..enqueue([DemoLibrary.nightcall]),
  );
  const screen = String.fromEnvironment('LAFLEUR_DEMO_SCREEN');
  return AppScope(
    db: db,
    player: player,
    covers: _DemoCovers(DemoLibrary.writeCovers(dir)),
    strings: Strings.of(PlatformDispatcher.instance.locale),
    equalizer: ValueNotifier(Equalizer.named('flat')),
    settings: AppSettings(),
    saveSettings: () {},
    accounts: accounts,
    child: MaterialApp(
      title: 'LAFLEURMUSIC',
      debugShowCheckedModeBanner: false,
      theme: lafleurTheme(),
      home: AdaptiveHome(debugStart: screen.isEmpty ? null : screen),
    ),
  );
}

class _DemoCovers extends Covers {
  _DemoCovers(this.files) : super(cacheDir: Directory.systemTemp);
  final Map<String, File> files;
  @override
  Future<File?> get(String trackPath, int size) async => files[trackPath];
}

class _MemorySecrets implements SecretStore {
  final _data = <String, String>{};
  @override
  Future<String?> read(String key) async => _data[key];
  @override
  Future<void> write(String key, String value) async => _data[key] = value;
  @override
  Future<void> delete(String key) async => _data.remove(key);
}
