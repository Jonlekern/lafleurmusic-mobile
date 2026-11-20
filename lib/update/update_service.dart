import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../app_version.dart';
import '../settings.dart';

const _releaseUrl =
    'https://api.github.com/repos/Jonlekern/lafleurmusic-mobile/releases/latest';
const _apkName = 'LAFLEURMUSIC-android.apk';
const _ipaName = 'LAFLEURMUSIC-iphone-unsigned.ipa';

/// Une version plus récente publiée sur GitHub.
class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.notes,
    required this.pageUrl,
    this.apkUrl,
    this.apkSize,
    this.apkSha256,
    this.ipaUrl,
  });
  final String version; // sans le « v »
  final List<String> notes; // les puces de « What's new »
  final String pageUrl;
  final String? apkUrl;
  final int? apkSize;
  final String? apkSha256; // hexadécimal, minuscules
  final String? ipaUrl;

  Map<String, Object?> toJson() => {
    'version': version,
    'notes': notes,
    'pageUrl': pageUrl,
    'apkUrl': apkUrl,
    'apkSize': apkSize,
    'apkSha256': apkSha256,
    'ipaUrl': ipaUrl,
  };

  /// null si le JSON n'a pas la bonne forme.
  static UpdateInfo? fromJson(Object? j) {
    try {
      if (j is! Map) return null;
      final v = j['version'], page = j['pageUrl'], notes = j['notes'];
      if (v is! String || page is! String || notes is! List) return null;
      return UpdateInfo(
        version: v,
        notes: [for (final n in notes) n as String],
        pageUrl: page,
        apkUrl: j['apkUrl'] as String?,
        apkSize: j['apkSize'] as int?,
        apkSha256: j['apkSha256'] as String?,
        ipaUrl: j['ipaUrl'] as String?,
      );
    } on Object {
      return null;
    }
  }
}

enum UpdateCheck { newer, upToDate, offline }

/// Annule un téléchargement en cours.
class CancelToken {
  final _done = Completer<void>();
  bool get cancelled => _done.isCompleted;

  /// Se termine à l'annulation (pour interrompre une attente en cours).
  Future<void> get whenCancelled => _done.future;
  void cancel() {
    if (!_done.isCompleted) _done.complete();
  }
}

List<int>? _parts(String v) {
  final m = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)$').firstMatch(v.trim());
  if (m == null) return null;
  return [for (var i = 1; i <= 3; i++) int.parse(m.group(i)!)];
}

/// Vrai si [candidate] est strictement plus grande que [current] (trois nombres).
bool isNewerVersion(String candidate, String current) {
  final a = _parts(candidate), b = _parts(current);
  if (a == null || b == null) return false;
  for (var i = 0; i < 3; i++) {
    if (a[i] != b[i]) return a[i] > b[i];
  }
  return false;
}

/// Les puces de la section « What's new », sans « - » ni « ** » ;
/// à défaut, les premières lignes de texte.
List<String> _notes(String body) {
  final lines = const LineSplitter().convert(body);
  final out = <String>[];
  var inSection = false;
  for (final l in lines) {
    final t = l.trim();
    if (t.startsWith('#')) {
      if (inSection) break;
      inSection = RegExp(
        r"^#+\s*what.?s new",
        caseSensitive: false,
      ).hasMatch(t);
      continue;
    }
    if (inSection && (t.startsWith('- ') || t.startsWith('* '))) {
      out.add(t.substring(2).replaceAll('**', '').trim());
    }
  }
  if (out.isNotEmpty) return out;
  for (final l in lines) {
    final t = l.trim();
    if (t.isEmpty ||
        t.startsWith('#') ||
        t.startsWith('![') ||
        t.startsWith('<')) {
      continue;
    }
    out.add(t.replaceAll('**', ''));
    if (out.length == 3) break;
  }
  return out;
}

