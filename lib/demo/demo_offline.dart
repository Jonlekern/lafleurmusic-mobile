import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../library/db.dart';
import '../library/models.dart';
import '../offline/device.dart';
import '../offline/downloader.dart';
import '../settings.dart';
import '../sources/account_service.dart';
import 'demo_library.dart';

/// « Garder sur mon iPhone » sans réseau ni disque (mode démo et tests d'écran) : note ce qu'on lui
/// demande et répond [result].
class DemoDownloader extends ChangeNotifier implements Downloader {
  DemoDownloader({this.result = const KeepResult.queued(0, 0)});

  /// Réponse de [keep] (ok, trop gros, erreur).
  KeepResult result;

  /// Chemins demandés à [keep], un lot par appel.
  final kept = <List<String>>[];

  /// Chemins passés à [forget], un lot par appel.
  final forgotten = <List<String>>[];

  @override
  bool accessDenied = false;

  /// Le morceau en cours et sa progression (0 à 1) : [current] null = rien ne tourne.
  @override
  String? current;
  @override
  double progress = 0;

  /// Appels à [pause], à [start], à [resume] et à [adoptRoot].
  int pauses = 0, starts = 0, resumes = 0, adopted = 0;

  @override
  bool userPaused = false;

  /// Réponse de [moveRoot] ; avec [moveGate], elle attend que le test la libère.
  KeepResult moveResult = const KeepResult.queued(0, 0);
  Completer<void>? moveGate;

  /// Les déplacements demandés : de, vers.
  final moves = <(Directory, Directory)>[];

  @override
  void pause() {
    pauses++;
    userPaused = true;
    current = null;
    notifyListeners();
  }

  @override
  void start() => starts++;

  @override
  void resume() {
    resumes++;
    userPaused = false;
    notifyListeners();
  }

  @override
  Future<KeepResult> adoptRoot({
    required Future<void> Function() commit,
  }) async {
    adopted++;
    if (moveResult.ok) await commit();
    return moveResult;
  }

  @override
  Future<KeepResult> moveRoot({
    required Directory from,
    required Directory to,
    Future<void> Function()? commit,
  }) async {
    moves.add((from, to));
    await moveGate?.future;
    if (moveResult.ok) await commit?.call();
    return moveResult;
  }

  @override
  Future<KeepResult> keep(
    List<Track> tracks, {
    OfflineReason reason = OfflineReason.user,
    String Function(Track)? origin,
    bool unpause = true,
  }) async {
    kept.add([for (final t in tracks) t.path]);
    if (origin != null) {
      origins.add({for (final t in tracks) origin(t)});
    }
    return result;
  }

  /// Les raisons notées par [keep], un ensemble par appel.
  final origins = <Set<String>>[];

  /// Les raisons retirées par [forgetFrom].
  final forgottenOrigins = <String>[];

  @override
  Future<List<String>> toForgetFrom(String origin, List<String> paths) async =>
      fromOrigin ?? paths;

  @override
  Future<void> forgetFrom(
    String origin,
    List<String> paths, {
    bool block = true,
  }) async {
    forgottenOrigins.add(origin);
    forgotten.add(paths);
  }

  @override
  Future<void> forget(
    List<String> trackPaths, {
    OfflineReason? only,
    bool byUser = false,
    bool block = true,
  }) async => forgotten.add(trackPaths);

  @override
  Future<void> whenIdle() => Future.value();

  /// Playlists demandées à [keepPlaylist] et à [forgetPlaylist] : (compte, playlist).
  final keptPlaylists = <(String, String)>[];
  final forgottenPlaylists = <(String, String)>[];

  @override
  Future<KeepResult> keepPlaylist(String accountId, String playlistId) async {
    keptPlaylists.add((accountId, playlistId));
    return result;
  }

  /// Réponse de [playlistSongsToForget] (vide : rien ne partirait) et de [toForgetFrom]
  /// (null : tous les morceaux donnés).
  List<String> playlistSongs = const [];
  List<String>? fromOrigin;

  @override
  Future<List<String>> playlistSongsToForget(
    String accountId,
    String playlistId,
  ) async => playlistSongs;

  @override
  Future<void> forgetPlaylist(String accountId, String playlistId) async =>
      forgottenPlaylists.add((accountId, playlistId));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Les comptes de la démo : les morceaux de [notOnPhone] ne sont pas jouables (hors ligne, jamais gardés).
class DemoAccountService extends AccountService {
  DemoAccountService(
    super.accounts, {
    required super.db,
    super.draftSource,
    super.sourceOf,
    super.sync,
    this.notOnPhone = const {},
  });
  final Set<String> notOnPhone;

