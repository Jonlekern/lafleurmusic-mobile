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
  SubsonicException(this.message, {this.code, this.httpStatus});
  final String message;
  final int? code;

  /// The HTTP status when the answer was not a Subsonic one (a proxy's 403, a 502…).
  final int? httpStatus;
  @override
  String toString() => 'SubsonicException(${code ?? '-'}): $message';
}

class SubsonicSource
    implements MusicSource, HttpSource, PlaylistWriter, PlaylistOrderWriter {
  SubsonicSource({
    required this.accountId,
    required this._base,
    required this._user,
    required this._password,
    Map<String, String> headers = const {},
    http.Client? client,
    String Function()? salt,
    this.timeout = requestTimeout,
  }) : _headers = Map.unmodifiable(headers),
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

  /// [params] values: a String, or a list of them (the name repeated, e.g. `songId`).
  Uri _uri(String method, [Map<String, Object> params = const {}]) {
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

  /// [post]: the parameters go in a form body (OpenSubsonic `formPost`), only the sign-in
  /// ones stay in the address.
  Future<Map<String, dynamic>> _call(
    String method,
    Map<String, Object> params, {
    bool post = false,
  }) async {
    final http.Response res;
    try {
      res = post
          ? await _client
                .post(
                  _uri(method),
                  headers: {
                    ..._headers,
                    'Content-Type':
                        'application/x-www-form-urlencoded; charset=utf-8',
                  },
                  body: Uri(queryParameters: params).query,
                )
                .timeout(timeout)
          : await _client
                .get(_uri(method, params), headers: _headers)
                .timeout(timeout);
    } on Exception catch (e) {
      // never rethrow as is: ClientException.toString prints the URL, token included
      throw SourceNetworkException(e);
    }
    final r = _parse(utf8.decode(res.bodyBytes, allowMalformed: true));
    if (r == null) {
      throw SubsonicException(
        'HTTP ${res.statusCode}: not a Subsonic response',
        httpStatus: res.statusCode,
      );
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
        // built whole: Uri.replace(port: null) would keep the old port
        final url = Uri(
          scheme: origin.scheme,
          host: origin.host,
          port: origin.hasPort ? origin.port : null,
          path: target.path,
          query: target.query,
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
        if (next == null || hops >= _maxRedirects || !sameHostHop(url, next)) {
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
      return TestResult
          .certificateRejected; // HandshakeException, CertificateException
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
      final raw = r['albumList2'] is Map
          ? (r['albumList2'] as Map)['album']
          : null;
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

  @override
  Future<List<SourcePlaylist>> playlists() async {
    final r = await _call('getPlaylists', const {});
    final raw = r['playlists'] is Map
        ? (r['playlists'] as Map)['playlist']
        : null;
    final heads = [
      for (final p in (raw is List ? raw : const []).whereType<Map>())
        if (p['id'] != null) ('${p['id']}', '${p['name'] ?? ''}', _editable(p)),
    ];
    return [
      for (final (id, name, editable) in heads)
        SourcePlaylist(
          id: id,
          name: name,
          songIds: await _playlistSongs(id),
          editable: editable,
        ),
    ];
  }

  /// Another user's playlist (`owner`), or one the server marks `readonly` (OpenSubsonic),
  /// can't be changed by this account.
  bool _editable(Map p) {
    if (p['readonly'] == true) return false;
    final owner = p['owner'];
    return owner == null || '$owner'.toLowerCase() == _user.toLowerCase();
  }

  /// Null when this playlist won't read (the others still do).
  Future<List<String>?> _playlistSongs(String id) async {
    try {
      return (await readPlaylist(id)).songIds;
    } on SubsonicException {
      return null;
    }
  }

  // ---- writing playlists (plan 9) ----------------------------------------------------------

  /// The longest address sent: a proxy's default limit for a request line is often 8 KB
  /// (nginx), so a list that makes it longer goes in a form POST, or in slices.
  static const maxUrlLength = 6000;

  bool? _formPostKnown;

  /// The server takes parameters in a form body (OpenSubsonic `formPost`, Navidrome 0.52+).
  /// Asked once per source; a network failure is not remembered.
  Future<bool> _formPost() async {
    final known = _formPostKnown;
    if (known != null) return known;
    bool ok;
    try {
      final r = await _call('getOpenSubsonicExtensions', const {});
      final list = r['openSubsonicExtensions'];
      ok =
          list is List &&
          list.whereType<Map>().any((e) => e['name'] == 'formPost');
    } on SubsonicException catch (e) {
      // not a Subsonic answer (a proxy's error page): not remembered, asked again next time
      if (e.httpStatus != null) return false;
      ok = false; // a Subsonic error: not OpenSubsonic
    }
    return _formPostKnown = ok;
  }

  /// A write: error 50 (not allowed), 30 (server too old) or an HTTP 403 is a
  /// [PlaylistWriteRefused].
  Future<Map<String, dynamic>> _write(
    String method,
    Map<String, Object> params, {
    bool post = false,
  }) async {
    try {
      return await _call(method, params, post: post);
    } on SubsonicException catch (e) {
      if (e.code == 50 || e.code == 30 || e.httpStatus == 403) {
        throw PlaylistWriteRefused('Subsonic ${e.code ?? e.httpStatus}');
      }
      rethrow;
    }
  }

  bool _fits(String method, Map<String, Object> params) =>
      _uri(method, params).toString().length <= maxUrlLength;

  /// [method] with [params] plus [key] = each of [values]: one GET while the address stays
  /// short, else one form POST when the server takes it, else (only when [split]) several
  /// GETs of consecutive slices, in order; not splittable: [PlaylistTooLong], nothing sent.
  Future<Map<String, dynamic>?> _writeList(
    String method,
    Map<String, String> params,
    String key,
    List<String> values, {
    required bool split,
  }) async {
    final whole = {...params, key: values};
    if (_fits(method, whole)) return _write(method, whole);
    if (await _formPost()) return _write(method, whole, post: true);
    if (!split) throw PlaylistTooLong(values.length);
    final room = maxUrlLength - _uri(method, params).toString().length;
    var i = 0;
    while (i < values.length) {
      var used = 0, end = i;
      while (end < values.length) {
        final cost =
            key.length + 2 + Uri.encodeQueryComponent(values[end]).length;
        if (end > i && used + cost > room) break;
        used += cost;
        end++;
      }
      await _write(method, {...params, key: values.sublist(i, end)});
      i = end;
    }
    return null;
  }

  @override
  Future<String> createPlaylist(
    String name, {
    List<String> songIds = const [],
  }) async {
    final r = await _write('createPlaylist', {'name': name});
    final p = r['playlist'];
    final String id;
    if (p is Map && p['id'] != null) {
      id = '${p['id']}';
    } else {
      id = await _newestNamed(name);
    }
    // the songs after: added in slices when many (createPlaylist can't be split)
    try {
      await addToPlaylist(id, songIds);
    } on Exception catch (e) {
      throw PlaylistCreatedPartly(id, name, e);
    }
    return id;
  }

  /// Subsonic before 1.14 answers a creation with nothing: the newest playlist with that
  /// name (by `created`, the server's own clock) is the new one; without dates, the last.
  Future<String> _newestNamed(String name) async {
    final all = await _call('getPlaylists', const {});
    final raw = all['playlists'] is Map
        ? (all['playlists'] as Map)['playlist']
        : null;
    final same = [
      for (final l in (raw is List ? raw : const []).whereType<Map>())
        if (l['id'] != null && '${l['name']}' == name)
          ('${l['id']}', DateTime.tryParse('${l['created'] ?? ''}')),
    ];
    if (same.isEmpty) throw SubsonicException('created playlist not found');
    if (same.every((l) => l.$2 != null)) {
      same.sort((a, b) => a.$2!.compareTo(b.$2!));
    }
    return same.last.$1;
  }

  @override
  Future<void> addToPlaylist(String id, List<String> songIds) async {
    if (songIds.isEmpty) return;
    await _writeList(
      'updatePlaylist',
      {'playlistId': id},
      'songIdToAdd',
      songIds,
      split: true,
    );
  }

  @override
  Future<void> removeFromPlaylist(
    String id,
    List<int> positions, {
    List<String>? expected,
  }) async {
    if (expected != null) {
      checkPlaylistRows((await readPlaylist(id)).songIds!, positions, expected);
    }
    // the last ones first: a slice never moves the positions of the next one
    final sorted = positions.toSet().toList()..sort((a, b) => b - a);
    if (sorted.isEmpty) return;
    await _writeList(
      'updatePlaylist',
      {'playlistId': id},
      'songIndexToRemove',
      [for (final p in sorted) '$p'],
      split: true,
    );
  }

  /// `updatePlaylist` can't move: the whole list is written again in its new order
  /// (`createPlaylist?playlistId=…&songId=…`), in one request, never in parts.
  @override
  Future<void> movePlaylistItem(
    String id,
    int from,
    int to, {
    String? expected,
  }) async {
    final ids = [...(await readPlaylist(id)).songIds!];
    checkPlaylistRows(ids, [from, to], expected == null ? null : [expected]);
    if (from == to) return;
    ids.insert(to, ids.removeAt(from));
    await _writeList(
      'createPlaylist',
      {'playlistId': id},
      'songId',
      ids,
      split: false,
    );
  }

  /// The whole list written again in its new order (`createPlaylist?playlistId=…`), in one
  /// request (or one form POST), never in parts.
  @override
  Future<void> setOrder(
    String id,
    List<String> songIds, {
    List<String>? expected,
  }) async {
    final now = (await readPlaylist(id)).songIds!;
    if (expected != null && !_sameList(now, expected)) throw PlaylistChanged();
    await _writeList(
      'createPlaylist',
      {'playlistId': id},
      'songId',
      songIds,
      split: false,
    );
  }

  static bool _sameList(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  Future<void> renamePlaylist(String id, String name) async {
    await _write('updatePlaylist', {'playlistId': id, 'name': name});
  }

  @override
  Future<void> deletePlaylist(String id) async {
    await _write('deletePlaylist', {'id': id});
  }

  @override
  Future<SourcePlaylist> readPlaylist(String id) async {
    final r = await _call('getPlaylist', {'id': id});
    final p = r['playlist'] is Map ? r['playlist'] as Map : const {};
    final entries = p['entry'] is List ? p['entry'] as List : const [];
    return SourcePlaylist(
      id: id,
      name: '${p['name'] ?? ''}',
      editable: _editable(p),
      songIds: [
        for (final e in entries.whereType<Map>())
          if (e['id'] != null) '${e['id']}',
      ],
    );
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
  Uri downloadUri(String songId) => _uri('download', {'id': songId});

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
