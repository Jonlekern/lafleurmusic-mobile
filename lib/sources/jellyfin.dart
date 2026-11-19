import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../app_version.dart';
import '../library/models.dart' show unknownAlbumName;
import 'accounts.dart';
import 'remote_key.dart';
import 'secret_store.dart';
import 'source.dart';

/// A Jellyfin-level failure. Never carries the password or the token.
class JellyfinException implements Exception {
  JellyfinException(
    this.message, {
    this.statusCode,
    this.wrongPassword = false,
  });
  final String message;
  final int? statusCode;

  /// The server refused the name or password (a 401 on sign-in).
  final bool wrongPassword;
  @override
  String toString() => 'JellyfinException(${statusCode ?? '-'}): $message';
}

/// A Jellyfin server (REST). Signs in once with name and password, keeps the access token in
/// the [SecretStore] under the account id, and signs in again once when the server refuses
/// the token (revoked, expired) with the password the account already holds.
class JellyfinSource
    implements MusicSource, HttpSource, TypedSource, AuthRenewable {
  JellyfinSource({
    required this.accountId,
    required Uri base,
    required this._user,
    required this._password,
    Map<String, String> headers = const {},
    http.Client? client,
    this.secrets,
    String? deviceName,
    this.timeout = requestTimeout,
  }) : _root = base,
       _custom = Map.unmodifiable(headers),
       _client = client ?? newServerClient(),
       _deviceName = deviceName ?? (Platform.isIOS ? 'iPhone' : 'Android'),
       _deviceId = sha1
           .convert(utf8.encode('lafleurmusic:$accountId'))
           .toString()
           .substring(0, 32);

  /// Sent as `Version` in the Authorization header (the app's own version).
  static const clientVersion = appVersion;
  static const _clientName = 'LAFLEURMUSIC';

  /// Where the access token and the user id are kept (the password stays with the account's
  /// own entry, see [Accounts]: sign-in again needs it).
  static String tokenKey(String id) => 'account.$id.jellyfin.token';
  static String userIdKey(String id) => 'account.$id.jellyfin.userId';

  /// A request that hasn't fully answered after this fails (a [SourceNetworkException]).
  final Duration timeout;

  /// Null for a throw-away source (the form's "Tester"): nothing is written.
  final SecretStore? secrets;

  @override
  final String accountId;
  Uri _root;
  final String _user;
  final String _password;
  final Map<String, String> _custom;
  final http.Client _client;
  final String _deviceName, _deviceId;

  String? _token, _userId;
  bool _loaded = false;
  bool _closed = false;
  Future<String>? _signingIn;

  @override
  AccountType get accountType => AccountType.jellyfin;

  @override
  http.Client get httpClient => _client;

  /// Set by [test] when the server sent us from http to https on the same host.
  Uri? get redirectedBase => _redirectedBase;
  Uri? _redirectedBase;

  /// The signed-in user's id (after a sign-in or once the stored one is read).
  String? get userId => _userId;

  bool get _customHasAuthorization =>
      _custom.keys.any((k) => k.toLowerCase() == 'authorization');

  String _authValue(String? token) =>
      'MediaBrowser Client="$_clientName", Device="$_deviceName", '
      'DeviceId="$_deviceId", Version="$clientVersion"'
      '${token == null ? '' : ', Token="$token"'}';

  /// The account's headers plus ours. A proxy's own `Authorization` is kept: ours then goes
  /// in `X-Emby-Authorization`, which Jellyfin reads the same way.
  Map<String, String> _headersWith(String? token) => {
    ..._custom,
    _customHasAuthorization ? 'X-Emby-Authorization' : 'Authorization':
        _authValue(token),
  };

  @override
  Map<String, String> get headers => _headersWith(_token);

  Uri _url(String path, [Map<String, String>? query]) => _root.replace(
    pathSegments: [
      ..._root.pathSegments.where((s) => s.isNotEmpty),
      ...path.split('/').where((s) => s.isNotEmpty),
    ],
    queryParameters: query == null || query.isEmpty ? null : query,
  );

  Future<http.Response> _send(http.Request req) async {
    try {
      return await _client
          .send(req)
          .then(http.Response.fromStream)
          .timeout(timeout);
    } on Exception catch (e) {
      // never rethrow as is: ClientException.toString prints the URL
      throw SourceNetworkException(e);
    }
  }

  http.Request _req(String method, Uri url, String? token) =>
      http.Request(method, url)
        ..followRedirects = false
        ..headers.addAll(_headersWith(token));

  // ---- sign-in -------------------------------------------------------------------------

  /// Signs in with name and password; stores the token. Throws [JellyfinException]
  /// ([JellyfinException.wrongPassword] on 401).
  Future<String> _signIn() async {
    final req = _req('POST', _url('Users/AuthenticateByName'), null)
      ..headers['Content-Type'] = 'application/json; charset=utf-8'
      ..body = jsonEncode({'Username': _user, 'Pw': _password});
    final res = await _send(req);
    if (res.statusCode == 401) {
      throw JellyfinException(
        'wrong name or password',
        statusCode: 401,
        wrongPassword: true,
      );
    }
    if (res.statusCode != 200) {
      throw JellyfinException('sign-in refused', statusCode: res.statusCode);
    }
    String? token, id;
    try {
      final d = jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
      if (d is Map) {
        token = d['AccessToken'] is String ? d['AccessToken'] as String : null;
        final u = d['User'];
        id = u is Map && u['Id'] is String ? u['Id'] as String : null;
      }
    } on FormatException {
      // not JSON
    }
    if (token == null || token.isEmpty || id == null) {
      throw JellyfinException('not a Jellyfin sign-in answer');
    }
    if (_closed) throw JellyfinException('source closed');
    _token = token;
    _userId = id;
    _loaded = true;
    final s = secrets;
    if (s != null) {
      await s.write(tokenKey(accountId), token);
      await s.write(userIdKey(accountId), id);
    }
    return token;
  }

  Future<void> _forgetToken(String? failed) async {
    // another request may already have signed in again: keep its token
    if (_token != failed) return;
    _token = null;
    _userId = null;
    final s = secrets;
    if (s == null) return;
    for (final k in [tokenKey(accountId), userIdKey(accountId)]) {
      try {
        await s.delete(k);
      } catch (_) {}
    }
  }

  Future<void> _load() async {
    if (_loaded) return;
    final s = secrets;
    if (s != null) {
      _token ??= await s.read(tokenKey(accountId));
      _userId ??= await s.read(userIdKey(accountId));
    }
    _loaded = true;
  }

  /// One sign-in at a time: callers that met a 401 together wait for the same one.
  Future<String> _reSignIn(String? stale) {
    final t = _token;
    // someone just refreshed it
    if (t != null && t != stale) return Future.value(t);
    return _signingIn ??= _signIn().whenComplete(() => _signingIn = null);
  }

  /// GET [path] (relative to the server's address) with the token. A 401 signs in again once
  /// with the account's password and repeats the request; a second 401 throws a
  /// [JellyfinException] with [JellyfinException.wrongPassword] and forgets the token.
  Future<http.Response> authedGet(String path, [Map<String, String>? query]) =>
      _authed(() => _url(path, query), 'GET');

  Future<http.Response> _authed(Uri Function() url, String method) async {
    await _load();
    var token = _token ?? await _reSignIn(null);
    var res = await _send(_req(method, url(), token));
    if (res.statusCode != 401) return res;
    try {
      token = await _reSignIn(token);
    } on JellyfinException catch (e) {
      if (e.wrongPassword) await _forgetToken(token);
      rethrow;
    }
    res = await _send(_req(method, url(), token));
    if (res.statusCode == 401) {
      await _forgetToken(token);
      throw JellyfinException(
        'wrong name or password',
        statusCode: 401,
        wrongPassword: true,
      );
    }
    return res;
  }

  // ---- Tester --------------------------------------------------------------------------

  static const _maxRedirects = 3;

  /// `GET /System/Info/Public`, redirects followed by hand: only to the same host, a proxy
  /// sending to its login page is a refused header.
  Future<http.Response?> _publicInfo() async {
    var hops = 0;
    while (true) {
      final url = _url('System/Info/Public');
      final r = await _send(_req('GET', url, null));
      if (r.statusCode < 300 || r.statusCode >= 400) return r;
      final loc = r.headers['location'];
      final next = loc == null ? null : url.resolve(loc);
      if (next == null || hops >= _maxRedirects || !sameHostHop(url, next)) {
        return null;
      }
      hops++;
      if (next.scheme != _root.scheme) {
        _root = Uri(
          scheme: next.scheme,
          host: next.host,
          port: next.hasPort ? next.port : null,
          pathSegments: _root.pathSegments.where((s) => s.isNotEmpty),
        );
        _redirectedBase = _root;
      }
    }
  }

  @override
  Future<TestResult> test() async {
    _redirectedBase = null;
    try {
      final info = await _publicInfo();
      if (info == null) return TestResult.headerRefused;
      final code = info.statusCode;
      if (code == 401 || code == 403) return TestResult.headerRefused;
      if (code == 502 || code == 503 || code == 504) {
        return TestResult.unreachable;
      }
      if (code != 200 || !_isJellyfin(info)) return TestResult.notJellyfin;
      try {
        await _signIn();
        return TestResult.ok;
      } on JellyfinException catch (e) {
        if (e.wrongPassword) return TestResult.wrongPassword;
        final c = e.statusCode;
        if (c == 403 || (c != null && c >= 300 && c < 400)) {
          return TestResult.headerRefused;
        }
        if (c != null && c >= 500) return TestResult.unreachable;
        return TestResult.notJellyfin;
      }
    } on SourceNetworkException catch (e) {
      return _isTls(e)
          ? TestResult.certificateRejected
          : TestResult.unreachable;
    }
  }

  static bool _isTls(SourceNetworkException e) =>
      e.kind == 'HandshakeException' ||
      e.kind == 'CertificateException' ||
      e.kind == 'TlsException';

  static bool _isJellyfin(http.Response r) {
    try {
      final d = jsonDecode(utf8.decode(r.bodyBytes, allowMalformed: true));
      return d is Map &&
          d['ProductName'] is String &&
          (d['ProductName'] as String).toLowerCase().contains('jellyfin');
    } on FormatException {
      return false;
    }
  }

  // ---- library ---------------------------------------------------------------------------

  static const _loosePrefix = 'loose:';

  /// Songs outside any album, by `loose:<artist>`; filled when [albums] reaches its end.
  Map<String, List<SourceSong>>? _loose;

  Future<String> _uid() async {
    await _load();
    var id = _userId;
    if (id == null) {
      await (_signingIn ??= _signIn().whenComplete(() => _signingIn = null));
      id = _userId;
    }
    if (id == null) throw JellyfinException('no user id');
    return id;
  }

  Map<String, dynamic> _decode(http.Response r) {
    if (r.statusCode != 200) {
      throw JellyfinException('request refused', statusCode: r.statusCode);
    }
    try {
      final d = jsonDecode(utf8.decode(r.bodyBytes, allowMalformed: true));
      if (d is Map<String, dynamic>) return d;
    } on FormatException {
      // not JSON
    }
    throw JellyfinException('not a Jellyfin answer');
  }

  /// The `Items` of [path], one page at a time. [repeatCheck]: a server ignoring the offset
  /// sends the same items again, which fails the run (a playlist may list a song twice: off).
  Stream<List<Map>> _pages(
    String path,
    Map<String, String> query, {
    int pageSize = 500,
    bool repeatCheck = true,
  }) async* {
    var start = 0;
    final seen = <String>{};
    while (true) {
      final d = _decode(
        await authedGet(path, {
          ...query,
          'StartIndex': '$start',
          'Limit': '$pageSize',
        }),
      );
      final raw = d['Items'];
      final items = [if (raw is List) ...raw.whereType<Map>()];
      if (items.isEmpty) return;
      if (repeatCheck) {
        final ids = [
          for (final i in items)
            if (i['Id'] != null) '${i['Id']}',
        ];
        if (ids.any(seen.contains)) {
          throw JellyfinException('list repeats itself at offset $start');
        }
        seen.addAll(ids);
      }
      yield items;
      start += items.length;
      final total = d['TotalRecordCount'];
      if (total is int) {
        if (start >= total) return;
      } else if (!repeatCheck) {
        return; // no total: can't tell a repeat from a long list
      }
    }
  }

  /// The ids of the music views (`CollectionType` music). Several is fine, none is empty.
  Future<List<String>> _musicViews(String uid) async {
    final d = _decode(await authedGet('Users/$uid/Views'));
    final items = d['Items'];
    return [
      for (final v in (items is List ? items : const []).whereType<Map>())
        if (v['Id'] != null &&
            '${v['CollectionType']}'.toLowerCase() == 'music')
          '${v['Id']}',
    ];
  }

  static const _albumFields = 'ChildCount,Genres';
  static const _songFields = 'MediaSources,Genres';

  @override
  Stream<List<SourceAlbum>> albums({int pageSize = 500}) async* {
    _loose = null;
    final uid = await _uid();
    final views = await _musicViews(uid);
    final seen = <String>{}; // an album in two views counts once
    for (final view in views) {
      await for (final items in _pages('Users/$uid/Items', {
        'ParentId': view,
        'IncludeItemTypes': 'MusicAlbum',
        'Recursive': 'true',
        'SortBy': 'SortName',
        'Fields': _albumFields,
      }, pageSize: pageSize)) {
        final page = [
          for (final a in items)
            if (a['Id'] != null && seen.add('${a['Id']}'))
              SourceAlbum(
                id: '${a['Id']}',
                name: '${a['Name'] ?? ''}',
                artist: _albumArtist(a),
                coverId: _hasPrimary(a) ? '${a['Id']}' : null,
                songCount: _int(a['ChildCount']) ?? 0,
              ),
        ];
        if (page.isNotEmpty) yield page;
      }
    }
    // songs outside any album would never be listed by their album: one more album each artist
    final loose = await _looseSongs(uid, views, pageSize);
    _loose = loose;
    if (loose.isNotEmpty) {
      yield [
        for (final e in loose.entries)
          SourceAlbum(
            id: e.key,
            name: unknownAlbumName,
            artist: e.value.first.albumArtist,
            coverId: e.value
                .map((s) => s.coverId)
                .firstWhere((c) => c != null, orElse: () => null),
            songCount: e.value.length,
          ),
      ];
    }
  }

  /// Songs outside any album. The scan over every song is lean (no media sources, genres or
  /// pictures: just what tells a loose song); only the loose ones are then fetched in full.
  Future<Map<String, List<SourceSong>>> _looseSongs(
    String uid,
    List<String> views,
    int pageSize,
  ) async {
    final loose = <String>[];
    final seen = <String>{};
    for (final view in views) {
      await for (final items in _pages('Users/$uid/Items', {
        'ParentId': view,
        'IncludeItemTypes': 'Audio',
        'Recursive': 'true',
        'SortBy': 'SortName',
        'EnableUserData': 'false',
        'EnableImages': 'false',
      }, pageSize: pageSize)) {
        for (final m in items) {
          final album = m['AlbumId'];
          if (album != null && '$album'.isNotEmpty) continue;
          if (m['Id'] != null && seen.add('${m['Id']}')) {
            loose.add('${m['Id']}');
          }
        }
      }
    }
    final out = <String, List<SourceSong>>{};
    for (var i = 0; i < loose.length; i += _idsBatch) {
      final batch = loose.sublist(i, min(i + _idsBatch, loose.length));
      final d = _decode(
        await authedGet('Users/$uid/Items', {
          'Ids': batch.join(','),
          'Fields': _songFields,
        }),
      );
      final items = d['Items'];
      for (final m in (items is List ? items : const []).whereType<Map>()) {
        if (m['Id'] == null) continue;
        final artist = _albumArtist(m, fallbackToArtists: true);
        out
            .putIfAbsent('$_loosePrefix$artist', () => [])
            .add(_song(m, unknownAlbumName, artist));
      }
    }
    return out;
  }

  /// Ids per request (they travel in the URL).
  static const _idsBatch = 100;

  @override
  Future<List<SourceSong>> albumSongs(String albumId) async {
    if (albumId.startsWith(_loosePrefix)) {
      final uid = await _uid();
      final loose = _loose ??= await _looseSongs(
        uid,
        await _musicViews(uid),
        500,
      );
      return loose[albumId] ?? const [];
    }
    final uid = await _uid();
    final songs = <SourceSong>[];
    await for (final items in _pages('Users/$uid/Items', {
      'ParentId': albumId,
      'IncludeItemTypes': 'Audio',
      'SortBy': 'ParentIndexNumber,IndexNumber',
      'Fields': _songFields,
    })) {
      for (final m in items) {
        if (m['Id'] != null) songs.add(_song(m, '${m['Album'] ?? ''}', null));
      }
    }
    return songs;
  }

  SourceSong _song(Map m, String album, String? albumArtist) {
    final src =
        m['MediaSources'] is List && (m['MediaSources'] as List).isNotEmpty
        ? (m['MediaSources'] as List).first
        : null;
    final media = src is Map ? src : const {};
    final artists = [
      for (final a in (m['Artists'] is List ? m['Artists'] as List : const []))
        if ('$a'.isNotEmpty) '$a',
    ];
    final genres = [
      for (final g in (m['Genres'] is List ? m['Genres'] as List : const []))
        if ('$g'.isNotEmpty) '$g',
    ];
    final ud = m['UserData'] is Map ? m['UserData'] as Map : const {};
    final id = '${m['Id']}';
    final ticks = _num(m['RunTimeTicks']);
    return SourceSong(
      id: id,
      title: '${m['Name'] ?? ''}',
      artist: artists.isNotEmpty
          ? artists.join(', ')
          : '${m['AlbumArtist'] ?? ''}',
      album: album,
      albumArtist: albumArtist ?? _albumArtist(m),
      genre: genres.join(', '),
      track: _int(m['IndexNumber']),
      disc: _int(m['ParentIndexNumber']),
      durationMs: ticks == null ? 0 : (ticks / 10000).round(), // 100 ns ticks
      size: _int(media['Size']) ?? 0,
      coverId: _hasPrimary(m)
          ? id
          : (m['AlbumId'] != null && m['AlbumPrimaryImageTag'] != null
                ? '${m['AlbumId']}'
                : null),
      suffix: _suffix(media),
      replayGainTrack: _num(m['NormalizationGain'])?.toDouble(), // dB
      playCount: _int(ud['PlayCount']) ?? 0,
    );
  }

  static String _albumArtist(Map m, {bool fallbackToArtists = false}) {
    final aa = m['AlbumArtist'];
    if (aa != null && '$aa'.isNotEmpty) return '$aa';
    final list = m['AlbumArtists'];
    if (list is List && list.isNotEmpty && list.first is Map) {
      final n = (list.first as Map)['Name'];
      if (n != null && '$n'.isNotEmpty) return '$n';
    }
    if (fallbackToArtists) {
      final a = m['Artists'];
      if (a is List && a.isNotEmpty && '${a.first}'.isNotEmpty) {
        return '${a.first}';
      }
    }
    return '';
  }

  static bool _hasPrimary(Map m) {
    final t = m['ImageTags'];
    return t is Map && t['Primary'] != null;
  }

  /// `Container` of the first media source; a list ("mov,mp4,m4a") falls back on the file's extension.
  static String? _suffix(Map media) {
    final c = media['Container'];
    if (c is! String || c.isEmpty) return null;
    if (!c.contains(',')) return c.toLowerCase();
    final path = media['Path'];
    if (path is String) {
      final dot = path.lastIndexOf('.');
      if (dot >= 0 &&
          dot < path.length - 1 &&
          !path.substring(dot).contains('/')) {
        return path.substring(dot + 1).toLowerCase();
      }
    }
    return c.split(',').first.toLowerCase();
  }

  static num? _num(Object? v) => v is num ? v : num.tryParse('${v ?? ''}');
  static int? _int(Object? v) => _num(v)?.toInt();

  @override
  Future<List<SourcePlaylist>> playlists() async {
    final uid = await _uid();
    final heads = <(String, String)>[];
    await for (final items in _pages('Users/$uid/Items', {
      'IncludeItemTypes': 'Playlist',
      'Recursive': 'true',
    })) {
      for (final p in items) {
        if (p['Id'] != null) heads.add(('${p['Id']}', '${p['Name'] ?? ''}'));
      }
    }
    return [
      for (final (id, name) in heads)
        SourcePlaylist(
          id: id,
          name: name,
          songIds: await _playlistSongs(uid, id),
        ),
    ];
  }

  /// Null when this playlist won't read (the others still do).
  Future<List<String>?> _playlistSongs(String uid, String id) async {
    final ids = <String>[];
    try {
      await for (final items in _pages('Playlists/$id/Items', {
        'UserId': uid,
      }, repeatCheck: false)) {
        for (final m in items) {
          if (m['Id'] != null) ids.add('${m['Id']}');
        }
      }
    } on JellyfinException {
      return null;
    }
    return ids;
  }

  /// GET [url] (a full address, e.g. a cover's) with the token; signs in again on a 401.
  Future<http.Response> authedGetUri(Uri url) => _authed(() => url, 'GET');

  @override
  Uri coverUri(String coverId, int size) => _url(
    'Items/$coverId/Images/Primary',
    {'maxWidth': '$size', 'quality': '90'},
  );

  // ---- playback, downloads, listens ---------------------------------------------------------

  /// Loads the stored token, or signs in when there is none: after this, [headers] and
  /// [streamUri] carry a token. Callers that read them synchronously (the resolver, the
  /// downloader) wait for it first.
  @override
  Future<void> prepare() async {
    await _load();
    if (_token == null || _userId == null) {
      await (_signingIn ??= _signIn().whenComplete(() => _signingIn = null));
    }
  }

  /// The server refused the token: signs in again, once, with the account's password. Throws
  /// a [JellyfinException] ([JellyfinException.wrongPassword]) when the password is refused too.
  @override
  Future<void> renewAuth() async {
    await _load();
    final stale = _token;
    try {
      await _reSignIn(stale);
    } on JellyfinException catch (e) {
      if (e.wrongPassword) await _forgetToken(stale);
      rethrow;
    }
  }

  /// The audio stream. mpv may not send custom headers after a redirect, so the token also
  /// travels as `api_key`: this address is never shown, logged nor stored (see [prepare]).
  @override
  Uri streamUri(String songId) {
    final token = _token, uid = _userId;
    if (token == null || uid == null) {
      throw StateError('Jellyfin source not signed in');
    }
    return _url('Audio/$songId/universal', {
      'UserId': uid,
      'Container': 'flac,mp3,m4a,ogg,opus,wav',
      'TranscodingContainer': 'mp3',
      'AudioCodec': 'mp3',
      'api_key': token,
    });
  }

  /// The original file; the token goes in [headers] only.
  @override
  Uri downloadUri(String songId) => _url('Items/$songId/Download');

  /// Marks the song played at [at] (its original date, so a listen sent later keeps it).
  /// A 404 (the server no longer has the song) is a [JellyfinException] with that code.
  @override
  Future<void> scrobble(String songId, DateTime at) async {
    final uid = await _uid();
    final res = await _authed(
      () => _url('Users/$uid/PlayedItems/$songId', {
        'DatePlayed': at.toUtc().toIso8601String(),
      }),
      'POST',
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw JellyfinException('listen refused', statusCode: res.statusCode);
    }
  }

  @override
  void close() {
    _closed = true;
    _client.close();
  }
}
