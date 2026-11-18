import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart' show MpvAudioKit;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app_scope.dart';
import 'demo/demo_app.dart';
import 'l10n/strings.dart';
import 'library/covers.dart';
import 'library/db.dart';
import 'library/play_counter.dart';
import 'offline/device.dart';
import 'offline/local_folder.dart';
import 'player/equalizer.dart';
import 'player/loudness.dart';
import 'player/media_resolver.dart';
import 'player/player.dart';
import 'settings.dart';
import 'sources/account_service.dart';
import 'sources/accounts.dart';
import 'sources/secret_store.dart';
import 'tags/tag_reader.dart';
import 'theme/lafleur_theme.dart';
import 'ui/phone/phone_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // plan 1 : téléphone debout seulement (le Cover Flow couché viendra plus tard)
  if (isMobilePlatform(defaultTargetPlatform)) {
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }
  // --dart-define=LAFLEUR_DEMO=true : bibliothèque inventée des maquettes, sans serveur ni son (debug seulement)
  if (kDebugMode && const bool.fromEnvironment('LAFLEUR_DEMO')) {
    runApp(await demoApp());
    return;
  }
  MpvAudioKit.ensureInitialized();
  // LAFLEURMUSIC_SUPPORT_DIR : dossier de bibliothèque à part, pour essayer une copie sans toucher à la vraie
  final override = Platform.environment['LAFLEURMUSIC_SUPPORT_DIR'];
  final support = override != null && override.isNotEmpty
      ? Directory(override)
      : await getApplicationSupportDirectory();
  runApp(await buildLafleurApp(support: support, secrets: SecureSecretStore()));
}

/// L'appli entière (base, comptes, lecteur…) rangée dans [support], secrets dans [secrets].
/// L'essai de bout en bout (integration_test/app_test.dart) la monte avec un dossier et un coffre à lui.
Future<LafleurApp> buildLafleurApp({
  required Directory support,
  required SecretStore secrets,
}) async {
  // réglages (égaliseur) : rechargés, appliqués tout de suite, enregistrés à chaque changement
  final settingsFile = File(p.join(support.path, 'settings.json'));
  final settings = await AppSettings.load(settingsFile);
  final db = LibraryDb(
    NativeDatabase.createInBackground(
      File(p.join(support.path, 'library.sqlite')),
    ),
  );
  // morceaux du serveur : flux et pochettes avec les en-têtes du compte (une source par compte)
  final accounts = Accounts(db, secrets);
  // dossier des copies gardées : un morceau qui en a une se lit depuis son fichier
  final device = ChannelDevice(
    settings: settings,
    saveSettings: () => settings.save(settingsFile),
  );
  final keptCopy = keptFile(db, device.musicRoot);
  final resolver = MediaResolver(
    accounts.source,
    localCopy: keptCopy,
    localPath: device.absolutePath,
  );
  final covers = Covers(
    cacheDir: Directory(p.join(support.path, 'covers')),
    remote: remoteCovers(resolver, db.trackByPath),
    remoteKey: remoteCoverKey(db.trackByPath), // une pochette par album
    absolute: device.absolutePath,
  );
  // tester, enregistrer, synchroniser : les mêmes comptes et le même resolver que le lecteur
  final accountService = AccountService(
    accounts,
    db: db,
    resolver: resolver,
    forgetCovers: covers.forgetAccount, // compte retiré : ses pochettes aussi
    device: device, // …mais ses copies gardées restent, en morceaux locaux
  );
  await accountService.watchOffline();
  // fichiers posés à la main dans le dossier : relus au lancement, au retour au premier plan
  // et quand le dossier change (déplacement ou nouveau choix : refreshRoot prévient)
  final localFolder = LocalFolder(
    db: db,
    device: device,
    reader: TagLibReader(),
  );
  String? scannedRoot = (await device.musicRoot()).path; // le lancement relit déjà
  accountService.addListener(() async {
    final path = (await device.musicRoot()).path;
    if (path == scannedRoot) return;
    scannedRoot = path;
    unawaited(localFolder.rescan());
  });
  final player = LafleurPlayer(resolver: resolver)
    // écran verrouillé : la pochette du serveur en octets, jamais une URL
    // serveur perdu : on saute aux morceaux gardés
    ..playable = accountService.playableNow
    ..artworkOf = (t) async => (await covers.get(t.path, 600))?.readAsBytes();
  await player.setEqualizer(settings.equalizer);
  await player.setCrossfade(
    settings.crossfade ? settings.crossfadeSeconds : null,
  );
  final equalizer = ValueNotifier<Equalizer>(settings.equalizer);
  final applyEq = Latest();
  equalizer.addListener(() {
    applyEq.run(() => player.setEqualizer(equalizer.value));
    settings.equalizer = equalizer.value;
    settings.save(settingsFile);
  });
  // vue Artistes (grille ou liste) : retenue
  final artistGrid = ValueNotifier<bool>(settings.artistGrid);
  artistGrid.addListener(() {
    settings.artistGrid = artistGrid.value;
    settings.save(settingsFile);
  });
  // Volume égal : mesures gardées dans la base, allumé si on l'avait laissé allumé
  final loudness = LoudnessService(
    db,
    player,
    copyOf: keptCopy,
    absolute: device.absolutePath,
  )..enabled = settings.equalVolume;
  player.gainOf =
      loudness.gainOf; // le 2e lecteur du fondu démarre au bon niveau
  return LafleurApp(
    db: db,
    loudness: loudness,
    covers: covers,
    resolver: resolver,
    accounts: accounts,
    accountService: accountService,
    localFolder: localFolder,
    player: player,
    equalizer: equalizer,
    artistGrid: artistGrid,
    settings: settings,
    saveSettings: () => settings.save(settingsFile),
    strings: Strings.of(PlatformDispatcher.instance.locale),
  );
}

