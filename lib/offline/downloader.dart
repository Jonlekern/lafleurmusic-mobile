import 'dart:async';
import 'dart:io';

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
import 'paths.dart';

/// Place laissée libre sur le téléphone.
const _freeMargin = 200 * 1024 * 1024;

/// Taille comptée pour un morceau dont le serveur ne dit pas la taille.
const unknownTrackSize = 10 * 1024 * 1024;

/// Réponse de [Downloader.keep] et [Downloader.moveRoot].
class KeepResult {
  const KeepResult.queued(this.count, this.bytes) : ok = true, neededBytes = 0;

  /// Refusé : il manque [neededBytes] (le plus grand écart avec la limite ou la place libre).
  const KeepResult.tooBig(this.neededBytes) : ok = false, count = 0, bytes = 0;

  /// Une erreur au milieu : rien n'a changé.
  const KeepResult.failed() : ok = false, neededBytes = 0, count = 0, bytes = 0;

  final bool ok;
  final int count, bytes, neededBytes;
}

/// Suffixe de nos fichiers en cours : on n'efface jamais les `.part` des autres.
const _partSuffix = '.lafleur.part';

/// Le serveur refuse CE morceau (introuvable, vide, format inconnu) : seul cas compté
/// comme un échec. Tout le reste (réseau, 5xx, 401/403, page de proxy, disque…) arrête
/// la file sans rien compter.
class _Refusal implements Exception {}

