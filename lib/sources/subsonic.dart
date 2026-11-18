import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'source.dart';

/// A Subsonic-level failure (status "failed" or an unusable response).
/// Never carries the password or the token.
class SubsonicException implements Exception {
  SubsonicException(this.message, {this.code});
  final String message;
  final int? code;
  @override
  String toString() => 'SubsonicException(${code ?? '-'}): $message';
}

class SubsonicSource implements MusicSource, HttpSource {
  SubsonicSource({
    required this.accountId,
    required this._base,
    required this._user,
    required this._password,
    Map<String, String> headers = const {},
    http.Client? client,
    String Function()? salt,
    this.timeout = requestTimeout,
  })  : _headers = Map.unmodifiable(headers),
        _client = client ?? newServerClient(),
        _salt = salt ?? _randomSalt;

  /// A request that hasn't fully answered after this fails (a [SourceNetworkException]).
  final Duration timeout;

  @override
  final String accountId;
  final Uri _base;
  final String _user;
  final String _password;
  final Map<String, String> _headers;
  final http.Client _client;
  final String Function() _salt;

  static const _version = '1.16.1';
  static const _clientName = 'LAFLEURMUSIC';

  static String _randomSalt() {
    final r = Random.secure();
    return List.generate(12, (_) => r.nextInt(16).toRadixString(16)).join();
  }

  @override
  Map<String, String> get headers => _headers;

  @override
  http.Client get httpClient => _client;

  Uri _uri(String method, [Map<String, String> params = const {}]) {
    final salt = _salt();
    final token = md5.convert(utf8.encode('$_password$salt')).toString();
    final segs = [
      ..._base.pathSegments.where((s) => s.isNotEmpty),
      'rest',
      '$method.view',
    ];
    return _base.replace(
      pathSegments: segs,
      queryParameters: {
        'u': _user,
        't': token,
        's': salt,
        'v': _version,
        'c': _clientName,
        'f': 'json',
        ...params,
      },
    );
  }

  /// Returns the decoded `subsonic-response`, or null when the body isn't one.
  Map<String, dynamic>? _parse(String body) {
    try {
      final d = jsonDecode(body);
      if (d is Map && d['subsonic-response'] is Map) {
        return Map<String, dynamic>.from(d['subsonic-response'] as Map);
      }
    } on FormatException {
      // not JSON
    }
    return null;
  }

  Future<Map<String, dynamic>> _call(
      String method, Map<String, String> params) async {
    final http.Response res;
    try {
      res = await _client
          .get(_uri(method, params), headers: _headers)
          .timeout(timeout);
    } on Exception catch (e) {
      // never rethrow as is: ClientException.toString prints the URL, token included
      throw SourceNetworkException(e);
    }
    final r = _parse(utf8.decode(res.bodyBytes, allowMalformed: true));
    if (r == null) {
      throw SubsonicException('HTTP ${res.statusCode}: not a Subsonic response');
    }
    if (r['status'] != 'ok') {
      final e = r['error'];
      throw SubsonicException(
        e is Map ? '${e['message'] ?? 'error'}' : 'request failed',
        code: e is Map ? _int(e['code']) : null,
      );
    }
    return r;
  }

  static const _maxRedirects = 3;

  /// Set by [test] when the server sent us from http to https on the same host:
  /// the address to use from now on. Null otherwise.
  Uri? get redirectedBase => _redirectedBase;
  Uri? _redirectedBase;

  static int _portOf(Uri u) => u.hasPort ? u.port : (u.scheme == 'https' ? 443 : 80);

  /// A hop we accept: same host, http or https, never https -> http, and the
  /// port unchanged (or the default https port when upgrading).
  static bool _sameHostHop(Uri from, Uri to) {
    if (to.scheme != 'http' && to.scheme != 'https') return false;
    if (to.host.toLowerCase() != from.host.toLowerCase()) return false;
    if (from.scheme == 'https' && to.scheme == 'http') return false;
    final upgrade = from.scheme == 'http' && to.scheme == 'https';
    return _portOf(to) == _portOf(from) || (upgrade && _portOf(to) == 443);
  }

