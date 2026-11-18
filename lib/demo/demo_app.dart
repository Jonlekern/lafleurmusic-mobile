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
import '../library/sync.dart';
import '../sources/account_service.dart';
import '../sources/accounts.dart';
import '../sources/secret_store.dart';
import '../sources/source.dart';
import '../theme/lafleur_theme.dart';
import '../ui/phone/account_form.dart';
import '../ui/phone/accounts_screen.dart';
import '../ui/phone/phone_shell.dart';
import 'demo_library.dart';
import 'demo_player.dart';

/// Mode démo (debug seulement, `--dart-define=LAFLEUR_DEMO=true`) : la bibliothèque des maquettes en
/// mémoire, deux comptes factices, un lecteur muet sur « Lafleur Surf ». Rien n'est enregistré.
/// `--dart-define=LAFLEUR_DEMO_SCREEN=album|now|accounts|account` ouvre l'Album, En cours, Réglages → Comptes
/// ou Ajouter un compte (rempli comme la maquette 2) au lancement (captures).
Future<Widget> demoApp() async {
  final db = LibraryDb(NativeDatabase.memory());
  await db.upsertTracks(DemoLibrary.tracks);
  final accounts = Accounts(db, _MemorySecrets());
  // les comptes de la maquette 2 : Navidrome répond, Jellyfin non, Plex oui
  final answers = <String, TestResult>{};
  for (final (type, name, base, headers, answer) in [
    (
      AccountType.subsonic,
      'Navidrome maison',
      'http://192.168.1.20:4533',
      const <String, String>{},
      TestResult.ok,
    ),
    (
      AccountType.jellyfin,
      'Jellyfin de Max',
      'https://jellyfin.max.example',
      const {'CF-Access-Client-Id': 'demo', 'CF-Access-Client-Secret': 'demo'},
      TestResult.unreachable,
    ),
    (
      AccountType.plex,
      'Plex',
      'https://plex.example:32400',
      const <String, String>{},
      TestResult.ok,
    ),
  ]) {
    final a = await accounts.add(
      type: type,
      name: name,
      base: Uri.parse(base),
      user: 'johnny',
      password: 'demo',
      headers: headers,
    );
    answers[a.id] = answer;
  }
  // rien ne part sur le réseau : réponses inventées, synchro vide
  final service = AccountService(
    accounts,
    db: db,
    draftSource: (_, _) => _DemoSource('draft', TestResult.ok),
    sourceOf: (id) async =>
        _DemoSource(id, answers[id] ?? TestResult.unreachable),
    sync: (_) async =>
        const SyncResult(added: 0, updated: 0, removed: 0, complete: true),
  );
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
    accountService: service,
    child: MaterialApp(
      title: 'LAFLEURMUSIC',
      debugShowCheckedModeBanner: false,
      theme: lafleurTheme(),
      home: AdaptiveHome(
        debugStart: screen.isEmpty ? null : screen,
        debugScreens: switch (screen) {
          'accounts' => () => [const AccountsScreen()],
          'account' => () => [
            const AccountsScreen(),
            const AccountFormScreen(initial: demoDraft),
          ],
          _ => null,
        },
      ),
    ),
  );
}

/// Le formulaire « Ajouter un compte » de la maquette 2.
const demoDraft = AccountDraft(
  name: 'Navidrome maison',
  address: 'http://192.168.1.20:4533',
  user: 'johnny',
  password: 'motdepas',
  headers: {'CF-Access-Client-Id': 'abc123…'},
);

class _DemoSource implements MusicSource {
  _DemoSource(this.accountId, this.result);
  @override
  final String accountId;
  final TestResult result;
  @override
  Future<TestResult> test() async => result;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
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
