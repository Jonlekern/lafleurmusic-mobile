import 'dart:async';

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/app_scope.dart';
import 'package:lafleurmusic/l10n/strings.dart';
import 'package:lafleurmusic/library/db.dart';
import 'package:lafleurmusic/library/library_view.dart';
import 'package:lafleurmusic/library/sync.dart';
import 'package:lafleurmusic/offline/device.dart';
import 'package:lafleurmusic/offline/local_folder.dart';
import 'package:lafleurmusic/player/equalizer.dart';
import 'package:lafleurmusic/player/media_resolver.dart';
import 'package:lafleurmusic/settings.dart';
import 'package:lafleurmusic/sources/account_service.dart';
import 'package:lafleurmusic/sources/accounts.dart';
import 'package:lafleurmusic/sources/plex_link.dart';
import 'package:lafleurmusic/sources/source.dart';
import 'package:lafleurmusic/theme/lafleur_theme.dart';
import 'package:lafleurmusic/ui/phone/phone_shell.dart';

import '../sources/fake_secret_store.dart';
import 'fake_player.dart';
import 'morceaux_golden_test.dart' show ReadyCovers;
import 'phone_fixture.dart';

/// Source factice : ne fait que répondre à « Tester ».
class ProbeSource implements MusicSource {
  ProbeSource(this.accountId, this.result);
  @override
  final String accountId;
  final TestResult result;
  int tests = 0;

  @override
  Future<TestResult> test() async {
    tests++;
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// Coffre lent : les lectures des en-têtes attendent [release] une fois [armed].
class SlowSecretStore extends FakeSecretStore {
  bool armed = false;
  final _gate = Completer<void>();
  void release() => _gate.complete();

  @override
  Future<String?> read(String key) async {
    if (armed && key.endsWith('.headers')) await _gate.future;
    return super.read(key);
  }
}

/// Ce que le formulaire a demandé : brouillons testés, synchros lancées, sources construites.
class AccountsFixture {
  AccountsFixture(this.db, this.accounts, this.secrets, this.service);
  final LibraryDb db;
  final Accounts accounts;
  final FakeSecretStore secrets;
  final AccountService service;

  /// Réglages de l'appli (mode d'affichage) et nombre d'enregistrements demandés.
  final settings = AppSettings();
  int saves = 0;

  /// Réponse de « Tester » pour un brouillon.
  TestResult draftResult = TestResult.ok;

  /// Réponse de test() par compte enregistré (connecté / absent).
  final results = <String, TestResult>{};

  /// Synchro : complète par défaut ; false = le serveur ne répond plus.
  bool syncComplete = true;
  final drafts = <(AccountDraft, String)>[];
  final synced = <String>[];
  final built = <String>[];

  Future<List<Account>> list(WidgetTester tester) async =>
      (await tester.runAsync(() => accounts.watch().first))!;
}

/// Un compte de la maquette 2 (adresse, utilisateur, mot de passe, en-têtes).
typedef SeedAccount = ({
  AccountType type,
  String name,
  String base,
  Map<String, String> headers,
});

const mockupAccounts = <SeedAccount>[
  (
    type: AccountType.subsonic,
    name: 'Navidrome maison',
    base: 'http://192.168.1.20:4533',
    headers: {},
  ),
  (
    type: AccountType.jellyfin,
    name: 'Jellyfin de Max',
    base: 'https://jellyfin.max.example',
    headers: {'CF-Access-Client-Id': 'abc123', 'CF-Access-Client-Secret': 'x'},
  ),
  (
    type: AccountType.plex,
    name: 'Plex',
    base: 'https://plex.example:32400',
    headers: {},
  ),
];

/// Le téléphone avec ses comptes ([seed]) et un service de comptes aux réponses choisies.
/// [home] : l'écran de départ (sinon le PhoneShell entier, premier lancement compris).
Future<AccountsFixture> pumpAccounts(
  WidgetTester tester, {
  List<SeedAccount> seed = mockupAccounts,
  Widget Function()? home,
  Map<String, TestResult> Function(List<Account>)? results,
  MediaResolver? resolver,
  FakeSecretStore? secretStore,
  bool fr = true,
  bool view = false,
  PlexLink Function(String clientId)? plexLink,
  void Function(AppSettings)?
  configure, // réglages au départ (avant le premier affichage)
  Device? device,
  LocalFolder? localFolder,
}) async {
  phoneSize(tester);
  final db = LibraryDb(
    DatabaseConnection(
      NativeDatabase.memory(),
      closeStreamsSynchronously: true,
    ),
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(db.close);
  });
  final secrets = secretStore ?? FakeSecretStore();
  final accounts = Accounts(db, secrets);
  late final AccountsFixture f;
  final service = AccountService(
    accounts,
    db: db,
    resolver: resolver,
    plexLink: plexLink,
    wait: (_) =>
        Completer<void>().future, // the 30 s follow-up sync never fires here
    draftSource: (d, password) {
      f.drafts.add((d, password));
      return ProbeSource('draft', f.draftResult);
    },
    sourceOf: (id) async {
      f.built.add(id);
      return ProbeSource(id, f.results[id] ?? TestResult.ok);
    },
    sync: (s) async {
      f.synced.add(s.accountId);
      return SyncResult(
        added: 0,
        updated: 0,
        removed: 0,
        complete: f.syncComplete,
      );
    },
  );
  f = AccountsFixture(db, accounts, secrets, service);
  final list = <Account>[];
  await tester.runAsync(() async {
    for (final a in seed) {
      list.add(
        await accounts.add(
          type: a.type,
          name: a.name,
          base: Uri.parse(a.base),
          user: 'johnny',
          password: 'secret',
          headers: a.headers,
        ),
      );
    }
  });
  configure?.call(f.settings);
  if (results != null) f.results.addAll(results(list));
  // view : les listes suivent le mode d'affichage comme dans l'appli
  final libraryView = view ? LibraryView(db, settings: f.settings) : null;
  if (libraryView != null) {
    addTearDown(() => tester.runAsync(libraryView.dispose));
  }
  await tester.pumpWidget(
    AppScope(
      db: db,
      player: FakePlayer(),
      covers: ReadyCovers(const {}),
      strings: Strings.of(Locale(fr ? 'fr' : 'en')),
      equalizer: ValueNotifier(Equalizer.named('flat')),
      settings: f.settings,
      saveSettings: () => f.saves++,
      libraryView: libraryView,
      accounts: accounts,
      accountService: service,
      device: device,
      localFolder: localFolder,
      child: MaterialApp(
        theme: lafleurTheme(),
        home: home?.call() ?? const PhoneShell(),
      ),
    ),
  );
  await settle(tester);
  return f;
}
