import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

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
class JellyfinSource implements MusicSource, HttpSource, TypedSource {
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
  static const clientVersion = '0.3.0';
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

  Future<void> _forgetToken() async {
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
      if (e.wrongPassword) await _forgetToken();
      rethrow;
    }
    res = await _send(_req(method, url(), token));
    if (res.statusCode == 401) {
      await _forgetToken();
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

  // ---- the rest comes with the library (tasks 2 and 3) -----------------------------------

  @override
  Stream<List<SourceAlbum>> albums({int pageSize = 500}) =>
      throw UnimplementedError('Jellyfin library: task 2');

  @override
  Future<List<SourceSong>> albumSongs(String albumId) =>
      throw UnimplementedError('Jellyfin library: task 2');

  @override
  Future<List<SourcePlaylist>> playlists() =>
      throw UnimplementedError('Jellyfin library: task 2');

  @override
  Uri coverUri(String coverId, int size) =>
      throw UnimplementedError('Jellyfin covers: task 2');

  @override
  Uri streamUri(String songId) =>
      throw UnimplementedError('Jellyfin playback: task 3');

  @override
  Uri downloadUri(String songId) =>
      throw UnimplementedError('Jellyfin downloads: task 3');

  @override
  Future<void> scrobble(String songId, DateTime at) =>
      throw UnimplementedError('Jellyfin listens: task 3');

  @override
  void close() => _client.close();
}