UpdateInfo? _parse(Object? json) {
  if (json is! Map) return null;
  final tag = json['tag_name'];
  final url = json['html_url'];
  if (tag is! String || url is! String || _parts(tag) == null) return null;
  String? apkUrl, apkSha, ipaUrl;
  int? apkSize;
  final assets = json['assets'];
  if (assets is List) {
    for (final a in assets) {
      if (a is! Map) continue;
      final dl = a['browser_download_url'];
      if (dl is! String) continue;
      if (a['name'] == _apkName) {
        apkUrl = dl;
        apkSize = a['size'] is int ? a['size'] as int : null;
        final d = a['digest'];
        if (d is String && d.startsWith('sha256:')) {
          apkSha = d.substring(7).toLowerCase();
        }
      } else if (a['name'] == _ipaName) {
        ipaUrl = dl;
      }
    }
  }
  return UpdateInfo(
    version: tag.trim().replaceFirst(RegExp(r'^v'), ''),
    notes: _notes(json['body'] is String ? json['body'] as String : ''),
    pageUrl: url,
    apkUrl: apkUrl,
    apkSize: apkSize,
    apkSha256: apkSha,
    ipaUrl: ipaUrl,
  );
}

/// Cherche une nouvelle version sur GitHub (requête GET anonyme) et télécharge l'APK.
class UpdateService {
  UpdateService({
    required this.client,
    required this.settings,
    required Future<void> Function() saveSettings,
    DateTime Function()? now,
    this.current = appVersion,
    this.transferTimeout = const Duration(seconds: 30),
  }) : _save = saveSettings,
       _now = now ?? DateTime.now;

  final http.Client client;
  final AppSettings settings;
  final Future<void> Function() _save;
  final DateTime Function() _now;
  final String current;

  /// Délai max pour la réponse, puis entre deux morceaux du téléchargement.
  final Duration transferTimeout;

  UpdateInfo? _latest;

  /// La version la plus récente trouvée par la dernière recherche réussie,
  /// même écartée (la feuille des Réglages s'en sert).
  UpdateInfo? get latest => _latest;

  /// La mise à jour à proposer : plus récente et pas écartée.
  final ValueNotifier<UpdateInfo?> available = ValueNotifier(null);

  /// Au lancement : au plus un essai par 24 h, réussi ou non. Silencieux en cas d'échec.
  Future<UpdateInfo?> checkDaily() async {
    final last = settings.lastUpdateCheck;
    final nowMs = _now().millisecondsSinceEpoch;
    // un dernier essai dans le futur (horloge déréglée) compte comme dû
    if (last != null &&
        last <= nowMs &&
        nowMs - last < const Duration(hours: 24).inMilliseconds) {
      if (available.value == null && _latest == null) {
        // après un relancement : la version trouvée la dernière fois
        final saved = UpdateInfo.fromJson(settings.lastFoundUpdate);
        if (saved != null && isNewerVersion(saved.version, current)) {
          _latest = saved;
          _publish(saved);
        }
      }
      return available.value;
    }
    settings.lastUpdateCheck = nowMs;
    try {
      await _save();
    } on Object {
      // pas grave
    }
    final (ok, info) = await _fetch();
    if (ok) {
      _latest = info;
      await _remember(info);
    }
    _publish(info);
    return available.value;
  }

  /// Recherche à la demande (Réglages), sans limite de fréquence.
  Future<UpdateCheck> checkNow() async {
    final (ok, info) = await _fetch();
    if (!ok) return UpdateCheck.offline;
    _latest = info;
    await _remember(info);
    final newer = info != null && isNewerVersion(info.version, current);
    available.value = null;
    _publish(info);
    return newer ? UpdateCheck.newer : UpdateCheck.upToDate;
  }

  Future<void> _remember(UpdateInfo? info) async {
    final newer = info != null && isNewerVersion(info.version, current);
    settings.lastFoundUpdate = newer ? info.toJson() : null;
    try {
      await _save();
    } on Object {
      // pas grave
    }
  }

  void dismiss(UpdateInfo u) {
    settings.dismissedUpdate = u.version;
    available.value = null;
    unawaited(_save().catchError((Object _) {}));
  }

