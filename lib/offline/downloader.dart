import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show TableUpdateQuery;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../library/db.dart';
import '../library/models.dart';
import '../player/media_resolver.dart';
import '../settings.dart';
import '../sources/source.dart';
import '../tags/tag_reader.dart';
import '../tags/tag_writer.dart';
import 'device.dart';
import 'keep_origin.dart';
import 'm3u.dart';
import 'paths.dart';

export 'keep_origin.dart';

/// Place laissée libre sur le téléphone.
const _freeMargin = 200 * 1024 * 1024;

/// Taille comptée pour un morceau dont le serveur ne dit pas la taille.
const unknownTrackSize = 10 * 1024 * 1024;

/// Réponse de [Downloader.keep] et [Downloader.moveRoot].
class KeepResult {
  const KeepResult.queued(this.count, this.bytes)
    : ok = true,
      neededBytes = 0,
      folderUnavailable = false;

  /// Refusé : il manque [neededBytes] (le plus grand écart avec la limite ou la place libre).
  const KeepResult.tooBig(this.neededBytes)
    : ok = false,
      count = 0,
      bytes = 0,
      folderUnavailable = false;

  /// Une erreur au milieu : rien n'a changé.
  const KeepResult.failed()
    : ok = false,
      neededBytes = 0,
      count = 0,
      bytes = 0,
      folderUnavailable = false;

  /// Refusé : le dossier choisi ne répond plus (jamais de copie dans le dossier par défaut).
  const KeepResult.folderUnavailable()
    : ok = false,
      neededBytes = 0,
      count = 0,
      bytes = 0,
      folderUnavailable = true;

  final bool ok, folderUnavailable;
  final int count, bytes, neededBytes;
}

/// Le serveur refuse CE morceau (introuvable, vide, format inconnu) : seul cas compté
/// comme un échec. Un autre refus pour ce morceau (5xx, 429, 401/403, page de proxy,
/// compte sans source) l'envoie derrière, sans compter, et son compte attend le tour
/// suivant ; le réseau et le disque arrêtent la file.
class _Refusal implements Exception {}

/// Ce que la boucle fait après un morceau.
enum _Next { go, skipAccount, stop }

/// Une réponse que le serveur n'a pas servie comme fichier (4xx, ou erreur Subsonic en JSON/XML).
class _NotAFile implements Exception {
  _NotAFile(this.status);
  final int status;
}

/// The server answered 401 (the token may have been revoked).
class _Unauthorized implements Exception {}

/// File des copies hors ligne : un morceau à la fois, repris au lancement.
/// Aucune URL (elle porte le jeton) dans les erreurs ni les journaux.
class Downloader extends ChangeNotifier {
  Downloader({
    required this.db,
    required this.resolver,
    required this.device,
    required this.settings,
    http.Client Function()? client,
    TagFileIO? tags,
    TagReader? reader,
    this.mayAutoDownload,
    this.reachable,
  }) : _client = client ?? newServerClient,
       _tags = tags ?? TagLibIO(),
       _reader = reader ?? TagLibReader();

  final LibraryDb db;
  final MediaResolver resolver;
  final Device device;
  final Future<AppSettings> Function() settings;
  final http.Client Function() _client;
  final TagFileIO _tags;
  final TagReader _reader;

  /// Le compte [id] répond-il (pas marqué injoignable) ? Null : tous.
  final bool Function(String id)? reachable;

  /// Les copies `top100` ne partent que si ceci répond vrai (à la maison) ; les `user` toujours.
  /// Quand ça redevient vrai, l'appelant refait [start].
  final bool Function()? mayAutoDownload;

  /// Les `.m3u8` des playlists gardées, réécrits quand une copie arrive ou part.
  late final playlistFiles = PlaylistFiles(db, device);

  Future<void> _refreshPlaylists() async {
    try {
      await playlistFiles.refresh();
    } catch (e) {
      // un fichier de playlist n'arrête pas les copies
      _lastError = _describe(e);
    }
  }

  /// Une copie est arrivée pendant ce tour : les .m3u8 se réécrivent une fois, à la fin.
  bool _playlistsDirty = false;

  StreamSubscription<void>? _playlistsSub;
  Future<void> _playlistsJob = Future.value();

  /// Suit les playlists des serveurs (synchro, compte retiré) : voir [syncPlaylists].
  void followPlaylists() {
    _playlistsSub ??= db
        .tableUpdates(TableUpdateQuery.onTable(db.playlists))
        .listen((_) => syncPlaylists());
  }

  /// Un travail sur les playlists gardées à la fois (rattrapage, « Retirer »).
  Future<T> _playlistsSerial<T>(Future<T> Function() f) {
    final run = _playlistsJob.then((_) => f());
    _playlistsJob = run.then((_) {}, onError: (Object _) {});
    return run;
  }

  /// Se termine quand les changements de playlists déjà vus sont traités.
  @visibleForTesting
  Future<void> whenPlaylistsSettled() => _playlistsJob;

  /// Les playlists des serveurs ont changé (ou l'appli démarre) : chaque playlist encore
  /// gardée garde ses morceaux qui n'ont aucune copie, pas même en échec (ceux qu'elle a gagnés
  /// sur le serveur, règle Q12), sauf ceux que l'utilisateur a retirés un par un (bloqués),
  /// sans lever sa pause ; puis les .m3u8 suivent (une playlist que le serveur n'a plus, ou
  /// dont le compte est retiré, perd son fichier : règle Q10).
  Future<void> syncPlaylists() => _playlistsSerial(() async {
    try {
      for (final e in (await db.keptPlaylistsMissing()).entries) {
        final (acc, id) = e.key;
        // « Retirer » entre-temps : plus rien à garder pour elle
        if (!await db.isKeptPlaylist(acc, id)) continue;
        final origin = KeepOrigin.playlist(acc, id);
        await keep(e.value, origin: (_) => origin, unpause: false);
      }
    } catch (e) {
      _lastError = _describe(e);
    }
    await _refreshPlaylists();
  });