  @override
  bool playableNow(Track t) => !notOnPhone.contains(t.path);
}

/// Un album déjà copié : une ligne `done` par morceau, [bytes] au total (la place utilisée).
Future<void> seedKept(LibraryDb db, List<String> paths, int bytes) async {
  await db.queueOffline(paths, OfflineReason.user);
  for (final (i, p) in paths.indexed) {
    await db.markOfflineDone(p, 'kept/$i.mp3', bytes ~/ paths.length);
  }
}

/// Les données de la démo « Garder » : la bibliothèque serveur, Lafleur Surf gardé (4,2 Go utilisés).
Future<void> seedKeepDemo(LibraryDb db) async {
  await db.upsertTracks(DemoLibrary.remote);
  await seedKept(db, DemoLibrary.keptPaths, 4509715661); // 4,2 Go
}

/// Les playlists du serveur de la maquette 7 (écrans 10, 11) : « Soirée » et « Running » (gardée)
/// sur [navidrome], « Chill du dimanche » sur [jellyfin]. « Soirée » joue « Ocean Drive » deux fois et
/// finit sur un morceau absent de son compte. Après [seedKeepDemo].
Future<void> seedPlaylistDemo(
  LibraryDb db, {
  required String navidrome,
  required String jellyfin,
}) async {
  String of(String album, int no) => 'subsonic://demo/$album/$no';
  await db.upsertTracks([DemoLibrary.goldenHour]);
  final running = [
    of('Night Drive', 2),
    of('Lafleur Surf', 2),
    of('Ports', 1),
    of('Studio Lafleur', 7),
  ];
  await db.replacePlaylists(navidrome, [
    (
      id: 'soiree',
      name: 'Soirée',
      paths: [
        of('Studio Lafleur', 1),
        of('Lafleur Surf', 1),
        of('Night Drive', 1),
        of('Studio Lafleur', 4),
        DemoLibrary.goldenHour.path,
        of('Studio Lafleur', 1),
        of('Gone', 1), // plus dans la bibliothèque du compte
      ],
    ),
    (id: 'running', name: 'Running', paths: running),
  ]);
  await db.replacePlaylists(jellyfin, [
    (
      id: 'chill',
      name: 'Chill du dimanche',
      paths: [
        of('Studio Lafleur', 3),
        of('Lafleur Surf', 1),
        of('Summer Mix', 1),
        of('Night Drive', 3),
      ],
    ),
  ]);
  // « Running » gardée : ses morceaux copiés (Surf Radio l'est déjà), son .m3u8 noté
  await seedKept(db, [
    for (final p in running)
      if (!DemoLibrary.keptPaths.contains(p)) p,
  ], 30 * _mib);
  await db.setKeptPlaylist(navidrome, 'running', 'Running.m3u8');
}

const _mib = 1024 * 1024, _gib = 1024 * _mib;

/// Le téléphone de la démo : un dossier par défaut, 54 Go de place en tout (copies comprises), et
/// ce que le sélecteur de dossier répond ([picked], ou [pickError] levée).
class DemoDevice implements Device {
  DemoDevice({
    this.root = '/var/mobile/Documents/LAFLEURMUSIC',
    this.free =
        54 * _gib -
        4509715661 +
        1024, // + les octets perdus aux divisions des copies
    this.settings,
  });

  /// Le dossier adopté s'y inscrit, comme avec le vrai téléphone.
  final AppSettings? settings;
  String root;
  int free;
  PickedFolder? picked;

  /// Réponses suivantes de [pickFolder] avant de revenir à [picked].
  final pickQueue = <PickedFolder?>[];
  Object? pickError;
  bool reachable = true;

  /// Fait échouer [freeBytes] ; [pickGate] retient la réponse de [pickFolder] jusqu'à sa fin.
  Object? freeError;

  /// Appels à [pickFolder].
  int picks = 0;
  Completer<void>? pickGate;

  /// Dossiers adoptés par [commitFolder], et abandons par [releaseCandidate].
  final committed = <PickedFolder>[];
  int released = 0;

  @override
  Future<Directory> musicRoot() async => Directory(root);

  @override
  Future<bool> rootReachable() async => reachable;

  @override
  Future<PickedFolder?> pickFolder() async {
    picks++;
    await pickGate?.future;
    final e = pickError;
    if (e != null) throw e;
    if (pickQueue.isNotEmpty) return pickQueue.removeAt(0);
    return picked;
  }

  @override
  Future<void> commitFolder(PickedFolder c) async {
    committed.add(c);
    root = c.path;
    settings?.musicFolder = c.bookmark ?? c.path;
  }

  @override
  Future<void> releaseCandidate() async => released++;

  @override
  Future<int> freeBytes(String path) async {
    final e = freeError;
    if (e != null) throw e;
    return free;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Les données de la démo « Sur mon iPhone » (maquette 4) : Lafleur Surf (48 min), Studio Lafleur
/// gardés, Night Drive gardé par le Top 100 (4 titres), « Golden Hour » en cours avec 3 titres derrière,
/// « Ports » refusé par le serveur. 4,2 Go utilisés : le reste, des copies dont le morceau n'est plus
/// dans la bibliothèque (rien à afficher, mais la place compte).
Future<void> seedOnDeviceDemo(LibraryDb db) async {
  await db.upsertTracks([
    ...DemoLibrary.remote,
    ...DemoLibrary.surf48,
    DemoLibrary.nightDrive4,
    DemoLibrary.goldenHour,
  ]);
  String of(String album, int no) => 'subsonic://demo/$album/$no';
  // l'ordre de la liste suit l'heure de mise en file : une pause d'une milliseconde entre albums
  Future<void> next() => Future<void>.delayed(const Duration(milliseconds: 12));
  await seedKept(db, DemoLibrary.keptPaths, 420 * _mib);
  await next();
  await seedKept(db, [
    for (final t in DemoLibrary.remote)
      if (t.album == 'Studio Lafleur') t.path,
  ], 310 * _mib);
  await next();
  final night = [for (var i = 1; i <= 4; i++) of('Night Drive', i)];
  await db.queueOffline(night, OfflineReason.top100);
  for (final path in night) {
    await db.markOfflineDone(path, 'kept/$path.mp3', 38 * _mib ~/ 4);
  }
  await db.queueOffline([of('Other', 1)], OfflineReason.user);
  await db.markOfflineDone(
    of('Other', 1),
    'kept/other.mp3',
    4509715661 - (310 + 420 + 38) * _mib,
  );
  await db.queueOffline([
    DemoLibrary.goldenHour.path,
    of('Summer Mix', 1),
    of('Summer Mix', 2),
    of('Summer Mix', 3),
  ], OfflineReason.user);
  await db.queueOffline([of('Ports', 1)], OfflineReason.user);
  for (var i = 0; i < 3; i++) {
    await db.markOfflineFailed(of('Ports', 1));
  }
}
