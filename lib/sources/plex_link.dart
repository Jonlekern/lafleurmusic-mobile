import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../app_version.dart';
import 'source.dart';

/// A plex.tv or Plex server failure. Never carries a token nor a request URL.
class PlexException implements Exception {
  PlexException(this.message, {this.statusCode, this.tokenRefused = false});
  final String message;
  final int? statusCode;

  /// plex.tv or the server refused the token (a 401): the account needs a new code.
  final bool tokenRefused;

  @override
  String toString() => 'PlexException(${statusCode ?? '-'}): $message';
}

const plexProduct = 'LAFLEURMUSIC';

/// What every plex.tv and Plex server request carries. No value has a comma: mpv (which
/// sends them with the stream) splits its header option on commas.
Map<String, String> plexHeaders({
  required String clientId,
  required String deviceName,
  required String platform,
  String? token,
}) => {
  'Accept': 'application/json',
  'X-Plex-Product': plexProduct,
  'X-Plex-Client-Identifier': clientId,
  'X-Plex-Version': appVersion,
  'X-Plex-Platform': platform,
  'X-Plex-Device-Name': deviceName,
  'X-Plex-Token': ?token,
};

String get defaultPlexDeviceName => Platform.isIOS ? 'iPhone' : 'Android';
String get defaultPlexPlatform => Platform.isIOS ? 'iOS' : 'Android';

/// A code to type on plex.tv/link.
class PlexPin {
  const PlexPin({
    required this.id,
    required this.code,
    required this.expiresAt,
  });
  final int id;
  final String code;

  /// When plex.tv stops accepting it (by this phone's clock).
  final DateTime expiresAt;
}

/// One address of a Plex server, as plex.tv lists it.
class PlexConnection {
  const PlexConnection({
    required this.uri,
    this.local = false,
    this.relay = false,
    this.ipv6 = false,
  });
  final Uri uri;

  /// On the server's own network (the house).
  final bool local;

  /// Through Plex's relay (slow, capped): the last resort.
  final bool relay;
  final bool ipv6;

  static PlexConnection? fromJson(Object? j) {
    if (j is! Map) return null;
    final u = Uri.tryParse('${j['uri'] ?? ''}');
    if (u == null || u.host.isEmpty) return null;
    if (u.scheme != 'http' && u.scheme != 'https') return null;
    return PlexConnection(
      uri: u,
      local: j['local'] == true,
      relay: j['relay'] == true,
      ipv6: j['IPv6'] == true || j['ipv6'] == true,
    );
  }

  Map<String, Object> toJson() => {
    'uri': uri.toString(),
    'local': local,
    'relay': relay,
    'ipv6': ipv6,
  };
}

/// A Plex Media Server of the account: its id, name and addresses. [accessToken] is the
/// token to talk to it (a shared server has its own); it never goes in [toJson].
class PlexServer {
  const PlexServer({
    required this.machineId,
    required this.name,
    required this.connections,
    this.accessToken,
  });
  final String machineId, name;
  final List<PlexConnection> connections;
  final String? accessToken;

  /// A `resources` entry that provides `server`, else null.
  static PlexServer? fromResource(Map r) {
    final provides = '${r['provides'] ?? ''}'.split(',').map((s) => s.trim());
    if (!provides.contains('server')) return null;
    final id = r['clientIdentifier'];
    if (id is! String || id.isEmpty) return null;
    final conns = r['connections'];
    final token = r['accessToken'];
    return PlexServer(
      machineId: id,
      name: '${r['name'] ?? ''}',
      connections: [
        for (final c in (conns is List ? conns : const []))
          ?PlexConnection.fromJson(c),
      ],
      accessToken: token is String && token.isNotEmpty ? token : null,
    );
  }

  /// What the account keeps (no token).
  Map<String, Object> toJson() => {
    'machineId': machineId,
    'name': name,
    'connections': [for (final c in connections) c.toJson()],
  };

  static PlexServer fromJson(Object? j) {
    final m = j is Map ? j : const {};
    final conns = m['connections'];
    return PlexServer(
      machineId: '${m['machineId'] ?? ''}',
      name: '${m['name'] ?? ''}',
      connections: [
        for (final c in (conns is List ? conns : const []))
          ?PlexConnection.fromJson(c),
      ],
    );
  }
}

/// Local addresses first, then the remote ones, then the relay; IPv4 before IPv6 in each.
List<PlexConnection> orderConnections(List<PlexConnection> all) {
  int rank(PlexConnection c) =>
      (c.relay ? 4 : (c.local ? 0 : 2)) + (c.ipv6 ? 1 : 0);
  final indexed = all.indexed.toList()
    ..sort((a, b) {
      final r = rank(a.$2).compareTo(rank(b.$2));
      return r != 0 ? r : a.$1.compareTo(b.$1);
    });
  return [for (final (_, c) in indexed) c];
}

