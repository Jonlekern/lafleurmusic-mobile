import 'dart:async';
import 'dart:convert';

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
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now,
       _custom = Map.unmodifiable(headers),
       _client = client ?? newServerClient(),
       _deviceName = deviceName ?? defaultPlexDeviceName,
       _platform = platform ?? defaultPlexPlatform;

  /// The server's token (the app never keeps the plex.tv password: there is none).
  static String tokenKey(String id) => 'account.$id.plex.token';

  /// The server's id, name and addresses (JSON of [PlexServer.toJson], no token).
  static String serverKey(String id) => 'account.$id.plex.server';

  /// The plex.tv account token: only to read the server's addresses again from plex.tv when
  /// none of the saved ones answers. Never sent to the media server.
  static String accountTokenKey(String id) => 'account.$id.plex.accountToken';

  /// Who the account is on plex.tv (`uuid`): a new code must come from the same one.
  static String userKey(String id) => 'account.$id.plex.user';

  /// After a read of the addresses from plex.tv that found none answering, plex.tv is not
  /// asked again for this long (per account: sources are rebuilt often).
  static const refreshCooldown = Duration(minutes: 10);
  static final _cooldownUntil = <String, DateTime>{};
  static final _refreshingNow = <String, Future<void>>{};

  /// The network changed (home / away): plex.tv may be asked again at once.
  static void resetRefreshCooldowns() => _cooldownUntil.clear();

  /// The background read of the addresses from plex.tv running for this account, if any.
  Future<void>? get refreshing => _refreshingNow[accountId];

  final DateTime Function() _now;

  @override
  final String accountId;
  final String clientId;
  final SecretStore? secrets;
  final Duration timeout, probeTimeout;
  PlexServer _server;
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
  /// One round of probes (all addresses at once, [probeTimeout] at most). None answers:
  /// the addresses may be stale (a new public IP), so plex.tv is asked for the new ones in
  /// the background; this call doesn't wait for it (a check must stay short), the next one
  /// uses what it found.
  Future<Uri?> _pick() async {
    final c = await bestConnection(
      _client,
      _server,
      headers: _headersWith(null),
      timeout: probeTimeout,
    );
    if (c == null) _startRefresh();
    return _base = c?.uri;
  }

  void _startRefresh() {
    if (_refreshingNow.containsKey(accountId)) return;
    final until = _cooldownUntil[accountId];
    if (until != null && _now().isBefore(until)) return;
    late final Future<void> f;
    f = _refresh().whenComplete(() {
      if (identical(_refreshingNow[accountId], f)) {
        _refreshingNow.remove(accountId);
      }
    });
    _refreshingNow[accountId] = f;
  }

  Future<void> _refresh() async {
    var answers = false;
    try {
      if (await _refreshConnections()) {
        final c = await bestConnection(
          _client,
          _server,
          headers: _headersWith(null),
          timeout: probeTimeout,
        );
        if (c != null) _base = c.uri;
        answers = c != null;
      }
    } on Object {
      answers = false;
    }
    if (answers) {
      _cooldownUntil.remove(accountId);
    } else {
      _cooldownUntil[accountId] = _now().add(refreshCooldown);
    }
  }

  static bool _sameConnections(List<PlexConnection> a, List<PlexConnection> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].uri != b[i].uri ||
          a[i].local != b[i].local ||
          a[i].relay != b[i].relay) {
        return false;
      }
    }
    return true;
  }

  /// Reads this server's addresses from plex.tv (`/api/v2/resources`, with the plex.tv
  /// token, which goes to plex.tv only). True when the list changed (then saved). Any
  /// failure (no token kept, plex.tv down, server gone) is false: the account stays absent.
  Future<bool> _refreshConnections() async {
    try {
      final accountToken = await secrets?.read(accountTokenKey(accountId));
      if (accountToken == null || accountToken.isEmpty) return false;
      final link = PlexLink(
        clientId: clientId,
        client: _client, // shared: never closed here
        deviceName: _deviceName,
        platform: _platform,
        timeout: timeout,
      );
      final fresh = (await link.servers(accountToken))
          .where((s) => s.machineId == _server.machineId)
          .firstOrNull;
      if (fresh == null ||
          fresh.connections.isEmpty ||
          _sameConnections(fresh.connections, _server.connections)) {
        return false;
      }
      _server = PlexServer(
        machineId: _server.machineId,
        name: fresh.name.isNotEmpty ? fresh.name : _server.name,
        connections: fresh.connections,
      );
      try {
        await secrets?.write(
          serverKey(accountId),
          jsonEncode(_server.toJson()),
        );
      } on Object {
        // kept in memory; the next refresh writes it again
      }
      return true;
    } on Object {
      return false;
    }
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
