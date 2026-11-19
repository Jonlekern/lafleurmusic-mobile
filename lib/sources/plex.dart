import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../library/models.dart' show unknownAlbumName;
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
    implements
        MusicSource,
        HttpSource,
        TypedSource,
        AuthRenewable,
        SongResolving,
        PlaylistWriter {
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
    this._partsMax = 20000,
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

  /// A new code was just accepted for this account: plex.tv may be asked again at once.
  static void resetRefreshCooldown(String accountId) =>
      _cooldownUntil.remove(accountId);

  /// The account was removed: its cooldown and its running refresh are forgotten (the
  /// refresh, still running, then writes nothing and leaves no cooldown behind).
  static void forgetAccount(String accountId) {
    _forgotten.add(accountId);
    _cooldownUntil.remove(accountId);
    _refreshingNow.remove(accountId);
  }

  /// Removed accounts: no source of theirs reads plex.tv or writes their secrets any more.
  static final _forgotten = <String>{};

  /// An account with this id exists (again): its sources may refresh.
  static void accountAdded(String accountId) => _forgotten.remove(accountId);

  /// Clears every static state (tests).
  static void resetStateForTests() {
    _cooldownUntil.clear();
    _refreshingNow.clear();
    _forgotten.clear();
    onTokenRefused = null;
  }

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
  bool _closed = false;
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
  /// Callers meeting a round already running wait for that same round.
  Future<Uri?> _pick() => _picking ??= _pickRound().whenComplete(() {
    _picking = null;
  });

  Future<Uri?>? _picking;

  /// After a round where nothing answered, [prepare] doesn't probe again for this long.
  static const pickRetryAfter = Duration(seconds: 5);
  DateTime? _pickFailedAt;

  Future<Uri?> _pickRound() async {
    final c = await bestConnection(
      _client,
      _server,
      headers: _headersWith(null),
      timeout: probeTimeout,
    );
    if (c == null) {
      _pickFailedAt = _now();
      _startRefresh();
    } else {
      _pickFailedAt = null;
    }
    return _base = c?.uri;
  }

  void _startRefresh() {
    if (_forgotten.contains(accountId) || _closed) return;
    if (_refreshingNow.containsKey(accountId)) return;
    final until = _cooldownUntil[accountId];
    if (until != null && _now().isBefore(until)) return;
    late final Future<void> f;
    bool current() => identical(_refreshingNow[accountId], f);
    f = _refresh(current).whenComplete(() {
      if (current()) _refreshingNow.remove(accountId);
    });
    _refreshingNow[accountId] = f;
  }

  /// [current]: false once the account was removed ([forgetAccount]) meanwhile.
  Future<void> _refresh(bool Function() current) async {
    var answers = false;
    try {
      if (await _refreshConnections(current)) {
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
    // cut by close() (the source is rebuilt) or the account removed: not a real "nobody answers"
    if (!current() || _closed) return;
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
  Future<bool> _refreshConnections(bool Function() current) async {
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
      if (_closed || _forgotten.contains(accountId) || !current()) {
        return false; // the account is gone: write nothing
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
      if (_forgotten.contains(accountId) || !current()) {
        // removed while writing: the secret must not outlive the account
        try {
          await secrets?.delete(serverKey(accountId));
        } on Object {
          // nothing more to do
        }
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

  /// Called with the account's id whenever the server refuses its token (a 401, or no token):
  /// the accounts screen then shows « À reconnecter » at once. Set by the account service.
  static void Function(String accountId)? onTokenRefused;

  PlexException _relink() {
    onTokenRefused?.call(accountId);
    return _refusedToken();
  }

  static PlexException _refusedToken() => PlexException(
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
    if (_base == null) {
      final failed = _pickFailedAt;
      final recent =
          failed != null && _now().difference(failed) < pickRetryAfter;
      if (recent || await _pick() == null) {
        throw PlexException('no address of the server answers');
      }
    }
  }

  /// A Plex token can't be renewed without the user: always refused (« À reconnecter »).
  @override
  Future<void> renewAuth() async => throw _relink();

  // ---- library, playback (tasks 2 and 3) ----------------------------------------------------

  /// GET [path] on the server in use; anything but a 200 throws.
  Future<http.Response> _getRaw(
    String path,
    Map<String, String>? query, {
    int? start,
    int? size,
  }) async {
    await prepare();
    final base = _base;
    if (base == null) throw PlexException('no address of the server answers');
    final req = http.Request('GET', plexUrl(base, path, query))
      ..followRedirects = false
      ..headers.addAll(headers);
    if (start != null) req.headers['X-Plex-Container-Start'] = '$start';
    if (size != null) req.headers['X-Plex-Container-Size'] = '$size';
    final res = await _send(req);
    if (res.statusCode == 401) throw _relink();
    if (res.statusCode != 200) {
      throw PlexException('request refused', statusCode: res.statusCode);
    }
    return res;
  }

  /// GET [path] on the server in use, JSON back. A 401 is « À reconnecter »; another
  /// refusal is a [PlexException] with its code. [start]/[size]: one page.
  Future<Map> _get(
    String path, {
    Map<String, String>? query,
    int? start,
    int? size,
  }) async {
    final res = await _getRaw(path, query, start: start, size: size);
    try {
      final d = jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
      final mc = d is Map ? d['MediaContainer'] : null;
      if (mc is Map) return mc;
    } on FormatException {
      // not JSON
    }
    throw PlexException('not a Plex answer');
  }

  /// The `Metadata` of [path], one page at a time. [repeatCheck]: a server ignoring the
  /// offset sends the same items again, which fails the run (a playlist may list a song
  /// twice: off).
  Stream<List<Map>> _pages(
    String path, {
    Map<String, String>? query,
    int pageSize = 500,
    bool repeatCheck = true,
  }) async* {
    var start = 0;
    final seen = <String>{};
    while (true) {
      final d = await _get(path, query: query, start: start, size: pageSize);
      final raw = d['Metadata'];
      final items = [if (raw is List) ...raw.whereType<Map>()];
      if (items.isEmpty) return;
      if (repeatCheck) {
        final ids = [
          for (final i in items)
            if (i['ratingKey'] != null) '${i['ratingKey']}',
        ];
        if (ids.any(seen.contains)) {
          throw PlexException('list repeats itself at offset $start');
        }
        seen.addAll(ids);
      }
      yield items;
      start += items.length;
      final total = _int(d['totalSize']);
      if (total != null) {
        if (start >= total) return;
      } else if (!repeatCheck || items.length < pageSize) {
        return; // no total: a short page is the end (a repeat can't be told from a long list)
      }
    }
  }

  /// The ids of the music libraries (`type` artist). Several is fine, none is empty.
  Future<List<String>> _musicSections() async {
    final d = await _get('library/sections');
    final dirs = d['Directory'];
    return [
      for (final s in (dirs is List ? dirs : const []).whereType<Map>())
        if (s['type'] == 'artist' && s['key'] != null) '${s['key']}',
    ];
  }

  @override
  Stream<List<SourceAlbum>> albums({int pageSize = 500}) async* {
    final seen = <String>{}; // an album in two libraries counts once
    for (final section in await _musicSections()) {
      await for (final items in _pages(
        'library/sections/$section/all',
        query: {'type': '9'},
        pageSize: pageSize,
      )) {
        final page = [
          for (final a in items)
            if (a['ratingKey'] != null && seen.add('${a['ratingKey']}'))
              SourceAlbum(
                id: '${a['ratingKey']}',
                name: _albumName(a['title']),
                artist: _str(a['parentTitle']),
                coverId: _str(a['thumb']).isEmpty ? null : _str(a['thumb']),
                songCount: _int(a['leafCount']) ?? 0,
              ),
        ];
        if (page.isNotEmpty) yield page;
      }
    }
  }

  /// Plex names the album of tracks without one `[Unknown Album]`; an empty title is the same.
  static String _albumName(Object? title) {
    final t = _str(title);
    return t.isEmpty || t == '[Unknown Album]' ? unknownAlbumName : t;
  }

  @override
  Future<List<SourceSong>> albumSongs(String albumId) async {
    final songs = <SourceSong>[];
    await for (final items in _pages('library/metadata/$albumId/children')) {
      for (final m in items) {
        if (m['ratingKey'] != null) songs.add(_song(m));
      }
    }
    return songs;
  }

  /// The first `Part` of the first `Media` of a track (a track with several keeps the first).
  static Map? _firstPart(Map m) {
    final media = m['Media'] is List && (m['Media'] as List).isNotEmpty
        ? (m['Media'] as List).first
        : null;
    final part =
        media is Map &&
            media['Part'] is List &&
            (media['Part'] as List).isNotEmpty
        ? (media['Part'] as List).first
        : null;
    return part is Map ? part : null;
  }

  SourceSong _song(Map m) {
    final media = m['Media'] is List && (m['Media'] as List).isNotEmpty
        ? (m['Media'] as List).first
        : null;
    final part = _firstPart(m);
    final p = part is Map ? part : const {};
    // the artist of the album's artist node: the album's own artist, never the track's
    final albumArtist = _str(m['grandparentTitle']);
    final original = _str(m['originalTitle']);
    final thumb = _str(m['parentThumb']).isNotEmpty
        ? _str(m['parentThumb'])
        : _str(m['thumb']);
    final genres = m['Genre'] is List
        ? [
            for (final g in (m['Genre'] as List).whereType<Map>())
              if (_str(g['tag']).isNotEmpty) _str(g['tag']),
          ]
        : const <String>[];
    return SourceSong(
      id: '${m['ratingKey']}',
      title: _str(m['title']),
      artist: original.isNotEmpty ? original : _str(m['grandparentTitle']),
      album: _albumName(m['parentTitle']),
      albumArtist: albumArtist,
      genre: genres.join(', '),
      track: _int(m['index']),
      disc: _int(m['parentIndex']),
      durationMs: _int(m['duration']) ?? 0, // already in ms
      size: _int(p['size']) ?? 0,
      coverId: thumb.isEmpty ? null : thumb,
      suffix: _suffix(
        p['container'] ?? (media is Map ? media['container'] : null),
      ),
      playCount: _int(m['viewCount']) ?? 0,
    );
  }

  /// `container` of the first part; a list ("m4a,mp4") keeps the first name.
  static String? _suffix(Object? c) {
    if (c is! String || c.isEmpty) return null;
    return c.split(',').first.trim().toLowerCase();
  }

  static String _str(Object? v) => v == null ? '' : '$v';
  static int? _int(Object? v) =>
      v is num ? v.toInt() : int.tryParse('${v ?? ''}');

  @override
  Future<List<SourcePlaylist>> playlists() async {
    final heads = <(String, String)>[];
    await for (final items in _pages(
      'playlists',
      query: {'playlistType': 'audio'},
    )) {
      for (final p in items) {
        if (p['ratingKey'] != null) {
          heads.add(('${p['ratingKey']}', _str(p['title'])));
        }
      }
    }
    return [
      for (final (id, name) in heads)
        SourcePlaylist(id: id, name: name, songIds: await _playlistSongs(id)),
    ];
  }

  /// Null when this playlist won't read (the others still do). A revoked token still throws.
  Future<List<String>?> _playlistSongs(String id) async {
    try {
      return [for (final (song, _) in await _entries(id)) song];
    } on PlexException catch (e) {
      if (e.tokenRefused) rethrow;
      return null;
    } on SourceNetworkException {
      return null;
    }
  }

  /// The rows of playlist [id] in order: (song's ratingKey, the row's `playlistItemID`).
  Future<List<(String, String?)>> _entries(String id) async {
    final out = <(String, String?)>[];
    await for (final items in _pages(
      'playlists/$id/items',
      repeatCheck: false,
    )) {
      for (final m in items) {
        if (m['ratingKey'] == null) continue;
        final item = m['playlistItemID'];
        out.add(('${m['ratingKey']}', item == null ? null : '$item'));
      }
    }
    return out;
  }

  // ---- writing playlists (plan 9) ----------------------------------------------------------

  /// Playlists live on one server: songs are named by this server's library uri.
  String _libraryUri([List<String> ratingKeys = const []]) {
    final lib = 'server://${_server.machineId}/com.plexapp.plugins.library';
    return ratingKeys.isEmpty
        ? lib
        : '$lib/library/metadata/${ratingKeys.join(',')}';
  }

  /// Rating keys per request (they travel in the address).
  static const _keysBatch = 100;

  /// A playlist change on the server in use. No address answering is a
  /// [SourceNetworkException]; 403 a [PlaylistWriteRefused]; another refusal a
  /// [PlexException] with its code. A 401 is checked with one read (`library/sections`):
  /// the read works → the token is fine, this change is not allowed ([PlaylistWriteRefused]);
  /// the read is refused too → « À reconnecter ».
  Future<http.Response> _write(
    String method,
    String path, [
    Map<String, String>? query,
  ]) async {
    try {
      await prepare();
    } on PlexException catch (e) {
      if (e.tokenRefused) rethrow;
      throw SourceNetworkException(TimeoutException(e.message));
    }
    final base = _base;
    if (base == null) {
      throw SourceNetworkException(TimeoutException('no address answers'));
    }
    final req = http.Request(method, plexUrl(base, path, query))
      ..followRedirects = false
      ..headers.addAll(headers);
    final res = await _send(req);
    final c = res.statusCode;
    if (c == 401) {
      final check = await _send(
        http.Request('GET', plexUrl(base, 'library/sections'))
          ..followRedirects = false
          ..headers.addAll(headers),
      );
      if (check.statusCode == 200) throw PlaylistWriteRefused('Plex 401');
      if (check.statusCode == 401) throw _relink();
      throw PlexException('playlist change refused', statusCode: c);
    }
    if (c == 403) throw PlaylistWriteRefused('Plex 403');
    if (c < 200 || c >= 300) {
      throw PlexException('playlist change refused', statusCode: c);
    }
    return res;
  }

  /// With songs, the first goes with the creation (`uri=…/library/metadata/{first}`), the
  /// others are added after. Empty, the uri names the library only: a shape not yet checked
  /// against a real Plex Media Server.
  @override
  Future<String> createPlaylist(
    String name, {
    List<String> songIds = const [],
  }) async {
    final res = await _write('POST', 'playlists', {
      'type': 'audio',
      'title': name,
      'smart': '0',
      'uri': _libraryUri(songIds.take(1).toList()),
    });
    final id = _newId(res);
    await addToPlaylist(id, songIds.skip(1).toList());
    return id;
  }

  String _newId(http.Response res) {
    try {
      final d = jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
      final mc = d is Map ? d['MediaContainer'] : null;
      final list = mc is Map ? mc['Metadata'] : null;
      if (list is List && list.isNotEmpty && list.first is Map) {
        final key = (list.first as Map)['ratingKey'];
        if (key != null) return '$key';
      }
    } on FormatException {
      // not JSON
    }
    throw PlexException('no id for the new playlist');
  }

  @override
  Future<void> addToPlaylist(String id, List<String> songIds) async {
    for (var i = 0; i < songIds.length; i += _keysBatch) {
      final end = i + _keysBatch < songIds.length
          ? i + _keysBatch
          : songIds.length;
      await _write('PUT', 'playlists/$id/items', {
        'uri': _libraryUri(songIds.sublist(i, end)),
      });
    }
  }

  /// The `playlistItemID` of each row asked; a row without one is a refusal (too old).
  static List<String> _itemIds(
    List<(String, String?)> rows,
    Iterable<int> at,
  ) => [
    for (final p in at)
      if (p >= 0 && p < rows.length)
        rows[p].$2 ?? (throw PlaylistWriteRefused('Plex: no playlistItemID')),
  ];

  @override
  Future<void> removeFromPlaylist(
    String id,
    List<int> positions, {
    List<String>? expected,
  }) async {
    final rows = await _entries(id);
    if (expected != null) {
      checkPlaylistRows([for (final r in rows) r.$1], positions, expected);
    }
    for (final item in _itemIds(rows, positions.toSet())) {
      await _write('DELETE', 'playlists/$id/items/$item');
    }
  }

  /// `PUT …/items/{item}/move?after={the row that will come before it}`; to the top, no
  /// `after`.
  @override
  Future<void> movePlaylistItem(
    String id,
    int from,
    int to, {
    String? expected,
  }) async {
    final rows = await _entries(id);
    checkPlaylistRows(
      [for (final r in rows) r.$1],
      [from, to],
      expected == null ? null : [expected],
    );
    if (from == to) return;
    final ids = _itemIds(rows, List.generate(rows.length, (i) => i));
    final item = ids.removeAt(from);
    await _write('PUT', 'playlists/$id/items/$item/move', {
      if (to > 0) 'after': ids[to - 1],
    });
  }

  @override
  Future<void> renamePlaylist(String id, String name) async {
    await _write('PUT', 'playlists/$id', {'title': name});
  }

  @override
  Future<void> deletePlaylist(String id) async {
    await _write('DELETE', 'playlists/$id');
  }

  @override
  Future<SourcePlaylist> readPlaylist(String id) async {
    final d = await _get('playlists/$id');
    final list = d['Metadata'];
    final head = list is List && list.isNotEmpty && list.first is Map
        ? list.first as Map
        : const {};
    return SourcePlaylist(
      id: id,
      name: _str(head['title']),
      songIds: [for (final (song, _) in await _entries(id)) song],
    );
  }

  /// A cover: the server resizes the picture [coverId] (its `thumb` path). The token goes in
  /// [headers] only, never in this address (it would end up in cache keys and logs); callers
  /// wait for [prepare] first (the address is chosen there).
  @override
  Uri coverUri(String coverId, int size) {
    final base = _base;
    if (base == null) throw PlexException('source not prepared');
    return plexUrl(base, 'photo/:/transcode', {
      'url': coverId,
      'width': '$size',
      'height': '$size',
    });
  }

  /// How long a looked-up file address, and an album read, are trusted (the server may
  /// re-analyse its files).
  static const partTtl = Duration(minutes: 30);

  /// A song looked up for playback is asked again after this: nothing can retry inside mpv,
  /// so a stale address must not outlive one play.
  static const playbackFresh = Duration(minutes: 1);
  final int _partsMax;
  final _parts = <String, ({String key, DateTime at})>{};
  final _albumsRead = <String, DateTime>{};

  String? _partOf(String songId, [Duration ttl = partTtl]) {
    final p = _parts[songId];
    if (p == null) return null;
    if (_now().difference(p.at) >= ttl) {
      _parts.remove(songId);
      return null;
    }
    return p.key;
  }

  void _remember(String songId, Map m) {
    final key = _str(_firstPart(m)?['key']);
    if (key.isEmpty) return;
    if (_parts.length >= _partsMax && !_parts.containsKey(songId)) {
      _parts.clear();
      _albumsRead.clear();
    }
    _parts[songId] = (key: key, at: _now());
  }

  @override
  Future<void> forgetSong(String songId) async {
    // a rescan changes the keys of the whole album, and which album it was is not kept
    _parts.clear();
    _albumsRead.clear();
  }

  /// Looks the file of [songId] up (`GET /library/metadata/{id}`; its first Part). [batch]:
  /// a download run: what the song's album gave is used, and the album is then read once
  /// (`/children`, one request for all its songs) so the next songs cost nothing; if that
  /// fails, songs are read one by one. Playback ([batch] false) asks again when its answer
  /// is older than [playbackFresh]. A song the server doesn't have, or without a file, is a
  /// 404 [PlexException].
  @override
  Future<void> resolveSong(String songId, {bool batch = false}) async {
    await prepare();
    if (_partOf(songId, batch ? partTtl : playbackFresh) != null) return;
    final d = await _get('library/metadata/$songId');
    final raw = d['Metadata'];
    final m = raw is List && raw.isNotEmpty && raw.first is Map
        ? raw.first as Map
        : null;
    if (m == null) {
      throw PlexException('song not found', statusCode: 404);
    }
    _parts.remove(songId);
    _remember(songId, m);
    if (_partOf(songId) == null) {
      throw PlexException('song has no file', statusCode: 404);
    }
    final album = _str(m['parentRatingKey']);
    final read = _albumsRead[album];
    if (batch &&
        album.isNotEmpty &&
        (read == null || _now().difference(read) >= partTtl)) {
      _albumsRead[album] = _now();
      try {
        await for (final items in _pages('library/metadata/$album/children')) {
          for (final t in items) {
            if (t['ratingKey'] != null) _remember('${t['ratingKey']}', t);
          }
        }
      } on Object {
        _albumsRead.remove(album); // the songs are read one by one
      }
    }
  }

  Uri _partUri(String songId, [Map<String, String>? query]) {
    final base = _base, key = _partOf(songId);
    if (base == null || key == null) {
      throw StateError('Plex song not resolved'); // resolveSong() first
    }
    return plexUrl(base, key, query);
  }

  /// The original file; the token goes in [headers] only (never in this address).
  @override
  Uri streamUri(String songId) => _partUri(songId);

  @override
  Uri downloadUri(String songId) => _partUri(songId, {'download': '1'});

  /// Marks the song played. Plex takes no date: a listen sent later (it waited offline)
  /// counts as played now. A 404 (the song is gone) is a [PlexException] with that code.
  @override
  Future<void> scrobble(String songId, DateTime at) async {
    await _getRaw('/:/scrobble', {
      'key': songId,
      'identifier': 'com.plexapp.plugins.library',
    });
  }

  @override
  void close() {
    _closed = true;
    _client.close();
  }
}
