// Fake servers that keep their playlists in memory (plan 9): handwritten answers in the
// shapes of the real APIs. Never a real server.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lafleurmusic/sources/plex.dart';
import 'package:lafleurmusic/sources/plex_link.dart';

import 'fake_plex.dart';
import 'fake_secret_store.dart';

/// A fake Navidrome keeping its playlists in memory, answering with the JSON shapes a real
/// one sends (handwritten from Navidrome 0.53 answers). Never a real server.
class FakeNavidrome {
  final lists = <String, ({String name, List<String> songs})>{
    'pl1': (name: 'Road', songs: ['s1', 's2', 's3']),
  };
  final log = <http.Request>[];
  var nextId = 10;

  /// Error 50 (« user is not authorized ») on every write.
  bool readOnly = false;

  /// Error 50 on the next this many writes only.
  int refuseNext = 0;

  /// Writes answer HTTP 403 with no Subsonic body (a proxy refusing them).
  bool forbidden = false;

  /// Announces the OpenSubsonic `formPost` extension.
  bool formPost = false;

  /// createPlaylist answers like Subsonic before 1.14: no playlist in the answer.
  bool oldCreate = false;

  /// Requests longer than this are refused (414), like a proxy's limit.
  int maxUrl = 100000;

  /// Playlists of another user (public): shown with that owner, error 50 on any change.
  Set<String> foreign = {};

  /// Playlists the server marks `readonly` (OpenSubsonic).
  Set<String> readonlyFlag = {};

  /// When each playlist was made (`created`); a new one gets the next second.
  final created = <String, DateTime>{'pl1': DateTime.utc(2024, 1, 1)};
  var _clock = DateTime.utc(2026, 11, 19, 10);

  /// getPlaylists lists the newest first (the last one is then not the new one).
  bool newestFirst = false;

  /// The next this many answers to getOpenSubsonicExtensions are a proxy's 502 page.
  int extensionsBroken = 0;

  /// The next this many writes are applied, then their answer never comes (a timeout).
  int lostAnswers = 0;

  static const _ok = {'status': 'ok', 'version': '1.16.1'};