  @override
  void dispose() {
    _playlistsSub?.cancel();
    super.dispose();
  }

  Future<void>? _loop;
  bool _paused = false;
  bool _userPaused = false; // « Pause » de l'écran : seul « Reprendre » ou un « Garder » la lève
  bool _sweeping = false; // resumeAtLaunch efface les .part : la boucle attend
  bool _wanted = false; // un start() a eu lieu depuis le début du tour
  bool _moving = false; // moveRoot en cours : la boucle ne tourne pas
  bool _accessOk = false;
  bool _accessDenied = false;
  final _reserved =
      <String>{}; // chemins relatifs (minuscules) déjà donnés ce tour
  _Active? _active;
  double _progress = 0;

  /// Le morceau en cours de téléchargement (sa clé), sinon null.
  String? get current => _active?.path;

  String? _target;

  /// Le fichier final en cours d'écriture ou tout juste rangé, pas encore noté `done`.
  String? get targetPath => _target;

  /// Avancement du morceau en cours, de 0 à 1.
  double get progress => _progress;

  /// Vrai si l'utilisateur a mis la file en pause (écran « Sur mon iPhone »).
  bool get userPaused => _userPaused;

  /// Vrai si l'utilisateur a refusé l'accès au stockage : la file est arrêtée.
  bool get accessDenied => _accessDenied;

  String? _lastError;

  /// Dernière erreur qui a arrêté la file ou fait échouer un morceau (type et message,
  /// jamais l'URL ni le jeton). Pour les tests de bout en bout.
  @visibleForTesting
  String? get lastError => _lastError;

  static String _describe(Object e) => switch (e) {
    FileSystemException(:final message, :final osError, :final path) =>
      'FileSystemException: $message (${osError?.message}, errno '
          '${osError?.errorCode}) ${path == null ? '' : p.basename(path)}',
    // jamais l'URL d'une ClientException ; les autres : leur type seul
    http.ClientException(:final message) => 'ClientException: $message',
    StateError(:final message) => 'StateError: $message',
    _ => e.runtimeType.toString(),
  };

  /// Se termine quand la boucle s'arrête (file vide, pause ou accès refusé).
  Future<void> whenIdle() => _loop ?? Future.value();

  static int _sizeOf(Track t) => t.size > 0 ? t.size : unknownTrackSize;

  /// Garde [tracks] : refuse tout si ça dépasse la limite ou la place libre, ou si le
  /// dossier choisi ne répond plus. Un « Garder » de l'utilisateur lève sa pause.
  /// [origin] : pourquoi l'utilisateur garde chaque morceau ([KeepOrigin]) ; null : rien de
  /// noté (Top 100, « Réessayer » qui garde les raisons d'avant).
  /// [unpause] faux : la pause de l'utilisateur reste (un rattrapage automatique).
  Future<KeepResult> keep(
    List<Track> tracks, {
    OfflineReason reason = OfflineReason.user,
    String Function(Track)? origin,
    bool unpause = true,
  }) {
    // un à la fois : une garde automatique ne prend pas la place qu'un « Garder » vient de libérer
    final run = _keepLock.then((_) => _keep(tracks, reason, origin, unpause));
    _keepLock = run.then((_) {}, onError: (Object _) {});
    return run;
  }

  Future<void> _keepLock = Future.value();

  Future<KeepResult> _keep(
    List<Track> tracks,
    OfflineReason reason,
    String Function(Track)? origin,
    bool unpause,
  ) async {
    if (!await device.rootReachable()) {
      return const KeepResult.folderUnavailable();
    }
    // le Top 100 laisse de côté ce que l'utilisateur a retiré (avant tout calcul de place)
    // …ou ce qu'il a retiré d'un jumeau (le même morceau sur un autre compte, règle Q8)
    final remote = [
      for (final t in tracks)
        if (parseRemoteKey(t.path) != null &&
            !(reason == OfflineReason.top100 &&
                await db.autoKeepBlockedFor(t.path)))
          t,
    ];
    final batch = _albumOrder(remote);
    final fresh = <Track>[]; // ni terminés ni déjà en file
    final toQueue = <String>[];
    final done = <String>[];
    final dropOwn = <String>[];
    for (final t in batch) {
      // le même morceau sur un autre compte, déjà gardé ou en file : pas de seconde copie
      final own = await db.offlineOf(t.path);
      final row = own == null || own.state == OfflineState.failed.name
          ? await db.twinOffline(t.path) ?? own
          : own;
      if (row?.state == OfflineState.done.name ||
          row?.state == OfflineState.queued.name) {
        final path = row!.trackPath;
        // its own failed row gives way to the twin's copy (no retry of a second copy)
        if (own != null && path != t.path) dropOwn.add(t.path);
        if (row.state == OfflineState.done.name) {
          done.add(path);
        } else {
          toQueue.add(path);
        }
        continue;
      }
      // aucune copie, ou seulement une en échec : un jumeau dont le compte répond
      final from = await _sourceFor(t, ownFailed: own != null);
      if (own != null && from.path != t.path) dropOwn.add(t.path);
      toQueue.add(from.path);
      fresh.add(from);
    }
    // une copie déjà faite par le Top 100 devient celle de l'utilisateur : plus jamais retirée toute seule
    await db.queueOffline(done, reason);
    final need = fresh.fold<int>(0, (s, t) => s + _sizeOf(t));
    final limit = (await settings()).storageLimitBytes;
    final root = await device.musicRoot();
    // la file d'attente déjà promise compte aussi dans la limite
    Future<int> overLimit() async =>
        await db.offlineBytes() +
        await db.queuedBytes(unknownTrackSize) +
        need -
        limit;
    Future<int> freeNow() async =>
        await device.freeBytes(root.path) - _freeMargin;
    var over = await overLimit();
    var free = await freeNow();
    if (over > 0 || need > free) {
      final shortfall = over > need - free ? over : need - free;
      if (reason != OfflineReason.user ||
          !await _evictTop100(over, need - free, {
            for (final t in batch) t.path,
          })) {
        return KeepResult.tooBig(shortfall);
      }
      // seuls les fichiers vraiment effacés ont libéré de la place
      over = await overLimit();
      free = await freeNow();
      if (over > 0 || need > free) {
        return KeepResult.tooBig(over > need - free ? over : need - free);
      }
    }
    await db.queueOffline(toQueue, reason);
    await db.removeOffline(dropOwn);
    if (reason == OfflineReason.user && origin != null) {
      await db.addOrigins({for (final t in remote) t.path: origin(t)});
    }
    // un « Garder » de l'utilisateur lève le blocage du Top 100
    if (reason == OfflineReason.user) {
      await db.unblockAutoKeep([
        ...toQueue,
        for (final p in toQueue) ...await db.twinPaths(p),
      ]);
    }
    _accessDenied = false;
    if (reason == OfflineReason.user && unpause) _userPaused = false;
    start();
    return KeepResult.queued(fresh.length, need);
  }