/// Une réponse que le serveur n'a pas servie comme fichier (4xx, ou erreur Subsonic en JSON/XML).
class _NotAFile implements Exception {}

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

  /// Les copies `top100` ne partent que si ceci répond vrai (à la maison) ; les `user` toujours.
  /// Quand ça redevient vrai, l'appelant refait [start].
  final bool Function()? mayAutoDownload;

  Future<void>? _loop;
  bool _paused = false;
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

  /// Garde [tracks] : refuse tout si ça dépasse la limite ou la place libre.
  Future<KeepResult> keep(
    List<Track> tracks, {
    OfflineReason reason = OfflineReason.user,
  }) async {
    final remote = [
      for (final t in tracks)
        if (parseRemoteKey(t.path) != null) t,
    ];
    final batch = _albumOrder(remote);
    final fresh = <Track>[]; // ni terminés ni déjà en file
    final toQueue = <Track>[];
    final done = <String>[];
    for (final t in batch) {
      final state = (await db.offlineOf(t.path))?.state;
      if (state == OfflineState.done.name) {
        done.add(t.path);
        continue;
      }
      toQueue.add(t);
      if (state != OfflineState.queued.name) fresh.add(t);
    }
    // une copie déjà faite par le Top 100 devient celle de l'utilisateur : plus jamais retirée toute seule
    await db.queueOffline(done, reason);
    final need = fresh.fold<int>(0, (s, t) => s + _sizeOf(t));
    // la file d'attente déjà promise compte aussi dans la limite
    var backlog = 0;
    for (final r in (await db.watchOffline().first).values) {
      if (r.state != OfflineState.queued.name) continue;
      final t = await db.trackByPath(r.trackPath);
      backlog += t == null ? unknownTrackSize : _sizeOf(t);
    }
    final limit = (await settings()).storageLimitBytes;
    final root = await device.musicRoot();
    final free = await device.freeBytes(root.path) - _freeMargin;
    final over = await db.offlineBytes() + backlog + need - limit;
    if (over > 0 || need > free) {
      final shortfall = over > need - free ? over : need - free;
      return KeepResult.tooBig(shortfall);
    }
    await db.queueOffline([for (final t in toQueue) t.path], reason);
    _accessDenied = false;
    start();
    return KeepResult.queued(fresh.length, need);
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

  void start() {
    _wanted = true;
    _paused = false;
    if (_loop != null || _moving) return;
    _launch();
  }

  void _launch() {
    _wanted = false;
    late final Future<void> f;
    f = _run().whenComplete(() {
      if (identical(_loop, f)) _loop = null;
      // un start() arrivé pendant que la boucle s'arrêtait ne doit pas se perdre
      if (_wanted && !_paused && !_moving && _loop == null) _launch();
    });
    _loop = f;
  }

  /// Sorti de la maison : le morceau du Top 100 en cours est abandonné (il reste en file) ;
  /// un morceau demandé par l'utilisateur continue.
  void cancelAuto() {
    final a = _active;
    if (a != null && a.auto) a.cancel();
  }

  /// Arrête après avoir abandonné le morceau en cours (il reste en file).
  void pause() {
    _paused = true;
    _active?.cancel();
    notifyListeners();
  }

  Future<void> _run() async {
    try {
      while (!_paused && !_moving) {
        final row = await db.nextQueued(
          top100: mayAutoDownload?.call() ?? true,
        );
        if (row == null) break;
        if (await db.trackByPath(row.trackPath) == null) {
          // le morceau a disparu (synchro, compte retiré) : plus rien à copier, ni à compter
          await db.removeOffline([row.trackPath]);
          continue;
        }
        if (!_accessOk) {
          if (!await device.ensureAccess()) {
            _accessDenied = true; // refusé : rien n'est marqué en échec
            notifyListeners();
            break;
          }
          _accessOk = true;
        }
        if (!await _one(row)) break;
      }
    } finally {
      _reserved.clear();
      _setProgress(0);
    }
  }

  /// Faux si la boucle doit s'arrêter (réseau coupé : rien n'est compté, le prochain
  /// start() reprend). Un refus du serveur compte un échec et passe au morceau suivant.
  Future<bool> _one(OfflineRow row) async {
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
      return true;
    } catch (e) {
      if (active.cancelled) return true; // pause ou oubli : pas un échec
      _lastError = _describe(e);
      if (e is! _Refusal) return false;
      await db.markOfflineFailed(row.trackPath);
      await db.sendOfflineToBack(row.trackPath);
      return true;
    } finally {
      active.client.close();
      _active = null;
      _target = null;
      done.complete();
      notifyListeners();
    }
  }

  /// Télécharge le morceau ; renvoie le chemin relatif, null si abandonné.
  Future<String?> _download(OfflineRow row, _Active active) async {
    final key = parseRemoteKey(row.trackPath);
    final t = await db.trackByPath(row.trackPath);
    if (key == null || t == null) throw StateError('unknown track'); // pas un refus du serveur
    final source = await resolver.source(key.$1);
    final root = await device.musicRoot();

    var viaDownload = true;
    http.StreamedResponse res;
    try {
      res = await _get(active, source.downloadUri(key.$2), source.headers);
    } on _NotAFile {
      viaDownload = false;
      res = await _get(
        active,
        source.streamUri(key.$2),
        source.headers,
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
    final part = File('${file.path}$_partSuffix');
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
      await part.rename(file.path);
    } catch (_) {
      try {
        await sink.close();
      } catch (_) {}
      await _drop(part);
      rethrow;
    }

    // fait dès le rangement : une coupure ensuite ne perd pas la copie
    if (await db.offlineOf(row.trackPath) == null) {
      await _drop(file); // oublié pendant le téléchargement
      return null;
    }
    await db.markOfflineDone(row.trackPath, rel, await file.length());
    await _fillTags(file.path, t, source, active);
    try {
      await device.announce(file.path);
    } catch (_) {} // la médiathèque du système n'est pas vitale
    try {
      // les tags changent la taille du fichier
      if (await db.offlineOf(row.trackPath) != null) {
        await db.markOfflineDone(row.trackPath, rel, await file.length());
      }
    } catch (_) {}
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

  Future<http.StreamedResponse> _get(
    _Active active,
    Uri url,
    Map<String, String> headers, {
    bool fallback = false,
  }) async {
    final req = http.Request('GET', url)..headers.addAll(headers);
    final res = await active.client.send(req).timeout(requestTimeout);
    final type = (res.headers['content-type'] ?? '').toLowerCase();
    // Subsonic répond « erreur » par un 200 avec un corps JSON ou XML
    // ou une page HTML (connexion d'un proxy, Cloudflare Access) : seul de l'audio passe
    final bad = res.statusCode >= 400 || !_isAudioType(type);
    if (!bad) return res;
    if (!fallback) {
      await res.stream.drain<void>().timeout(requestTimeout);
      throw _NotAFile();
    }
    var notFound = res.statusCode == 404 || res.statusCode == 410;
    if (type.contains('json') || type.contains('xml')) {
      // erreur Subsonic 70 : « donnée introuvable »
      final body = String.fromCharCodes(
        (await res.stream.toBytes().timeout(requestTimeout)).take(4096),
      );
      notFound =
          notFound ||
          RegExp(r'"code"\s*:\s*70\b|code="70"').hasMatch(body);
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
          File(p.join(root.path, c)).existsSync() ||
          File('${p.join(root.path, c)}$_partSuffix').existsSync(),
    );
    _reserved.add(rel.toLowerCase());
    return rel;
  }

  /// Titre, artiste, album, numéros et pochette si le fichier n'a ni titre ni pochette.
  /// Jamais fatal : le fichier est déjà rangé.
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
  Future<void> resumeAtLaunch() async {
    try {
      if (_loop == null && await device.rootReachable()) {
        final root = await device.musicRoot();
        if (await root.exists()) {
          await for (final e in root.list(
            recursive: true,
            followLinks: false,
          )) {
            if (e is File && e.path.endsWith(_partSuffix)) await _drop(e);
          }
        }
      }
    } catch (_) {} // un dossier illisible n'empêche pas la reprise
    start();
  }

  /// Retire les copies de [trackPaths] : efface leurs fichiers (sous la racine seulement,
  /// jamais un morceau `local`) puis les lignes. Annule d'abord le téléchargement en cours.
  /// Avec [only], seules les lignes de cette raison sont oubliées (relue au moment même).
  Future<void> forget(List<String> trackPaths, {OfflineReason? only}) async {
    final remote = [
      for (final t in trackPaths)
        if (parseRemoteKey(t) != null) t,
    ];
    // les lignes d'abord : la boucle ne reprend pas un morceau qu'on oublie
    final taken = await db.takeOffline(remote, reason: only);
    final rels = [for (final rel in taken.values) ?rel];
    final a = _active;
    if (a != null && taken.containsKey(a.path)) {
      a.cancel();
      await a.done;
    }
    // dossier choisi injoignable : musicRoot() donne le dossier par défaut, où ces chemins
    // désignent peut-être d'autres fichiers. Les lignes sont retirées, aucun fichier effacé.
    if (!await device.rootReachable()) return;
    final root = await device.musicRoot();
    for (final rel in rels) {
      final file = _inside(root, rel);
      if (file == null) continue; // hors de la racine : on n'y touche pas
      await _drop(File('${file.path}$_partSuffix'));
      await _drop(file);
      _pruneEmpty(root, file.parent);
    }
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
  /// vérifiée, puis [commit] (qui adopte le dossier : `device.commitFolder`), puis les
  /// originaux sont effacés. Une erreur retire ce qui a été copié, l'ancien dossier reste.
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
    if (a == b) return const KeepResult.queued(0, 0);
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
        if (src == null || !await src.exists()) continue;
        final rel = uniquePath(
          r.filePath!,
          (c) =>
              taken.contains(c.toLowerCase()) ||
              File(p.join(to.path, c)).existsSync(),
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
      await commit?.call();
    } catch (_) {
      for (final f in created) {
        await _drop(f);
        _pruneEmpty(to, f.parent);
      }
      return const KeepResult.failed();
    }
    // une transaction avant d'effacer quoi que ce soit : une ligne ne pointe jamais
    // vers un fichier qui n'est pas le nôtre
    try {
      await db.applyOfflineMove(newRel, [
        for (final r in rows)
          if (!newRel.containsKey(r.trackPath)) r.trackPath,
      ]);
    } catch (_) {
      return KeepResult.queued(newRel.length, bytes); // originaux gardés
    }
    for (final r in rows) {
      if (!newRel.containsKey(r.trackPath)) continue;
      final src = _inside(from, r.filePath!);
      if (src == null) continue;
      await _drop(src);
      _pruneEmpty(from, src.parent);
    }
    return KeepResult.queued(newRel.length, bytes);
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