  http.Response _json(Map<String, Object?> body) => http.Response(
    jsonEncode({
      'subsonic-response': {..._ok, ...body},
    }),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  http.Response _error(int code, String message) => http.Response(
    jsonEncode({
      'subsonic-response': {
        'status': 'failed',
        'version': '1.16.1',
        'error': {'code': code, 'message': message},
      },
    }),
    200,
  );

  Map<String, Object?> _playlist(String id) {
    final p = lists[id]!;
    return {
      'id': id,
      'name': p.name,
      'owner': foreign.contains(id) ? 'someone' : 'johnny',
      'public': foreign.contains(id),
      if (readonlyFlag.contains(id)) 'readonly': true,
      if (created[id] != null) 'created': created[id]!.toIso8601String(),
      'songCount': p.songs.length,
      'entry': [
        for (final s in p.songs) {'id': s, 'title': 'T$s', 'isDir': false},
      ],
    };
  }

  /// The network is gone: every request fails (a SocketException).
  bool down = false;

  /// Each answer takes this long (requests may then overlap if the app lets them).
  Duration delay = Duration.zero;

  /// Requests being answered now, and the most seen at once.
  int inFlight = 0, maxInFlight = 0;

  Future<http.Response> handle(http.Request r) async {
    if (down) throw const SocketException('no route to host');
    inFlight++;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    try {
      if (delay > Duration.zero) await Future<void>.delayed(delay);
      final res = _handle(r);
      final m = r.url.pathSegments.last;
      if (lostAnswers > 0 &&
          m.contains('Playlist.view') &&
          !m.startsWith('get')) {
        lostAnswers--;
        throw TimeoutException('answer lost');
      }
      return res;
    } finally {
      inFlight--;
    }
  }

  http.Response _handle(http.Request r) {
    log.add(r);
    if (r.url.toString().length > maxUrl) return http.Response('', 414);
    final method = r.url.pathSegments.last.replaceAll('.view', '');
    // a form POST carries its parameters in the body
    final all = <String, List<String>>{
      for (final e in r.url.queryParametersAll.entries) e.key: [...e.value],
    };
    if (r.method == 'POST') {
      if (!formPost) return http.Response('', 405);
      for (final e in Uri(query: r.body).queryParametersAll.entries) {
        all.putIfAbsent(e.key, () => []).addAll(e.value);
      }
    }
    String? one(String k) => all[k]?.first;
    const writes = {'createPlaylist', 'updatePlaylist', 'deletePlaylist'};
    if (writes.contains(method)) {
      if (forbidden) return http.Response('Forbidden', 403);
      if (readOnly) return _error(50, 'User not authorized');
      if (refuseNext > 0) {
        refuseNext--;
        return _error(50, 'User not authorized');
      }
      final target = one('playlistId') ?? one('id');
      if (foreign.contains(target)) {
        return _error(50, 'User not authorized');
      }
    }
    switch (method) {
      case 'getOpenSubsonicExtensions':
        if (extensionsBroken > 0) {
          extensionsBroken--;
          return http.Response('<html>Bad gateway</html>', 502);
        }
        return _json({
          'openSubsonicExtensions': [
            if (formPost)
              {
                'name': 'formPost',
                'versions': [1],
              },
            {
              'name': 'transcodeOffset',
              'versions': [1],
            },
          ],
        });
      case 'getPlaylists':
        return _json({
          'playlists': {
            'playlist': [
              for (final id
                  in newestFirst ? lists.keys.toList().reversed : lists.keys)
                {..._playlist(id)}..remove('entry'),
            ],
          },
        });
      case 'getPlaylist':
        final id = one('id');
        if (!lists.containsKey(id)) return _error(70, 'Playlist not found');
        return _json({'playlist': _playlist(id!)});
      case 'createPlaylist':
        final songs = all['songId'] ?? const [];
        final existing = one('playlistId');
        if (existing != null) {
          final old = lists[existing];
          if (old == null) return _error(70, 'Playlist not found');
          lists[existing] = (name: one('name') ?? old.name, songs: songs);
          return oldCreate
              ? _json({})
              : _json({'playlist': _playlist(existing)});
        }
        final id = 'pl${nextId++}';
        lists[id] = (name: one('name')!, songs: songs);
        created[id] = _clock = _clock.add(const Duration(seconds: 1));
        return oldCreate ? _json({}) : _json({'playlist': _playlist(id)});
      case 'updatePlaylist':
        final id = one('playlistId');
        final old = lists[id];
        if (old == null) return _error(70, 'Playlist not found');
        final gone = {
          for (final i in all['songIndexToRemove'] ?? const <String>[])
            int.parse(i),
        };
        lists[id!] = (
          name: one('name') ?? old.name,
          songs: [
            for (final (i, s) in old.songs.indexed)
              if (!gone.contains(i)) s,
            ...?all['songIdToAdd'],
          ],
        );
        return _json({});
      case 'deletePlaylist':
        if (lists.remove(one('id')) == null) {
          return _error(70, 'Playlist not found');
        }
        return _json({});
    }
    return http.Response('', 404);
  }

  MockClient client() => MockClient(handle);
}

const jellyfinAuth =
    '{"User":{"Name":"max","Id":"user-1"},"AccessToken":"tok-secret-1","ServerId":"abc"}';

http.Response jfJson(Object body, [int code = 200]) => http.Response(
  jsonEncode(body),
  code,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

/// A fake Jellyfin 10.9 keeping its playlists in memory, with the answer shapes of the real
/// API (handwritten). Each row has its own `PlaylistItemId`, as on a real server.
class FakeJellyfin {
  final lists = <String, ({String name, List<(String, String)> rows})>{
    'pl1': (name: 'Road', rows: [('s1', 'e1'), ('s2', 'e2'), ('s3', 'e3')]),
  };
  final log = <http.Request>[];
  var _next = 10, _entry = 10;

  /// Every write answers 403 (the user may not change playlists).
  bool readOnly = false;

  /// `POST /Playlists/{id}` does not exist (before 10.9): 404.
  bool oldServer = false;

  /// `DELETE /Items/{id}` answers 401 to this user (Jellyfin's answer when deleting is not
  /// allowed), even with a fresh token.
  bool deleteDenied = false;

  int signIns = 0;

  List<String> songs(String id) => [for (final (s, _) in lists[id]!.rows) s];

  Future<http.Response> handle(http.Request r) async {
    log.add(r);
    final p = r.url.path;
    final q = r.url.queryParameters;
    if (p == '/Users/AuthenticateByName') {
      signIns++;
      return http.Response(jellyfinAuth, 200);
    }
    if (!(r.headers['Authorization'] ?? '').contains('Token="tok-secret-1"')) {
      return http.Response('', 401);
    }
    final write = r.method != 'GET';
    if (write && readOnly) return http.Response('', 403);

    if (p == '/Playlists' && r.method == 'POST') {
      final b = jsonDecode(r.body) as Map;
      if (b['UserId'] != 'user-1' || b['MediaType'] != 'Audio') {
        return http.Response('', 400);
      }
      final id = 'pl${_next++}';
      lists[id] = (
        name: b['Name'] as String,
        rows: [
          for (final s in (b['Ids'] as List).cast<String>())
            (s, 'e${_entry++}'),
        ],
      );
      return jfJson({'Id': id});
    }
    var m = RegExp(r'^/Users/user-1/Items/(\w+)$').firstMatch(p);
    if (m != null) {
      final l = lists[m.group(1)];
      if (l == null) return http.Response('', 404);
      return jfJson({
        'Id': m.group(1),
        'Name': l.name,
        'Type': 'Playlist',
        'MediaType': 'Audio',
      });
    }
    m = RegExp(r'^/Playlists/(\w+)/Items$').firstMatch(p);
    if (m != null) {
      final id = m.group(1)!;
      final l = lists[id];
      if (l == null) return http.Response('', 404);
      switch (r.method) {
        case 'GET':
          final start = int.parse(q['StartIndex'] ?? '0');
          final limit = int.parse(q['Limit'] ?? '100000');
          final all = [
            for (final (s, e) in l.rows)
              {'Id': s, 'Name': 'T$s', 'Type': 'Audio', 'PlaylistItemId': e},
          ];
          return jfJson({
            'Items': all.skip(start).take(limit).toList(),
            'TotalRecordCount': all.length,
            'StartIndex': start,
          });
        case 'POST':
          if (q['UserId'] != 'user-1') return http.Response('', 400);
          for (final s in q['Ids']!.split(',')) {
            l.rows.add((s, 'e${_entry++}'));
          }
          return http.Response('', 204);
        case 'DELETE':
          final gone = q['EntryIds']!.split(',').toSet();
          l.rows.removeWhere((row) => gone.contains(row.$2));
          return http.Response('', 204);
      }
    }
    m = RegExp(r'^/Playlists/(\w+)/Items/(\w+)/Move/(\d+)$').firstMatch(p);
    if (m != null && r.method == 'POST') {
      final l = lists[m.group(1)]!;
      final from = l.rows.indexWhere((row) => row.$2 == m!.group(2));
      if (from < 0) return http.Response('', 404);
      final row = l.rows.removeAt(from);
      l.rows.insert(int.parse(m.group(3)!), row);
      return http.Response('', 204);
    }
    m = RegExp(r'^/Playlists/(\w+)$').firstMatch(p);
    if (m != null && r.method == 'POST') {
      if (oldServer) return http.Response('', 404);
      final id = m.group(1)!;
      final l = lists[id]!;
      lists[id] = (
        name: (jsonDecode(r.body) as Map)['Name'] as String,
        rows: l.rows,
      );
      return http.Response('', 204);
    }
    m = RegExp(r'^/Items/(\w+)$').firstMatch(p);
    if (m != null) {
      final id = m.group(1)!;
      if (r.method == 'DELETE') {
        if (deleteDenied) return http.Response('', 401);
        lists.remove(id);
        return http.Response('', 204);
      }
      if (r.method == 'POST') {
        final b = jsonDecode(r.body) as Map;
        if (b['Id'] != id || b['Type'] != 'Playlist') {
          return http.Response('', 400);
        }
        lists[id] = (name: b['Name'] as String, rows: lists[id]!.rows);
        return http.Response('', 204);
      }
    }
    return http.Response('', 404);
  }

  MockClient client() => MockClient(handle);
}

final home = PlexServer.fromResource(resourceJson(homeResource))!;

const plexLibraryUri = 'server://mach-home/com.plexapp.plugins.library';

/// A fake Plex Media Server keeping its audio playlists in memory, answering with the shapes
/// of the real API (handwritten from PMS 1.41 answers). Each row has its own
/// `playlistItemID`. Other paths (identity…) go to [FakePms].
class FakePlexPlaylists {
  final pms = FakePms();
  final lists = <String, ({String title, List<(String, int)> rows})>{
    '900': (title: 'Road', rows: [('101', 1), ('211', 2), ('102', 3)]),
  };
  final log = <http.Request>[];
  var _next = 910, _item = 10;

  /// Every write answers 403 (a shared user may not change this server's playlists).
  bool readOnly = false;

  /// Every write answers 401 while reads with the same token work.
  bool writes401 = false;

  /// The network is gone.
  bool down = false;

  List<String> songs(String id) => [for (final (s, _) in lists[id]!.rows) s];

  http.Response _ok([Object? mc]) => jsonResponse(
    jsonEncode({
      'MediaContainer': mc ?? {'size': 0},
    }),
  );

  Map<String, Object?> _head(String id) => {
    'ratingKey': id,
    'key': '/playlists/$id/items',
    'type': 'playlist',
    'title': lists[id]!.title,
    'playlistType': 'audio',
    'smart': false,
    'leafCount': lists[id]!.rows.length,
  };

  /// The rating keys of a `server://…/library/metadata/1,2,3` uri.
  List<String>? _keys(String? uri) {
    if (uri == null || !uri.startsWith(plexLibraryUri)) return null;
    final rest = uri.substring(plexLibraryUri.length);
    if (rest.isEmpty) return const [];
    if (!rest.startsWith('/library/metadata/')) return null;
    return rest.substring('/library/metadata/'.length).split(',');
  }

  Future<http.Response> handle(http.Request r) async {
    if (down) throw const SocketException('down');
    final p = r.url.path;
    if (!p.startsWith('/playlists')) return pms.handle(r);
    log.add(r);
    if (r.url.host != homeLocal) throw const SocketException('not here');
    if (r.headers['X-Plex-Token'] != 'server-token-home') {
      return http.Response('<html>Unauthorized</html>', 401);
    }
    final q = r.url.queryParameters;
    if (r.method != 'GET' && readOnly) return http.Response('', 403);
    if (r.method != 'GET' && writes401) return http.Response('', 401);
    if (p == '/playlists' && r.method == 'POST') {
      final keys = _keys(q['uri']);
      if (q['type'] != 'audio' || q['smart'] != '0' || keys == null) {
        return http.Response('', 400);
      }
      final id = '${_next++}';
      lists[id] = (
        title: q['title']!,
        rows: [for (final k in keys) (k, _item++)],
      );
      return _ok({
        'size': 1,
        'Metadata': [_head(id)],
      });
    }
    var m = RegExp(r'^/playlists/(\d+)$').firstMatch(p);
    if (m != null) {
      final id = m.group(1)!;
      if (!lists.containsKey(id)) return http.Response('', 404);
      switch (r.method) {
        case 'GET':
          return _ok({
            'size': 1,
            'Metadata': [_head(id)],
          });
        case 'PUT':
          lists[id] = (title: q['title']!, rows: lists[id]!.rows);
          return _ok();
        case 'DELETE':
          lists.remove(id);
          return http.Response('', 204);
      }
    }
    m = RegExp(r'^/playlists/(\d+)/items$').firstMatch(p);
    if (m != null) {
      final id = m.group(1)!;
      final l = lists[id];
      if (l == null) return http.Response('', 404);
      if (r.method == 'GET') {
        final start = int.parse(r.headers['X-Plex-Container-Start'] ?? '0');
        final size = int.parse(r.headers['X-Plex-Container-Size'] ?? '100000');
        final all = [
          for (final (k, item) in l.rows)
            {
              'ratingKey': k,
              'type': 'track',
              'title': 'T$k',
              'playlistItemID': item,
            },
        ];
        final page = all.skip(start).take(size).toList();
        return _ok({
          'size': page.length,
          'totalSize': all.length,
          'offset': start,
          if (page.isNotEmpty) 'Metadata': page,
        });
      }
      if (r.method == 'PUT') {
        final keys = _keys(q['uri']);
        if (keys == null || keys.isEmpty) return http.Response('', 400);
        for (final k in keys) {
          l.rows.add((k, _item++));
        }
        return _ok({'size': 0, 'leafCountAdded': keys.length});
      }
    }
    m = RegExp(r'^/playlists/(\d+)/items/(\d+)(/move)?$').firstMatch(p);
    if (m != null) {
      final l = lists[m.group(1)]!;
      final item = int.parse(m.group(2)!);
      final i = l.rows.indexWhere((row) => row.$2 == item);
      if (i < 0) return http.Response('', 404);
      if (r.method == 'DELETE' && m.group(3) == null) {
        l.rows.removeAt(i);
        return _ok();
      }
      if (r.method == 'PUT' && m.group(3) != null) {
        final row = l.rows.removeAt(i);
        final after = q['after'];
        if (after == null) {
          l.rows.insert(0, row);
        } else {
          final a = l.rows.indexWhere((x) => x.$2 == int.parse(after));
          if (a < 0) return http.Response('', 400);
          l.rows.insert(a + 1, row);
        }
        return _ok();
      }
    }
    return http.Response('', 404);
  }

  PlexSource source() {
    final s = FakeSecretStore();
    s.data[PlexSource.tokenKey('acc1')] = 'server-token-home';
    return PlexSource(
      accountId: 'acc1',
      server: home,
      clientId: 'client-abc',
      headers: const {'X-Proxy': 'k'},
      client: MockClient(handle),
      secrets: s,
      deviceName: 'iPhone',
      platform: 'iOS',
    );
  }
}