  bool _answers(String path) {
    final acc = parseRemoteKey(path)?.$1;
    return acc == null || (reachable?.call(acc) ?? true);
  }

  /// D'où copier [t] : lui, sinon un jumeau (le même morceau sur un autre compte, dans
  /// l'ordre de l'écran des comptes) si son compte à lui ne répond pas ; après un échec
  /// sur [t] ([ownFailed]), un jumeau d'abord. Aucun ne répond : [t].
  Future<Track> _sourceFor(Track t, {bool ownFailed = false}) async {
    final others = [
      for (final w in await db.twinsOf(t.path))
        if (w.path != t.path && parseRemoteKey(w.path) != null) w,
    ];
    final order = ownFailed ? [...others, t] : [t, ...others];
    return order.firstWhere((w) => _answers(w.path), orElse: () => t);
  }

  /// « Garder » une playlist du serveur : ses morceaux (chacun une fois, les absents de son
  /// compte laissés de côté), puis son `.m3u8` sous `Playlists/`, écrit au fil des copies.
  Future<KeepResult> keepPlaylist(String accountId, String playlistId) async {
    final seen = <String>{};
    final tracks = <Track>[];
    for (final path in await db.playlistPaths(accountId, playlistId)) {
      if (!seen.add(path)) continue;
      final t = await db.trackByPath(path);
      if (t != null) tracks.add(t);
    }
    final origin = KeepOrigin.playlist(accountId, playlistId);
    final r = await keep(tracks, origin: (_) => origin);
    if (r.ok) {
      await db.addKeptPlaylist(accountId, playlistId);
      await _refreshPlaylists();
    }
    return r;
  }

  /// Ce que retirer [origin] de [paths] efface vraiment : ceux qui n'ont, jumeaux compris,
  /// aucune autre raison d'être gardés (règle Q13). Une copie du Top 100 n'en a aucune ;
  /// celle d'avant la v4 ([KeepOrigin.legacy]) ne compte pas comme une autre raison.
  Future<List<String>> toForgetFrom(String origin, List<String> paths) async {
    final out = <String>[];
    for (final path in {...paths}) {
      final others = (await db.originsOf(path))
          .where((o) => o != origin && o != KeepOrigin.legacy);
      if (others.isNotEmpty) continue;
      out.add(path);
    }
    return out;
  }

  /// Retirer un album ou une playlist ([origin]) : la raison part, puis les morceaux qui n'en
  /// ont plus aucune sont retirés comme par l'utilisateur ([forget] `byUser`, jumeaux compris),
  /// bloqués pour le Top 100 sauf avec [block] faux.
  Future<void> forgetFrom(
    String origin,
    List<String> paths, {
    bool block = true,
  }) async {
    final gone = await toForgetFrom(origin, paths);
    await db.removeOrigin(origin, paths);
    await forget(gone, byUser: true, block: block);
  }

  /// Ce que « Retirer » une playlist retire : ses morceaux qui ne sont gardés pour aucune
  /// autre raison (un album, une autre playlist, le morceau lui-même).
  Future<List<String>> playlistSongsToForget(
    String accountId,
    String playlistId,
  ) async => toForgetFrom(
    KeepOrigin.playlist(accountId, playlistId),
    await db.playlistPaths(accountId, playlistId),
  );

  /// « Retirer » une playlist : son `.m3u8` (le nôtre) part, puis ses morceaux qui n'ont plus
  /// d'autre raison ; sans les bloquer : le Top 100 peut les garder de nouveau (règle Q11).
  /// Jamais en même temps qu'un rattrapage ([syncPlaylists]).
  Future<void> forgetPlaylist(String accountId, String playlistId) =>
      _playlistsSerial(() async {
        await playlistFiles.remove(accountId, playlistId);
        await forgetFrom(
          KeepOrigin.playlist(accountId, playlistId),
          await db.playlistPaths(accountId, playlistId),
          block: false,
        );
      });