class LafleurApp extends StatefulWidget {
  const LafleurApp({
    super.key,
    required this.db,
    required this.covers,
    required this.player,
    required this.strings,
    required this.equalizer,
    required this.artistGrid,
    required this.settings,
    required this.saveSettings,
    required this.loudness,
    required this.resolver,
    required this.accounts,
    required this.accountService,
    required this.localFolder,
  });
  final LoudnessService loudness;
  final MediaResolver resolver;
  // le même pour le lecteur (MediaResolver) et les écrans
  final Accounts accounts;
  final AccountService accountService;
  final LocalFolder localFolder;
  final AppSettings settings;
  final VoidCallback saveSettings;
  final ValueNotifier<bool> artistGrid;
  final LibraryDb db;
  final Covers covers;
  final LafleurPlayer player;
  final Strings strings;
  final ValueNotifier<Equalizer> equalizer;

  @override
  State<LafleurApp> createState() => _LafleurAppState();
}

class _LafleurAppState extends State<LafleurApp> with WidgetsBindingObserver {
  late final PlayCounter _plays = PlayCounter(
    widget.player.state,
    widget.db,
    sourceOf:
        widget.resolver.source, // écoute d'un morceau du serveur → scrobble
  ); // Top 100

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(widget.localFolder.rescan());
    // au lancement : la bibliothèque des serveurs est remise à jour en arrière-plan
    unawaited(widget.accountService.syncAll());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(widget.localFolder.rescan());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _plays.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppScope(
    db: widget.db,
    player: widget.player,
    covers: widget.covers,
    strings: widget.strings,
    equalizer: widget.equalizer,
    artistGrid: widget.artistGrid,
    settings: widget.settings,
    saveSettings: widget.saveSettings,
    loudness: widget.loudness,
    accounts: widget.accounts,
    accountService: widget.accountService,
    child: MaterialApp(
      title: 'LAFLEURMUSIC',
      debugShowCheckedModeBanner: false,
      theme: lafleurTheme(),
      home: const AdaptiveHome(), // Android, iOS : téléphone ; sinon les colonnes du Mac
    ),
  );
}
