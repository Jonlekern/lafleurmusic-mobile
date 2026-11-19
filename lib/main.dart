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
import 'library/library_view.dart';
import 'library/play_counter.dart';
import 'offline/device.dart';
import 'offline/downloader.dart';
import 'offline/home_state.dart';
import 'offline/local_folder.dart';
import 'offline/top_keeper.dart';
import 'player/equalizer.dart';
import 'player/loudness.dart';
import 'player/media_resolver.dart';
import 'player/player.dart';
import 'settings.dart';
import 'sources/account_service.dart';
import 'sources/accounts.dart';
import 'sources/plex_link.dart' show PlexLink;
import 'sources/secret_store.dart';
import 'tags/tag_reader.dart';
import 'theme/lafleur_theme.dart';
import 'ui/phone/phone_shell.dart';
import 'ui/tablet.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // téléphone : debout, ou couché des deux côtés (Cover Flow) ; En cours le remet debout le temps qu'on y est.
  // Tablette : les quatre orientations
  if (isMobilePlatform(defaultTargetPlatform)) {
    await SystemChrome.setPreferredOrientations(launchOrientations);
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
  PlexLink Function(String clientId)? plexLink, // tests: a fake plex.tv
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
    twinsOf:
        db.twinsOf, // le même morceau sur un autre compte, ou sur le téléphone
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
    plexLink: plexLink,
  );
  await accountService.watchOffline();
  // à la maison : Wi-Fi et un serveur qui répond ; le Top 100 ne se garde que là
  final home = HomeState(wifi: ConnectivityWifi(), accounts: accountService);
  final downloader = Downloader(
    db: db,
    resolver: resolver,
    device: device,
    settings: () async => settings,
    mayAutoDownload: () => home.atHome,
    // un compte qui ne répond pas : ses morceaux viennent d'un jumeau qui répond
    reachable: (id) => accountService.mayAnswer(id),
  );
  downloader.followPlaylists(); // synchro, compte retiré : les .m3u8 suivent
  unawaited(downloader.resumeAtLaunch());
  final topKeeper = TopKeeper(
    db: db,
    downloader: downloader,
    atHome: () => home.atHome,
    reachable: (id) => accountService.mayAnswer(id),
  );
  // le Top 100 change (une écoute comptée) : un tour de plus, sans rafale
  final topSub = db.watchTop(100).listen((_) => topKeeper.schedule());
  var wasAtHome = false;
  home.addListener(() {
    if (home.atHome == wasAtHome) return;
    wasAtHome = home.atHome;
    if (!wasAtHome) {
      downloader.cancelAuto(); // jamais en données mobiles : le Top 100 en cours s'arrête
      return;
    }
    downloader.start(); // les copies Top 100 en attente repartent
    topKeeper.refreshQuietly();
  });
  // un serveur revient : la file reprend (copies demandées par l'utilisateur)
  // …ou un compte vient d'être vu injoignable : ses morceaux en file passent à un jumeau
  var wasOnline = accountService.anyConnected;
  var wasAbsent = accountService.absentIds;
  accountService.addListener(() {
    final online = accountService.anyConnected;
    final absent = accountService.absentIds;
    if (online && (!wasOnline || !wasAbsent.containsAll(absent))) {
      downloader.start();
    }
    wasOnline = online;
    wasAbsent = absent;
  });
  // fichiers posés à la main dans le dossier : relus au lancement, au retour au premier plan
  // et quand le dossier change (déplacement ou nouveau choix : refreshRoot prévient)
  final localFolder = LocalFolder(
    db: db,
    device: device,
    reader: TagLibReader(),
    inFlight: () =>
        downloader.targetPath, // le fichier en cours n'est pas posé à la main
  );
  // le lancement relit déjà ; une erreur du téléphone n'empêche jamais l'appli de démarrer
  String? scannedRoot;
  try {
    scannedRoot = (await device.musicRoot()).path;
  } on Object {
    scannedRoot = null;
  }
  accountService.addListener(() async {
    try {
      final path = (await device.musicRoot()).path;
      if (path == scannedRoot) return;
      scannedRoot = path;
      unawaited(localFolder.rescan());
    } on Object {
      // dossier illisible : la prochaine annonce réessaie
    }
  });
  // le même morceau sur plusieurs comptes : joué depuis le premier qui répond (P8)
  resolver.reachable = (id) => accountService.mayAnswer(id);
  final library = LibraryView(db, settings: settings);
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
  // Mode Classic ou normal (téléphone) : retenu ; changer remplace l'écran, pas le lecteur
  final classicMode = ValueNotifier<bool>(settings.classicMode);
  classicMode.addListener(() {
    settings.classicMode = classicMode.value;
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
    library: library,
    loudness: loudness,
    covers: covers,
    resolver: resolver,
    accounts: accounts,
    accountService: accountService,
    localFolder: localFolder,
    downloader: downloader,
    device: device,
    home: home,
    topKeeper: topKeeper,
    topSub: topSub,
    player: player,
    equalizer: equalizer,
    artistGrid: artistGrid,
    classicMode: classicMode,
    settings: settings,
    saveSettings: () => settings.save(settingsFile),
    strings: Strings.of(PlatformDispatcher.instance.locale),
  );
}