  /// Fait de la place pour un « Garder » de l'utilisateur : efface des copies `top100`,
  /// les moins écoutées d'abord, juste ce qu'il faut pour couvrir [overLimit] (la limite)
  /// et [overDisk] (la place libre ; seules les copies finies en libèrent). Jamais une
  /// copie de l'utilisateur ni de [keep] (le lot demandé). Faux, sans rien effacer, si
  /// les copies `top100` ne suffisent pas.
  Future<bool> _evictTop100(
    int overLimit,
    int overDisk,
    Set<String> keep,
  ) async {
    final out = <String>[];
    var limitLeft = overLimit, diskLeft = overDisk;
    for (final r in await db.top100ByLeastPlayed()) {
      if (limitLeft <= 0 && diskLeft <= 0) break;
      if (keep.contains(r.trackPath)) continue;
      final done = r.state == OfflineState.done.name;
      // un échec ne compte ni dans la limite ni sur le disque ; une copie en file ne libère rien sur le disque
      if (r.state == OfflineState.failed.name) continue;
      if (!done && limitLeft <= 0) continue;
      // en file : la taille annoncée par le serveur, comme le décompte de la limite
      final size = done
          ? r.size
          : await db.trackSize(r.trackPath) ?? unknownTrackSize;
      out.add(r.trackPath);
      limitLeft -= size;
      if (done) diskLeft -= r.size;
    }
    if (limitLeft > 0 || diskLeft > 0) return false;
    await forget(out, only: OfflineReason.top100);
    return true;
  }

  /// Albums dans l'ordre où ils apparaissent, chacun par disque puis numéro.
  static List<Track> _albumOrder(List<Track> tracks) {
    final groups = <String, List<Track>>{};
    for (final t in tracks) {
      (groups['${t.albumArtist}\u0000${t.album}'] ??= []).add(t);
    }
    int by(Track a, Track b) {
      final d = (a.disc ?? 0).compareTo(b.disc ?? 0);
      return d != 0 ? d : (a.trackNo ?? 0).compareTo(b.trackNo ?? 0);
    }

    return [for (final g in groups.values) ...(List.of(g)..sort(by))];
  }

  /// Relance la file (retour au premier plan, serveur revenu, à la maison…) ; sans effet
  /// pendant une pause de l'utilisateur.
  void start() {
    if (_userPaused) return;
    _wanted = true;
    _paused = false;
    if (_loop != null || _moving || _sweeping) return;
    _launch();
  }

  /// « Reprendre » de l'écran : lève la pause de l'utilisateur.
  void resume() {
    _userPaused = false;
    start();
    notifyListeners();
  }

  void _launch() {
    _wanted = false;
    late final Future<void> f;
    f = _run().whenComplete(() {
      if (identical(_loop, f)) _loop = null;
      // un start() arrivé pendant que la boucle s'arrêtait ne doit pas se perdre
      if (_wanted && !_paused && !_moving && !_sweeping && _loop == null) {
        _launch();
      }
    });
    _loop = f;
  }

  /// Sorti de la maison : le morceau du Top 100 en cours est abandonné (il reste en file) ;
  /// un morceau demandé par l'utilisateur continue.
  void cancelAuto() {
    final a = _active;
    if (a != null && a.auto) a.cancel();
  }

  /// « Pause » de l'écran : arrête après avoir abandonné le morceau en cours (il reste
  /// en file) ; les relances automatiques ([start]) attendent [resume] ou un « Garder ».
  void pause() {
    _userPaused = true;
    _paused = true;
    _active?.cancel();
    notifyListeners();
  }

  Future<void> _run() async {
    final skip =
        <String>{}; // comptes dont le serveur a refusé un morceau ce tour
    try {
      // les comptes qui ne répondent pas (adresse de la maison, dehors) : leurs morceaux en
      // file passent d'abord à un jumeau qui répond
      if (reachable != null) {
        for (final row in await db.offlineRows()) {
          if (row.state != OfflineState.queued.name) continue;
          if (!_answers(row.trackPath)) await _moveToTwin(row);
        }
      }
      while (!_paused && !_moving) {
        final row = await db.nextQueued(
          top100: mayAutoDownload?.call() ?? true,
          skipAccounts: skip,
        );
        if (row == null) break;
        if (await db.trackByPath(row.trackPath) == null) {
          // le morceau a disparu (synchro, compte retiré) : plus rien à copier, ni à compter
          await db.removeOffline([row.trackPath]);
          continue;
        }
        // son compte ne répond pas (adresse de la maison, dehors) : un jumeau prend sa place
        if (!_answers(row.trackPath) && await _moveToTwin(row)) continue;
        // dossier choisi injoignable : jamais de copie dans le dossier par défaut, rien de compté
        if (!await device.rootReachable()) {
          _lastError = 'folder unavailable';
          break;
        }
        if (!_accessOk) {
          if (!await device.ensureAccess()) {
            _accessDenied = true; // refusé : rien n'est marqué en échec
            notifyListeners();
            break;
          }
          _accessOk = true;
        }
        final next = await _one(row);
        if (next == _Next.stop) break;
        if (next == _Next.skipAccount) {
          final acc = parseRemoteKey(row.trackPath)?.$1;
          if (acc != null) skip.add(acc);
        }
      }
    } on Object catch (e) {
      _lastError = _describe(
        e,
      ); // base fermée, canal natif… : la boucle s'arrête, sans planter
    } finally {
      _reserved.clear();
      _setProgress(0);
      if (_playlistsDirty) {
        _playlistsDirty = false;
        await _refreshPlaylists();
      }
    }
  }

  /// La ligne en file [row] passe à un jumeau dont le compte répond et qui n'a pas de copie.
  Future<bool> _moveToTwin(OfflineRow row) async {
    for (final w in await db.twinsOf(row.trackPath)) {
      if (w.path == row.trackPath || parseRemoteKey(w.path) == null) continue;
      if (!_answers(w.path) || await db.offlineOf(w.path) != null) continue;
      return db.moveQueued(row.trackPath, w.path);
    }
    return false;
  }