  @override
  Future<TestResult> test() async {
    _redirectedBase = null;
    final http.Response res;
    try {
      // redirects followed by hand: only to the same host, a proxy sending to
      // its login page is a refused header
      var origin = _base;
      var hops = 0;
      http.Response r;
      while (true) {
        final target = _uri('ping');
        final url = target.replace(
          scheme: origin.scheme,
          host: origin.host,
          port: origin.hasPort ? origin.port : null,
        );
        final req = http.Request('GET', url)
          ..followRedirects = false
          ..headers.addAll(_headers);
        r = await _client
            .send(req)
            .then(http.Response.fromStream)
            .timeout(timeout);
        if (r.statusCode < 300 || r.statusCode >= 400) break;
        final loc = r.headers['location'];
        final next = loc == null ? null : url.resolve(loc);
        if (next == null || hops >= _maxRedirects || !_sameHostHop(url, next)) {
          return TestResult.headerRefused;
        }
        hops++;
        origin = next;
      }
      res = r;
      if (origin.scheme != _base.scheme) {
        _redirectedBase = Uri(
          scheme: origin.scheme,
          host: origin.host,
          port: origin.hasPort ? origin.port : null,
          pathSegments: _base.pathSegments.where((s) => s.isNotEmpty),
        );
      }
    } on TlsException {
      return TestResult.certificateRejected; // HandshakeException, CertificateException
    } on SocketException {
      return TestResult.unreachable;
    } on http.ClientException {
      return TestResult.unreachable;
    } on TimeoutException {
      return TestResult.unreachable;
    }
    if (res.statusCode >= 300 && res.statusCode < 400) {
      return TestResult.headerRefused;
    }
    final r = _parse(utf8.decode(res.bodyBytes, allowMalformed: true));
    if (r == null) {
      if (res.statusCode == 401 || res.statusCode == 403) {
        return TestResult.headerRefused;
      }
      return TestResult.notSubsonic;
    }
    if (r['status'] == 'ok') return TestResult.ok;
    final code = r['error'] is Map ? _int((r['error'] as Map)['code']) : null;
    if (code == 40 || code == 41) return TestResult.wrongPassword;
    return TestResult.notSubsonic;
  }

  @override
  Stream<List<SourceAlbum>> albums({int pageSize = 500}) async* {
    var offset = 0;
    final seen = <String>{};
    while (true) {
      final r = await _call('getAlbumList2', {
        'type': 'alphabeticalByName',
        'size': '$pageSize',
        'offset': '$offset',
      });
      final raw =
          r['albumList2'] is Map ? (r['albumList2'] as Map)['album'] : null;
      final list = raw is List ? raw : const [];
      final page = [
        for (final a in list.whereType<Map>())
          SourceAlbum(
            id: '${a['id']}',
            name: '${a['name'] ?? a['title'] ?? ''}',
            artist: '${a['artist'] ?? ''}',
            coverId: _str(a['coverArt']),
            songCount: _int(a['songCount']) ?? 0,
          ),
      ];
      // only an empty page ends the list: a server may cap the page below pageSize
      if (page.isEmpty) return;
      // a server ignoring the offset sends the same albums again: stop, sync incomplete
      if (page.any((a) => seen.contains(a.id))) {
        throw SubsonicException('album list repeats itself at offset $offset');
      }
      seen.addAll(page.map((a) => a.id));
      yield page;
      offset += list.length;
    }
  }

  @override
  Future<List<SourceSong>> albumSongs(String albumId) async {
    final r = await _call('getAlbum', {'id': albumId});
    final album = r['album'] is Map ? r['album'] as Map : const {};
    final songs = album['song'] is List ? album['song'] as List : const [];
    return [
      for (final s in songs.whereType<Map>())
        () {
          final rg = s['replayGain'] is Map ? s['replayGain'] as Map : null;
          return SourceSong(
            id: '${s['id']}',
            title: '${s['title'] ?? ''}',
            artist: '${s['artist'] ?? ''}',
            album: '${s['album'] ?? album['name'] ?? ''}',
            albumArtist: '${s['albumArtist'] ?? album['artist'] ?? ''}',
            genre: '${s['genre'] ?? ''}',
            track: _int(s['track']),
            disc: _int(s['discNumber']),
            durationMs: ((_num(s['duration']) ?? 0) * 1000).round(),
            size: _int(s['size']) ?? 0,
            coverId: _str(s['coverArt']),
            suffix: _str(s['suffix']),
            replayGainTrack: _num(rg?['trackGain'])?.toDouble(),
            replayGainAlbum: _num(rg?['albumGain'])?.toDouble(),
            playCount: _int(s['playCount']) ?? 0,
          );
        }(),
    ];
  }

  // Servers differ on JSON types (a cover id as a number, a size as a string): read leniently.
  static String? _str(Object? v) => v?.toString();
  static num? _num(Object? v) => v is num ? v : num.tryParse('${v ?? ''}');
  static int? _int(Object? v) => _num(v)?.toInt();

  @override
  void close() => _client.close();

  @override
  Uri streamUri(String songId) => _uri('stream', {'id': songId});

  @override
  Uri coverUri(String coverId, int size) =>
      _uri('getCoverArt', {'id': coverId, 'size': '$size'});

  @override
  Future<void> scrobble(String songId, DateTime at) async {
    await _call('scrobble', {
      'id': songId,
      'time': '${at.millisecondsSinceEpoch}',
      'submission': 'true',
    });
  }
}