/// Does [c] answer `GET /identity` as server [machineId]?
Future<bool> _identifies(
  http.Client client,
  PlexConnection c,
  String machineId,
  Map<String, String> headers,
  Duration timeout,
) async {
  try {
    final req = http.Request('GET', _join(c.uri, 'identity'))
      ..followRedirects = false
      ..headers.addAll(headers);
    final res = await client
        .send(req)
        .then(http.Response.fromStream)
        .timeout(timeout);
    if (res.statusCode != 200) return false;
    final body = utf8.decode(res.bodyBytes, allowMalformed: true);
    String? id;
    try {
      final d = jsonDecode(body);
      final mc = d is Map ? d['MediaContainer'] : null;
      if (mc is Map && mc['machineIdentifier'] is String) {
        id = mc['machineIdentifier'] as String;
      }
    } on FormatException {
      // an older server answers XML
      id = RegExp(r'machineIdentifier="([^"]*)"').firstMatch(body)?.group(1);
    }
    return id == machineId;
  } on Object {
    return false;
  }
}

Uri _join(Uri base, String path, [Map<String, String>? query]) => base.replace(
  pathSegments: [
    ...base.pathSegments.where((s) => s.isNotEmpty),
    ...path.split('/').where((s) => s.isNotEmpty),
  ],
  queryParameters: query == null || query.isEmpty ? null : query,
);

/// [base] + [path] (Plex servers sit at the root, a reverse proxy may add a path).
Uri plexUrl(Uri base, String path, [Map<String, String>? query]) =>
    _join(base, path, query);

/// How long one address may take to answer `/identity` (the app's connection rule).
const plexProbeTimeout = connectTimeout;

/// The best address of [server] that answers as that server: local first, then remote, then
/// relay. All are tried at once; the first in that order that answers wins. Null: none.
Future<PlexConnection?> bestConnection(
  http.Client client,
  PlexServer server, {
  Map<String, String> headers = const {},
  Duration timeout = plexProbeTimeout,
}) async {
  final ordered = orderConnections(server.connections);
  final tries = [
    for (final c in ordered)
      _identifies(client, c, server.machineId, headers, timeout),
  ];
  for (final (i, t) in tries.indexed) {
    if (await t) return ordered[i];
  }
  return null;
}

/// Where a server answers and how many music libraries it has (the server choice screen).
class PlexProbe {
  const PlexProbe(this.connection, this.musicLibraries);

  /// Null: no address answers from here.
  final PlexConnection? connection;

  /// Null: unknown (no answer, or the list refused).
  final int? musicLibraries;
}

/// Waiting for a code to be typed on plex.tv/link. [token] gives the account token, or null
/// when the code expired ([expired]) or the wait was cancelled.
class PinWait {
  PinWait._(this._link, this.pin) {
    token = _run();
  }
  final PlexLink _link;
  final PlexPin pin;
  late final Future<String?> token;

  bool _cancelled = false;
  bool _expired = false;
  Timer? _timer;
  Completer<void>? _sleeping;

  bool get expired => _expired;

  /// Stops the polling now (the screen closes, « Nouveau code »): no timer is left.
  void cancel() {
    _cancelled = true;
    _timer?.cancel();
    _timer = null;
    final s = _sleeping;
    _sleeping = null;
    if (s != null && !s.isCompleted) s.complete();
  }

  Future<void> _sleep(Duration d) {
    final c = _sleeping = Completer<void>();
    _timer = Timer(d, () {
      _timer = null;
      if (!c.isCompleted) c.complete();
    });
    return c.future;
  }

  Future<String?> _run() async {
    while (!_cancelled) {
      final left = pin.expiresAt.difference(_link._now());
      if (left <= Duration.zero) {
        _expired = true;
        return null;
      }
      final (gone, t) = await _link._pinToken(pin.id);
      if (_cancelled) return null;
      if (t != null) return t;
      if (gone) {
        _expired = true;
        return null;
      }
      final rest = pin.expiresAt.difference(_link._now());
      if (rest <= Duration.zero) {
        _expired = true;
        return null;
      }
      await _sleep(rest < _link.pollEvery ? rest : _link.pollEvery);
    }
    return null;
  }
}

/// Signing in with a code typed on plex.tv/link (the plex.tv "PIN" flow), then finding the
/// account's servers and their best address. No password ever goes through the app.
class PlexLink {
  PlexLink({
    required this.clientId,
    http.Client? client,
    String? deviceName,
    String? platform,
    DateTime Function()? now,
    this.pollEvery = const Duration(seconds: 2),
    this.timeout = requestTimeout,
    this.probeTimeout = plexProbeTimeout,
  }) : _client = client ?? newServerClient(),
       deviceName = deviceName ?? defaultPlexDeviceName,
       platform = platform ?? defaultPlexPlatform,
       _now = now ?? DateTime.now;

  static final plexTv = Uri.parse('https://plex.tv');

  final String clientId, deviceName, platform;
  final http.Client _client;
  final DateTime Function() _now;
  final Duration pollEvery, timeout, probeTimeout;

  http.Client get httpClient => _client;

  Map<String, String> _headers([String? token]) => plexHeaders(
    clientId: clientId,
    deviceName: deviceName,
    platform: platform,
    token: token,
  );