  /// [_Next.stop] si la boucle doit s'arrêter (réseau coupé, disque : rien n'est compté,
  /// le prochain start() reprend). Un refus du serveur pour ce morceau compte un échec et
  /// passe au suivant ; un autre souci propre au morceau l'envoie derrière, sans compter,
  /// et son compte attend le tour suivant ([_Next.skipAccount]).
  Future<_Next> _one(OfflineRow row) async {
    final active = _Active(
      row.trackPath,
      _client(),
      auto: row.reason == OfflineReason.top100.name,
    );
    _active = active;
    _setProgress(0);
    final done = Completer<void>();
    active.done = done.future;
    try {
      await _download(row, active); // null : abandonné (pause), reste en file
      return _Next.go;
    } catch (e) {
      if (active.cancelled) return _Next.go; // pause ou oubli : pas un échec
      _lastError = _describe(e);
      if (e is _Refusal) {
        await db.markOfflineFailed(row.trackPath);
        await db.sendOfflineToBack(row.trackPath);
        return _Next.go;
      }
      if (_stopsAll(e)) {
        // le réseau d'un compte déjà vu injoignable : lui seul attend, les autres continuent
        if (e is! FileSystemException && !_answers(row.trackPath)) {
          return _Next.skipAccount;
        }
        return _Next.stop;
      }
      await db.sendOfflineToBack(row.trackPath);
      return _Next.skipAccount;
    } finally {
      active.client.close();
      _active = null;
      _target = null;
      done.complete();
      notifyListeners();
    }
  }

  /// Réseau (socket, délai, TLS, coupure) ou disque : rien ne passera pour les autres non plus.
  static bool _stopsAll(Object e) =>
      e is IOException ||
      e is TimeoutException ||
      e is http.ClientException ||
      e is SourceNetworkException;

  /// Télécharge le morceau ; renvoie le chemin relatif, null si abandonné.
  Future<String?> _download(OfflineRow row, _Active active) async {
    final key = parseRemoteKey(row.trackPath);
    final t = await db.trackByPath(row.trackPath);
    if (key == null || t == null) {
      throw StateError('unknown track'); // pas un refus du serveur
    }
    final source = await resolver.source(key.$1);
    final root = await device.musicRoot();

    // Jellyfin: the token is read synchronously below, so it is loaded (or signed in) first
    final auth = source is AuthRenewable ? source as AuthRenewable : null;
    await auth?.prepare();

    var viaDownload = true;
    http.StreamedResponse res;
    try {
      res = await _getRenewing(
        active,
        // a download refused after a fresh sign-in is the account's rights, not the token:
        // the next songs go straight to the stream instead of signing in once each
        _downloadDenied.contains(key.$1) ? null : auth,
        () => source.downloadUri(key.$2),
        () => source.headers,
        onDenied: () => _downloadDenied.add(key.$1),
      );
    } on _NotAFile {
      // the original is refused (no download right: 401/403, not audio…): the stream
      viaDownload = false;
      res = await _getRenewing(
        active,
        auth,
        () => source.streamUri(key.$2),
        () => source.headers,
        fallback: true,
      );
    }
    final fromType = _extOfType(res.headers['content-type']);
    final suffix = t.suffix?.trim().toLowerCase();
    final String ext;
    if (viaDownload) {
      ext = (suffix != null && suffix.isNotEmpty ? suffix : fromType) ?? '';
    } else {
      ext = fromType ?? (suffix ?? '');
    }
    if (ext.isEmpty) throw _Refusal();

    final rel = _chooseName(root, t, ext);
    final file = File(p.join(root.path, rel));
    _target = file.path;
    final part = File(partialPath(file.path));
    await part.parent.create(recursive: true);
    final sink = part.openWrite();
    var got = 0;
    try {
      final total = res.contentLength ?? (t.size > 0 ? t.size : null);
      await for (final chunk in res.stream.timeout(requestTimeout)) {
        sink.add(chunk);
        got += chunk.length;
        if (total != null && total > 0) {
          _setProgress((got / total).clamp(0, 1).toDouble());
        }
      }
      await sink.close();
      if (active.cancelled) {
        await _drop(part);
        return null;
      }
      final len = res.contentLength;
      if (got == 0) throw _Refusal();
      if (len != null && len != got) {
        throw http.ClientException('truncated'); // coupure : comme le réseau
      }
      // les tags dans le fichier en cours (il garde son extension audio) : la taille
      // est définitive dès qu'il est rangé ; un échec laisse le fichier sans tags
      await _fillTags(part.path, t, source, active);
      if (active.cancelled) {
        await _drop(part);
        return null;
      }
      await part.rename(file.path);
    } catch (_) {
      try {
        await sink.close();
      } catch (_) {}
      await _drop(part);
      rethrow;
    }

    // fait dès le rangement (déjà taguée, taille définitive) : une coupure ensuite ne perd pas la copie
    if (await db.offlineOf(row.trackPath) == null) {
      await _drop(file); // oublié pendant le téléchargement
      return null;
    }
    await db.markOfflineDone(row.trackPath, rel, await file.length());
    try {
      await device.announce(file.path);
    } catch (_) {} // la médiathèque du système n'est pas vitale
    _playlistsDirty = true;
    return rel;
  }

  static bool _isAudioType(String type) {
    final t = type.split(';').first.trim();
    return t.isEmpty ||
        t.startsWith('audio/') ||
        t == 'application/octet-stream' ||
        t == 'binary/octet-stream' ||
        t == 'application/ogg';
  }

