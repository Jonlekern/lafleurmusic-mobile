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

class SubsonicSource implements MusicSource {
  SubsonicSource({
    required this.accountId,
    required this._base,
    required this._user,
    required this._password,
    Map<String, String> headers = const {},
    http.Client? client,
    String Function()? salt,
  })  : _headers = Map.unmodifiable(headers),
        _client = client ?? http.Client(),
        _salt = salt ?? _randomSalt;

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
      res = await _client.get(_uri(method, params), headers: _headers);
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
        code: e is Map ? (e['code'] as num?)?.toInt() : null,
      );
    }
    return r;
  }

  @override
  Future<TestResult> test() async {
    final http.Response res;
    try {
      res = await _client.get(_uri('ping'), headers: _headers);
    } on SocketException {
      return TestResult.unreachable;
    } on http.ClientException {
      return TestResult.unreachable;
    } on TimeoutException {
      return TestResult.unreachable;
    } on HandshakeException {
      return TestResult.unreachable;
    }
    final r = _parse(utf8.decode(res.bodyBytes, allowMalformed: true));
    if (r == null) {
      if (res.statusCode == 401 || res.statusCode == 403) {
        return TestResult.headerRefused;
      }
      return TestResult.notSubsonic;
    }
    if (r['status'] == 'ok') return TestResult.ok;
    final code = r['error'] is Map ? (r['error'] as Map)['code'] : null;
    if (code == 40 || code == 41) return TestResult.wrongPassword;
    return TestResult.notSubsonic;
  }

  @override
  Stream<List<SourceAlbum>> albums({int pageSize = 500}) async* {
    var offset = 0;
    while (true) {
      final r = await _call('getAlbumList2', {
        'type': 'alphabeticalByName',
        'size': '$pageSize',
        'offset': '$offset',
      });
      final list = (r['albumList2'] is Map
              ? (r['albumList2'] as Map)['album']
              : null) as List? ??
          const [];
      final page = [
        for (final a in list.cast<Map>())
          SourceAlbum(
            id: '${a['id']}',
            name: '${a['name'] ?? a['title'] ?? ''}',
            artist: '${a['artist'] ?? ''}',
            coverId: a['coverArt'] as String?,
            songCount: (a['songCount'] as num?)?.toInt() ?? 0,
          ),
      ];
      if (page.isNotEmpty) yield page;
      if (list.length < pageSize) return;
      offset += pageSize;
    }
  }

  @override
  Future<List<SourceSong>> albumSongs(String albumId) async {
    final r = await _call('getAlbum', {'id': albumId});
    final album = r['album'] as Map? ?? const {};
    final songs = album['song'] as List? ?? const [];
    return [
      for (final s in songs.cast<Map>())
        () {
          final rg = s['replayGain'] as Map?;
          return SourceSong(
            id: '${s['id']}',
            title: '${s['title'] ?? ''}',
            artist: '${s['artist'] ?? ''}',
            album: '${s['album'] ?? album['name'] ?? ''}',
            albumArtist: '${s['albumArtist'] ?? album['artist'] ?? ''}',
            genre: '${s['genre'] ?? ''}',
            track: (s['track'] as num?)?.toInt(),
            disc: (s['discNumber'] as num?)?.toInt(),
            durationMs: (((s['duration'] as num?) ?? 0) * 1000).round(),
            size: (s['size'] as num?)?.toInt() ?? 0,
            coverId: s['coverArt'] as String?,
            suffix: s['suffix'] as String?,
            replayGainTrack: (rg?['trackGain'] as num?)?.toDouble(),
            replayGainAlbum: (rg?['albumGain'] as num?)?.toDouble(),
            playCount: (s['playCount'] as num?)?.toInt() ?? 0,
          );
        }(),
    ];
  }

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