class LafleurApp extends StatefulWidget {
  const LafleurApp({
    super.key,
    required this.db,
    required this.library,
    required this.covers,
    required this.player,
    required this.strings,
    required this.equalizer,
    required this.artistGrid,
    required this.classicMode,
    required this.settings,
    required this.saveSettings,
    required this.loudness,
    required this.resolver,
    required this.accounts,
    required this.accountService,
    required this.localFolder,
    required this.downloader,
    required this.device,
    required this.home,
    required this.topKeeper,
    required this.topSub,
  });
  final LoudnessService loudness;
  final MediaResolver resolver;
  // le même pour le lecteur (MediaResolver) et les écrans
  final Accounts accounts;
  final AccountService accountService;
  final LocalFolder localFolder;
  final Downloader downloader;
  final Device device;
  final HomeState home;
  final TopKeeper topKeeper;
  final StreamSubscription<Object?> topSub;
  final AppSettings settings;
  final VoidCallback saveSettings;
  final ValueNotifier<bool> artistGrid;
  final ValueNotifier<bool> classicMode;
  final LibraryDb db;
  final LibraryView library;
  final Covers covers;
  final LafleurPlayer player;
  final Strings strings;
  final ValueNotifier<Equalizer> equalizer;

  @override
  State<LafleurApp> createState() => _LafleurAppState();
}

class _LafleurAppState extends State<LafleurApp> with WidgetsBindingObserver {
  late final PlayCounter _plays; // Top 100 et scrobbles

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _plays = PlayCounter(
      widget.player.state,
      widget.db,
      sourceOf:
          widget.resolver.source, // écoute d'un morceau du serveur → scrobble
      playedAs: widget.resolver.playedKey, // …sur le compte qui a joué
    );
    unawaited(widget.localFolder.rescan());
    // au lancement : la bibliothèque des serveurs est remise à jour en arrière-plan
    unawaited(widget.accountService.syncAll());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(widget.localFolder.rescan());
      unawaited(
        widget.home.recheck(),
      ); // le réseau a pu changer pendant l'absence
      widget.downloader.start();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _plays.dispose();
    widget.topSub.cancel();
    widget.topKeeper.dispose();
    widget.home.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppScope(
    db: widget.db,
    libraryView: widget.library,
    player: widget.player,
    covers: widget.covers,
    strings: widget.strings,
    equalizer: widget.equalizer,
    artistGrid: widget.artistGrid,
    classicMode: widget.classicMode,
    settings: widget.settings,
    saveSettings: widget.saveSettings,
    loudness: widget.loudness,
    accounts: widget.accounts,
    accountService: widget.accountService,
    downloader: widget.downloader,
    device: widget.device,
    localFolder: widget.localFolder,
    home: widget.home,
    child: MaterialApp(
      title: 'LAFLEURMUSIC',
      debugShowCheckedModeBanner: false,
      theme: lafleurTheme(),
      home: const AdaptiveHome(), // téléphone : la vue téléphone ; tablette, ordinateur : les colonnes du Mac
    ),
  );
}