  /// [_get], and a 401 from a source that can sign in again ([auth]) signs in once and repeats.
  /// A second 401 is a refusal of this file, not of the token: it goes the usual way
  /// (original → stream; stream → server refused).
  Future<http.StreamedResponse> _getRenewing(
    _Active active,
    AuthRenewable? auth,
    Uri Function() url,
    Map<String, String> Function() headers, {
    bool fallback = false,
    void Function()? onDenied,
  }) async {
    try {
      return await _get(
        active,
        url(),
        headers(),
        fallback: fallback,
        unauthorized: auth != null,
      );
    } on _Unauthorized {
      await auth!.renewAuth();
      try {
        return await _get(active, url(), headers(), fallback: fallback);
      } on _NotAFile catch (e) {
        // only a refusal of the rights (not a 404, a proxy page…) marks the account
        if (e.status == 401 || e.status == 403) onDenied?.call();
        rethrow;
      }
    }
  }

  /// Accounts whose original files were refused (401) even with a fresh token, this session.
  final _downloadDenied = <String>{};

  Future<http.StreamedResponse> _get(
    _Active active,
    Uri url,
    Map<String, String> headers, {
    bool fallback = false,
    bool unauthorized = false,
  }) async {
    final req = http.Request('GET', url)..headers.addAll(headers);
    final res = await active.client.send(req).timeout(requestTimeout);
    if (unauthorized && res.statusCode == 401) {
      await res.stream.drain<void>().timeout(requestTimeout);
      throw _Unauthorized();
    }
    final type = (res.headers['content-type'] ?? '').toLowerCase();
    // Subsonic répond « erreur » par un 200 avec un corps JSON ou XML
    // ou une page HTML (connexion d'un proxy, Cloudflare Access) : seul de l'audio passe
    final bad = res.statusCode >= 400 || !_isAudioType(type);
    if (!bad) return res;
    if (!fallback) {
      await res.stream.drain<void>().timeout(requestTimeout);
      throw _NotAFile(res.statusCode);
    }
    var notFound = res.statusCode == 404 || res.statusCode == 410;
    if (type.contains('json') || type.contains('xml')) {
      // erreur Subsonic 70 : « donnée introuvable »
      final body = String.fromCharCodes(
        (await res.stream.toBytes().timeout(requestTimeout)).take(4096),
      );
      notFound =
          notFound || RegExp(r'"code"\s*:\s*70\b|code="70"').hasMatch(body);
    } else {
      await res.stream.drain<void>().timeout(requestTimeout);
    }
    throw notFound ? _Refusal() : StateError('server refused');
  }

  /// `Artiste/Album/NN Titre.ext`, sans écraser un fichier existant ni un nom déjà donné.
  String _chooseName(Directory root, Track t, String ext) {
    final rel = uniquePath(
      keptPath(
        albumArtist: t.albumArtist.isEmpty ? t.artist : t.albumArtist,
        album: t.album,
        disc: t.disc,
        track: t.trackNo,
        title: t.title,
        ext: ext,
      ),
      (c) =>
          _reserved.contains(c.toLowerCase()) ||
          fileOrPlaceholderExists(p.join(root.path, c)) ||
          File(partialPath(p.join(root.path, c))).existsSync(),
    );
    _reserved.add(rel.toLowerCase());
    return rel;
  }

  /// Titre, artiste, album, numéros et pochette si le fichier n'a ni titre ni pochette.
  /// Jamais fatal : sans tags, le fichier reste tel que le serveur l'a envoyé.
  Future<void> _fillTags(
    String path,
    Track t,
    MusicSource source,
    _Active active,
  ) async {
    try {
      final have = await _reader.read(path);
      if (have != null && (have.title.trim().isNotEmpty || have.hasCover)) {
        return;
      }
      final coverId = t.coverId;
      final cover = coverId == null || coverId.isEmpty
          ? null
          : await remoteCover(source, coverId, 600, client: active.client);
      await _tags.write(
        TagEdit(
          path: path,
          title: t.title,
          artist: t.artist,
          album: t.album,
          trackNo: t.trackNo,
          disc: t.disc,
          cover: cover,
        ),
      );
    } catch (_) {}
  }

  static String? _extOfType(String? type) {
    final t = (type ?? '').split(';').first.trim().toLowerCase();
    return switch (t) {
      'audio/mpeg' || 'audio/mp3' => 'mp3',
      'audio/flac' || 'audio/x-flac' => 'flac',
      'audio/mp4' || 'audio/x-m4a' || 'audio/m4a' => 'm4a',
      'audio/aac' || 'audio/aacp' => 'aac',
      'audio/ogg' || 'application/ogg' => 'ogg',
      'audio/opus' => 'opus',
      'audio/wav' || 'audio/x-wav' || 'audio/wave' => 'wav',
      _ => null,
    };
  }

