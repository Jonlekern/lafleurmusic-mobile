import 'dart:async';

import 'package:http/http.dart' as http;

import 'accounts.dart';
import 'plex_link.dart';
import 'remote_key.dart';
import 'secret_store.dart';
import 'source.dart';

/// A Plex Media Server, signed in with a code typed on plex.tv/link (see [PlexLink]).
/// The account keeps the server's id and all its addresses; the source uses the best one that
/// answers (local first, `GET /identity`), chosen again at every [test] (the accounts are
/// tested again when the network changes). Plex tokens don't renew: a 401 means « À
/// reconnecter », and a new code replaces the token in place.
class PlexSource
    implements MusicSource, HttpSource, TypedSource, AuthRenewable {
  PlexSource({
    required this.accountId,
    required this._server,
    required this.clientId,
    Map<String, String> headers = const {},
    http.Client? client,
    this.secrets,
    String? deviceName,
    String? platform,
    this.timeout = requestTimeout,
    this.probeTimeout = plexProbeTimeout,
  }) : _custom = Map.unmodifiable(headers),
       _client = client ?? newServerClient(),
       _deviceName = deviceName ?? defaultPlexDeviceName,
       _platform = platform ?? defaultPlexPlatform;

  /// The server's token (the app never keeps the plex.tv password: there is none).
  static String tokenKey(String id) => 'account.$id.plex.token';

  /// The server's id, name and addresses (JSON of [PlexServer.toJson], no token).
  static String serverKey(String id) => 'account.$id.plex.server';

  @override
  final String accountId;
  final String clientId;
  final SecretStore? secrets;
  final Duration timeout, probeTimeout;
  final PlexServer _server;
  final Map<String, String> _custom;
  final http.Client _client;
  final String _deviceName, _platform;

  String? _token;
  bool _loaded = false;
  Uri? _base;

  @override
  AccountType get accountType => AccountType.plex;

  @override
  http.Client get httpClient => _client;

  /// The address in use (null until [prepare] or [test] found one that answers).
  Uri? get base => _base;

  Map<String, String> _headersWith(String? token) => {
    ..._custom,
    ...plexHeaders(
      clientId: clientId,
      deviceName: _deviceName,
      platform: _platform,
      token: token,
    ),
  };

  /// The account's headers, then Plex's (with the token once loaded). No comma in any of
  /// Plex's values: mpv can send them as they are.
  @override
  Map<String, String> get headers => _headersWith(_token);

  Future<void> _load() async {
    if (_loaded) return;
    _token ??= await secrets?.read(tokenKey(accountId));
    _loaded = true;
  }

  /// Tries every address again, best first; keeps the one that answers (or none).
  Future<Uri?> _pick() async {
    final c = await bestConnection(
      _client,
      _server,
      headers: _headersWith(null),
      timeout: probeTimeout,
    );
    return _base = c?.uri;
  }

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

  static PlexException _relink() => PlexException(
    'Plex refused the token: a new code is needed',
    statusCode: 401,
    tokenRefused: true,
  );

  @override
  Future<TestResult> test() async {
    await _load();
    final token = _token;
    if (token == null) return TestResult.tokenRevoked;
    final base = await _pick();
    if (base == null) return TestResult.unreachable;
    try {
      final req = http.Request('GET', plexUrl(base, 'library/sections'))
        ..followRedirects = false
        ..headers.addAll(_headersWith(token));
      final res = await _send(req);
      return switch (res.statusCode) {
        200 => TestResult.ok,
        401 => TestResult.tokenRevoked,
        403 => TestResult.headerRefused,
        _ => TestResult.unreachable,
      };
    } on SourceNetworkException catch (e) {
      final tls =
          e.kind == 'HandshakeException' ||
          e.kind == 'CertificateException' ||
          e.kind == 'TlsException';
      return tls ? TestResult.certificateRejected : TestResult.unreachable;
    }
  }

  /// Loads the token and finds an address: after this, [headers] carry the token. Throws a
  /// [PlexException] ([PlexException.tokenRefused] when there is no token).
  @override
  Future<void> prepare() async {
    await _load();
    if (_token == null) throw _relink();
    if (_base == null && await _pick() == null) {
      throw PlexException('no address of the server answers');
    }
  }

  /// A Plex token can't be renewed without the user: always refused (« À reconnecter »).
  @override
  Future<void> renewAuth() async => throw _relink();

  // ---- library, playback (tasks 2 and 3) ----------------------------------------------------

  @override
  Stream<List<SourceAlbum>> albums({int pageSize = 500}) =>
      throw UnimplementedError('Plex library: plan 5 task 2');

  @override
  Future<List<SourceSong>> albumSongs(String albumId) =>
      throw UnimplementedError('Plex library: plan 5 task 2');

  @override
  Future<List<SourcePlaylist>> playlists() =>
      throw UnimplementedError('Plex playlists: plan 5 task 2');

  @override
  Uri coverUri(String coverId, int size) =>
      throw UnimplementedError('Plex covers: plan 5 task 2');

  @override
  Uri streamUri(String songId) =>
      throw UnimplementedError('Plex playback: plan 5 task 3');

  @override
  Uri downloadUri(String songId) =>
      throw UnimplementedError('Plex downloads: plan 5 task 3');

  @override
  Future<void> scrobble(String songId, DateTime at) =>
      throw UnimplementedError('Plex listens: plan 5 task 3');

  @override
  void close() => _client.close();
}