  void _publish(UpdateInfo? info) {
    if (info != null &&
        isNewerVersion(info.version, current) &&
        info.version != settings.dismissedUpdate) {
      available.value = info;
    }
  }

  /// (réponse lisible, release) ; ne lève jamais.
  Future<(bool, UpdateInfo?)> _fetch() async {
    try {
      final r = await client
          .get(
            Uri.parse(_releaseUrl),
            headers: {
              'User-Agent': 'LAFLEURMUSIC/$appVersion',
              'Accept': 'application/vnd.github+json',
            },
          )
          .timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) return (false, null);
      final info = _parse(jsonDecode(utf8.decode(r.bodyBytes)));
      return (info != null, info);
    } on Object {
      return (false, null);
    }
  }

  /// Télécharge l'APK dans `cacheDir/updates/` (fichier temporaire propre à cet appel,
  /// renommé à la fin), vérifie taille et SHA-256 ; en cas d'échec, de silence réseau
  /// de plus de [transferTimeout] ou d'annulation, le fichier est effacé.
  Future<File> downloadApk(
    UpdateInfo u,
    Directory cacheDir, {
    void Function(double)? onProgress,
    CancelToken? cancel,
  }) async {
    final url = u.apkUrl;
    if (url == null) throw StateError('pas d\'APK pour cette version');
    final dir = Directory(p.join(cacheDir.path, 'updates'));
    await dir.create(recursive: true);
    final tmp = File(
      p.join(
        dir.path,
        '$_apkName.${++_seq}.${_now().microsecondsSinceEpoch}.part',
      ),
    );
    final sink = tmp.openWrite();
    var closed = false;
    StreamIterator<List<int>>? it;
    // attend [f] mais s'arrête tout de suite si on annule
    Future<T> guard<T>(Future<T> f) {
      if (cancel == null) return f;
      return Future.any<T>([
        f,
        cancel.whenCancelled.then<T>((_) => throw const _Cancelled()),
      ]);
    }

    try {
      if (cancel?.cancelled ?? false) throw const _Cancelled();
      final req = http.Request('GET', Uri.parse(url))
        ..headers['User-Agent'] = 'LAFLEURMUSIC/$appVersion';
      final resp = await guard(client.send(req).timeout(transferTimeout));
      if (resp.statusCode != 200) {
        throw HttpException('HTTP ${resp.statusCode}');
      }
      final total = u.apkSize ?? resp.contentLength;
      var got = 0;
      it = StreamIterator(resp.stream);
      while (await guard(it.moveNext().timeout(transferTimeout))) {
        final chunk = it.current;
        sink.add(chunk);
        got += chunk.length;
        if (total != null && total > 0) {
          onProgress?.call((got / total).clamp(0.0, 1.0));
        }
      }
      if (cancel?.cancelled ?? false) throw const _Cancelled();
      await sink.close();
      closed = true;
      if (u.apkSize != null && got != u.apkSize) {
        throw const FormatException('taille inattendue');
      }
      final sha = u.apkSha256;
      if (sha != null) {
        final digest = await sha256.bind(tmp.openRead()).first;
        if (digest.toString() != sha.toLowerCase()) {
          throw const FormatException('empreinte inattendue');
        }
      }
      if (cancel?.cancelled ?? false) throw const _Cancelled();
      final file = await tmp.rename(p.join(dir.path, _apkName));
      onProgress?.call(1);
      return file;
    } on Object {
      if (it != null) unawaited(it.cancel().catchError((Object _) {}));
      if (!closed) {
        try {
          await sink.close();
        } on Object {
          // ignoré
        }
      }
      if (await tmp.exists()) await tmp.delete();
      rethrow;
    }
  }

  static int _seq = 0;

  /// Vide `cacheDir/updates/` (au lancement suivant).
  static Future<void> clearDownloads(Directory cacheDir) async {
    final dir = Directory(p.join(cacheDir.path, 'updates'));
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
      await dir.create(recursive: true);
    } on Object {
      // ignoré
    }
  }
}

class _Cancelled implements Exception {
  const _Cancelled();
  @override
  String toString() => 'téléchargement annulé';
}