  Future<void> _drop(File f) async {
    try {
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  void _setProgress(double v) {
    if (v == _progress) return;
    final step = (v * 100).floor() != (_progress * 100).floor();
    _progress = v;
    if (step || v == 0) notifyListeners();
  }

  /// Au lancement : efface les `.part` laissés par une coupure, remet la file en route.
  /// Un start() pendant le balayage attend sa fin (il effacerait le .part du morceau en cours).
  Future<void> resumeAtLaunch() async {
    if (_loop == null && !_moving) {
      _sweeping = true;
      try {
        if (await device.rootReachable()) {
          final root = await device.musicRoot();
          if (await root.exists()) {
            await for (final e in root.list(
              recursive: true,
              followLinks: false,
            )) {
              if (e is File && isPartialName(e.path)) await _drop(e);
            }
          }
        }
      } catch (_) {
        // un dossier illisible n'empêche pas la reprise
      } finally {
        _sweeping = false;
      }
    }
    await syncPlaylists(); // un morceau gagné avant l'arrêt de l'appli
    start();
  }

  /// Retire les copies de [trackPaths] : efface leurs fichiers (sous la racine seulement,
  /// jamais un morceau `local`) puis les lignes. Annule d'abord le téléchargement en cours.
  /// Avec [only], seules les lignes de cette raison sont oubliées (relue au moment même).
  /// [byUser] : c'est l'utilisateur qui retire (« Retirer du téléphone ») ; le Top 100 ne
  /// regarde plus ces morceaux jusqu'à un « Garder » de l'utilisateur.
  /// [block] faux : sans ce blocage (une playlist retirée).
  Future<void> forget(
    List<String> trackPaths, {
    OfflineReason? only,
    bool byUser = false,
    bool block = true,
  }) async {
    try {
      await _forget(trackPaths, only: only, byUser: byUser, block: block);
    } finally {
      await _refreshPlaylists();
    }
  }

  Future<void> _forget(
    List<String> trackPaths, {
    OfflineReason? only,
    bool byUser = false,
    bool block = true,
  }) async {
    final own = [
      for (final t in trackPaths)
        if (parseRemoteKey(t) != null) t,
    ];
    // l'utilisateur retire un morceau : ses jumeaux (le même sur les autres comptes, montrés
    // ou non) partent et sont bloqués aussi (règle Q8)
    final remote = byUser
        ? {...own, for (final t in own) ...await db.twinPaths(t)}.toList()
        : own;
    // le blocage d'abord : un tour du Top 100 entre-temps ne remet pas le morceau en file
    if (byUser && block) await db.blockAutoKeep(remote);
    // retiré par l'utilisateur : plus aucune raison de le garder
    if (byUser) await db.clearOrigins(remote);
    // les lignes d'abord : la boucle ne reprend pas un morceau qu'on oublie
    final taken = await db.takeOffline(remote, reason: only);
    final a = _active;
    if (a != null && taken.containsKey(a.path)) {
      a.cancel();
      await a.done;
    }
    // dossier choisi injoignable : musicRoot() donne le dossier par défaut, où ces chemins
    // désignent peut-être d'autres fichiers. Les lignes sont retirées, aucun fichier effacé.
    if (!await device.rootReachable()) return;
    final root = await device.musicRoot();
    for (final (:rel, :alike) in taken.values) {
      if (rel == null) continue;
      final file = _inside(root, rel);
      if (file == null) continue; // hors de la racine : on n'y touche pas
      // le fichier qu'une autre ligne joue encore reste
      if (_usedByAnother(root, file, alike)) continue;
      await _drop(File(partialPath(file.path)));
      await _drop(File(legacyPartialPath(file.path)));
      await _drop(file);
      await _announce(file.path); // Android : la médiathèque l'oublie
      _pruneEmpty(root, file.parent);
    }
  }

  /// [file] est-il celui d'une des lignes restantes ([alike] : leurs noms, à la casse près) ?
  /// Un dossier qui ignore la casse (iOS, stockage partagé d'Android) n'a qu'un fichier pour
  /// « Art/x » et « art/x » ; un dossier qui la respecte (Linux, stockage de l'appli) en a
  /// deux. Le disque tranche ; dans le doute (une copie mise de côté par iCloud), il reste.
  bool _usedByAnother(Directory root, File file, List<String> alike) {
    for (final rel in alike) {
      final other = _inside(root, rel);
      if (other == null) continue;
      if (p.equals(other.path, file.path)) return true;
      if (!fileOrPlaceholderExists(other.path)) continue; // un autre nom, sans fichier
      if (!file.existsSync() || !other.existsSync()) return true;
      try {
        if (FileSystemEntity.identicalSync(file.path, other.path)) return true;
      } on FileSystemException {
        return true;
      }
    }
    return false;
  }

  Future<void> _announce(String path) async {
    try {
      await device.announce(path);
    } catch (_) {} // la médiathèque du système n'est pas vitale
  }

  /// [rel] sous [root], ou null s'il en sort.
  File? _inside(Directory root, String rel) {
    if (p.isAbsolute(rel)) return null;
    final full = p.normalize(p.join(root.path, rel));
    return p.isWithin(p.normalize(root.path), full) ? File(full) : null;
  }

  /// Enlève les dossiers vides (album, artiste) jusqu'à la racine, jamais elle.
  void _pruneEmpty(Directory root, Directory dir) {
    var d = dir;
    final top = p.normalize(root.path);
    while (p.isWithin(top, p.normalize(d.path))) {
      try {
        if (d.listSync().isNotEmpty) return;
        d.deleteSync();
      } catch (_) {
        return;
      }
      d = d.parent;
    }
  }

  /// Déplace les copies terminées de [from] vers [to] : même chemin relatif (un autre nom
  /// si le fichier existe déjà : ceux de l'utilisateur ne sont jamais écrasés), taille
  /// vérifiée, les lignes réécrites, puis [commit] (qui adopte le dossier :
  /// `device.commitFolder`), puis les originaux sont effacés. Une erreur retire ce qui a
  /// été copié et remet les anciens chemins : l'ancien dossier reste. Une copie qu'iCloud
  /// a mise de côté (`.nom.icloud`) ne peut pas être copiée : le déplacement est refusé.
  /// La file est arrêtée pendant la copie et toujours relancée à la fin.
  Future<KeepResult> moveRoot({
    required Directory from,
    required Directory to,
    Future<void> Function()? commit,
  }) async {
    _moving = true;
    _active?.cancel();
    try {
      await whenIdle();
      // [from] vient de musicRoot() : injoignable, c'est le dossier par défaut, pas celui des copies
      if (!await device.rootReachable()) {
        await _releaseQuietly();
        return const KeepResult.failed();
      }
      final r = await _move(from, to, commit);
      if (!r.ok) await _releaseQuietly();
      return r;
    } catch (_) {
      await _releaseQuietly();
      rethrow;
    } finally {
      _moving = false;
      _reserved.clear();
      start();
    }
  }

  Future<void> _releaseQuietly() async {
    try {
      await device.releaseCandidate();
    } catch (_) {}
  }

  Future<KeepResult> _move(
    Directory from,
    Directory to,
    Future<void> Function()? commit,
  ) async {
    final a = p.normalize(from.path), b = p.normalize(to.path);
    if (a == b) {
      await _releaseQuietly(); // rien à adopter
      return const KeepResult.queued(0, 0);
    }
    if (p.isWithin(a, b) || p.isWithin(b, a)) return const KeepResult.failed();

    final rows = [
      for (final r in (await db.watchOffline().first).values)
        if (r.state == OfflineState.done.name && r.filePath != null) r,
    ];
    final need = rows.fold<int>(0, (s, r) => s + r.size);
    try {
      await to.create(recursive: true);
      final room = await device.freeBytes(to.path) - _freeMargin;
      if (need > room) {
        return KeepResult.tooBig(need - room);
      }
    } catch (_) {
      return const KeepResult.failed();
    }

    final created = <File>[]; // seulement ce que cette copie a créé
    final newRel = <String, String>{}; // trackPath -> chemin relatif dans [to]
    final taken = <String>{};
    var bytes = 0;
    try {
      for (final r in rows) {
        final src = _inside(from, r.filePath!);
        if (src == null) continue;
        if (!await src.exists()) {
          // encore là, mais dans iCloud seulement : ni perdu, ni copiable
          if (fileOrPlaceholderExists(src.path)) {
            throw const FileSystemException('not downloaded');
          }
          continue;
        }
        final rel = uniquePath(
          r.filePath!,
          (c) =>
              taken.contains(c.toLowerCase()) ||
              fileOrPlaceholderExists(p.join(to.path, c)),
        );
        final dst = _inside(to, rel);
        if (dst == null) continue;
        taken.add(rel.toLowerCase());
        await dst.parent.create(recursive: true);
        created.add(dst);
        await src.copy(dst.path);
        if (await dst.length() != await src.length()) {
          throw const FileSystemException('size differs');
        }
        newRel[r.trackPath] = rel;
        bytes += await dst.length();
      }
    } catch (_) {
      await _dropCreated(to, created);
      return const KeepResult.failed();
    }
    // les lignes d'abord, en une transaction, puis le dossier : une ligne ne pointe
    // jamais vers un fichier qui n'est pas le nôtre, et jamais « ok » sans elles
    final oldRel = {
      for (final r in rows)
        if (newRel.containsKey(r.trackPath)) r.trackPath: r.filePath!,
    };
    try {
      await db.applyOfflineMove(newRel, [
        for (final r in rows)
          if (!newRel.containsKey(r.trackPath)) r.trackPath,
      ]);
    } catch (_) {
      await _dropCreated(to, created);
      return const KeepResult.failed();
    }
    try {
      await commit?.call();
    } catch (_) {
      try {
        await db.applyOfflineMove(oldRel, const []); // l'ancien dossier reste
      } catch (_) {}
      await _dropCreated(to, created);
      return const KeepResult.failed();
    }
    for (final r in rows) {
      final rel = newRel[r.trackPath];
      if (rel == null) continue;
      await _announce(p.join(to.path, rel));
      final src = _inside(from, r.filePath!);
      if (src == null) continue;
      await _drop(src);
      await _announce(src.path);
      _pruneEmpty(from, src.parent);
    }
    // nos .m3u8 quittent l'ancien dossier ; réécrits dans le nouveau
    try {
      await playlistFiles.leave(from);
    } catch (_) {}
    await _refreshPlaylists();
    return KeepResult.queued(newRel.length, bytes);
  }

  Future<void> _dropCreated(Directory to, List<File> created) async {
    for (final f in created) {
      await _drop(f);
      _pruneEmpty(to, f.parent);
    }
  }

  /// L'ancien dossier ne répond plus et l'utilisateur en adopte un autre : en une
  /// transaction, chaque copie finie passe en échec sans chemin (à refaire depuis
  /// « À réessayer ») puis [commit] adopte le dossier. Si [commit] échoue, rien ne change.
  /// Rien n'est effacé : l'ancien dossier, s'il revient, garde ses fichiers.
  Future<KeepResult> adoptRoot({
    required Future<void> Function() commit,
  }) async {
    _moving = true;
    _active?.cancel();
    try {
      await whenIdle();
      await db.transaction(() async {
        await db.failDoneCopies();
        await commit();
      });
      // l'ancien dossier ne répond plus : ses .m3u8 y restent, plus à nous
      try {
        await playlistFiles.forgetFiles();
      } catch (_) {}
      return const KeepResult.queued(0, 0);
    } catch (_) {
      await _releaseQuietly();
      return const KeepResult.failed();
    } finally {
      _moving = false;
      _reserved.clear();
      start();
    }
  }
}

/// Le téléchargement en cours : son client (le fermer l'interrompt).
class _Active {
  _Active(this.path, this.client, {required this.auto});
  final String path;
  final bool auto; // copie du Top 100
  final http.Client client;
  bool cancelled = false;
  Future<void> done = Future.value();

  void cancel() {
    cancelled = true;
    client.close();
  }
}