  Future<http.Response> _send(
    String method,
    Uri url,
    Map<String, String> headers,
  ) async {
    try {
      final req = http.Request(method, url)..headers.addAll(headers);
      return await _client
          .send(req)
          .then(http.Response.fromStream)
          .timeout(timeout);
    } on Exception catch (e) {
      // never e.toString(): a ClientException prints the URL
      throw PlexException(SourceNetworkException(e).message);
    }
  }

  static Object? _json(http.Response r) {
    try {
      return jsonDecode(utf8.decode(r.bodyBytes, allowMalformed: true));
    } on FormatException {
      return null;
    }
  }

  /// `POST https://plex.tv/api/v2/pins?strong=false`: a short code (4 characters).
  Future<PlexPin> requestPin() async {
    final res = await _send(
      'POST',
      plexTv.replace(
        path: '/api/v2/pins',
        queryParameters: {'strong': 'false'},
      ),
      _headers(),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw PlexException('code refused', statusCode: res.statusCode);
    }
    final raw = _json(res);
    final d = raw is Map ? raw : const {};
    final id = d['id'];
    final code = d['code'];
    if (id is! int || code is! String || code.isEmpty) {
      throw PlexException('not a plex.tv code answer');
    }
    // its lifetime from now (this phone's clock may differ from plex.tv's)
    final inSec = d['expiresIn'];
    final at = DateTime.tryParse('${d['expiresAt'] ?? ''}');
    final expiresAt = inSec is num && inSec > 0
        ? _now().add(Duration(seconds: inSec.toInt()))
        : (at ?? _now().add(const Duration(minutes: 15)));
    return PlexPin(id: id, code: code, expiresAt: expiresAt);
  }

  /// (plex.tv forgot the code, token if it was typed). A network failure is "not yet".
  Future<(bool, String?)> _pinToken(int id) async {
    try {
      final res = await _send(
        'GET',
        plexTv.replace(path: '/api/v2/pins/$id'),
        _headers(),
      );
      if (res.statusCode == 404) return (true, null);
      if (res.statusCode != 200) return (false, null);
      final d = _json(res);
      final t = d is Map ? d['authToken'] : null;
      return (false, t is String && t.isNotEmpty ? t : null);
    } on PlexException {
      return (false, null);
    }
  }

  /// `GET https://plex.tv/api/v2/pins/{id}` every [pollEvery] until the code is typed or expires.
  PinWait poll(PlexPin pin) => PinWait._(this, pin);

  /// `GET https://plex.tv/api/v2/user`: who [token] belongs to (its `uuid`). A new code for
  /// an account must come from the same Plex account.
  Future<String> user(String token) async {
    final res = await _send(
      'GET',
      plexTv.replace(path: '/api/v2/user'),
      _headers(token),
    );
    if (res.statusCode == 401) {
      throw PlexException(
        'plex.tv refused the token',
        statusCode: 401,
        tokenRefused: true,
      );
    }
    if (res.statusCode != 200) {
      throw PlexException('user refused', statusCode: res.statusCode);
    }
    final d = _json(res);
    final uuid = d is Map ? d['uuid'] : null;
    if (uuid is String && uuid.isNotEmpty) return uuid;
    final id = d is Map ? d['id'] : null;
    if (id is int) return '$id';
    throw PlexException('not a plex.tv user answer');
  }

  /// `GET https://plex.tv/api/v2/resources?includeHttps=1&includeRelay=1`: the servers only.
  Future<List<PlexServer>> servers(String token) async {
    final res = await _send(
      'GET',
      plexTv.replace(
        path: '/api/v2/resources',
        queryParameters: {'includeHttps': '1', 'includeRelay': '1'},
      ),
      _headers(token),
    );
    if (res.statusCode == 401) {
      throw PlexException(
        'plex.tv refused the token',
        statusCode: 401,
        tokenRefused: true,
      );
    }
    if (res.statusCode != 200) {
      throw PlexException('servers refused', statusCode: res.statusCode);
    }
    final d = _json(res);
    if (d is! List) throw PlexException('not a plex.tv servers answer');
    return [for (final r in d.whereType<Map>()) ?PlexServer.fromResource(r)];
  }

  /// Where [server] answers from here, and its music libraries (`/library/sections`, type
  /// `artist`). [token]: the account token, when the server has none of its own.
  Future<PlexProbe> probe(PlexServer server, {String? token}) async {
    final c = await bestConnection(
      _client,
      server,
      headers: _headers(),
      timeout: probeTimeout,
    );
    if (c == null) return const PlexProbe(null, null);
    try {
      final res = await _send(
        'GET',
        plexUrl(c.uri, 'library/sections'),
        _headers(server.accessToken ?? token),
      );
      if (res.statusCode != 200) return PlexProbe(c, null);
      final d = _json(res);
      final mc = d is Map ? d['MediaContainer'] : null;
      final dirs = mc is Map ? mc['Directory'] : null;
      if (dirs is! List) return PlexProbe(c, 0);
      return PlexProbe(
        c,
        [
          for (final s in dirs.whereType<Map>())
            if (s['type'] == 'artist') s,
        ].length,
      );
    } on PlexException {
      return PlexProbe(c, null);
    }
  }

  void close() => _client.close();
}
