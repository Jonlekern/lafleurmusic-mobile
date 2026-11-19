// A small Jellyfin server for the end-to-end run (plan 4), in the test process itself, next to
// the fake Navidrome (fake_subsonic.dart). It carries the SAME album as the fake Navidrome
// ("Studio Lafleur" by LAFLEURSTUDIO, Night Drive and Surf Break, with AlbumArtist so the app
// merges the two), streams and gives for download a.flac, and counts the listens it receives.
// Like a Jellyfin behind a proxy, it refuses every request without `X-Lafleur-Test: ok` (403);
// everything but the public info and the sign-in needs the token (header or `api_key`), else 401.
// test/fake_jellyfin_test.dart checks our Jellyfin client talks to it like to a real server.
import 'dart:convert';
import 'dart:io';

import 'fake_subsonic.dart' show FakeRequest, fakeHeader, fakeHeaderValue;
import 'fixture_bytes.dart';

/// 1×1 PNG for the covers.
const _pngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

class FakeJellyfin {
  FakeJellyfin._(this._server, this.user, this.password);

  static const userId = 'jf-user-1';
  static const viewId = 'jf-music';
  static const albumId = 'jf-al-1';

  final HttpServer _server;
  final String user, password;

  /// Every request the server saw: what it was (`info`, `signIn`, `items`, `stream`,
  /// `download`, `played`…) and its outcome. Never the token.
  final requests = <FakeRequest>[];

  /// Cuts the server: every connection is closed without an answer. Nothing is recorded.
  bool down = false;

  /// Connections cut while [down].
  int refused = 0;

  final _plays = <String, int>{};
  final _song = base64Decode(aFlacBase64);
  final _png = base64Decode(_pngBase64);

  /// Listens received for [songId] (`POST /Users/{id}/PlayedItems/{song}`).
  int playCount(String songId) => _plays[songId] ?? 0;

  /// The access token the sign-in hands out (one per server).
  String get token => 'fake-jellyfin-token-${_server.port}';

  /// Serves on 127.0.0.1, random port.
  static Future<FakeJellyfin> start({
    String user = 'johnny',
    String password = 'jellyfin-e2e',
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = FakeJellyfin._(server, user, password);
    server.listen(fake._handle);
    return fake;
  }

  String get address => 'http://127.0.0.1:${_server.port}';

  Future<void> close() => _server.close(force: true);

  static const _album = {
    'Id': albumId,
    'Name': 'Studio Lafleur',
    'Type': 'MusicAlbum',
    'AlbumArtist': 'LAFLEURSTUDIO',
    'AlbumArtists': [
      {'Name': 'LAFLEURSTUDIO', 'Id': 'jf-ar-1'},
    ],
    'ChildCount': 2,
    'ImageTags': {'Primary': 'jf-tag'},
  };

  Map<String, Object?> _songJson(
    String id,
    String title,
    String artist,
    int track,
    String genre,
    int seconds,
  ) => {
    'Id': id,
    'Name': title,
    'Type': 'Audio',
    'Album': 'Studio Lafleur',
    'AlbumId': albumId,
    'AlbumArtist': 'LAFLEURSTUDIO',
    'AlbumPrimaryImageTag': 'jf-tag',
    'Artists': [artist],
    'IndexNumber': track,
    'ParentIndexNumber': 1,
    'Genres': [genre],
    'RunTimeTicks': seconds * 10000000,
    'MediaSources': [
      {'Container': 'flac', 'Size': _song.length, 'Path': '/music/$id.flac'},
    ],
    'UserData': {'PlayCount': 0, 'Played': false},
  };

  // the same songs as the fake Navidrome's getAlbum (s-1, s-2), under Jellyfin ids
  late final List<Map<String, Object?>> _songs = [
    _songJson('jf-s-1', 'Night Drive', 'Kavinsky', 1, 'Synthwave', 215),
    _songJson('jf-s-2', 'Surf Break', 'Johnny', 2, 'Surf', 180),
  ];

  bool _hasToken(HttpRequest req) {
    final q = req.uri.queryParameters;
    if (q['api_key'] == token) return true;
    for (final h in ['authorization', 'x-emby-authorization']) {
      final v = req.headers.value(h);
      if (v != null && v.contains('Token="$token"')) return true;
    }
    return false;
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    if (down) {
      refused++;
      (await res.detachSocket(writeHeaders: false)).destroy();
      return;
    }
    final q = req.uri.queryParameters;
    final seg = req.uri.pathSegments;
    var what = '${req.method} ${req.uri.path}';
    final logged = <String, String>{
      for (final e in q.entries)
        if (e.key != 'api_key') e.key: e.value,
    };
    void json(Object body) {
      res.headers.contentType = ContentType.json;
      res.write(jsonEncode(body));
    }

    void audio() {
      res.headers.contentType = ContentType('audio', 'flac');
      res.contentLength = _song.length;
      res.add(_song);
    }

    Map<String, Object?>? song(String id) {
      for (final s in _songs) {
        if (s['Id'] == id) return s;
      }
      return null;
    }

    final body = await utf8.decodeStream(req);
    if (req.headers.value(fakeHeader) != fakeHeaderValue) {
      res.statusCode = HttpStatus.forbidden;
      res.write('Forbidden');
    } else if (req.method == 'GET' && req.uri.path == '/System/Info/Public') {
      what = 'info';
      json({
        'LocalAddress': address,
        'ServerName': 'fake',
        'Version': '10.10.7',
        'ProductName': 'Jellyfin Server',
        'Id': 'fake-jellyfin',
        'StartupWizardCompleted': true,
      });
    } else if (req.method == 'POST' &&
        req.uri.path == '/Users/AuthenticateByName') {
      what = 'signIn';
      Object? d;
      try {
        d = jsonDecode(body);
      } on FormatException {
        d = null;
      }
      if (d is Map && d['Username'] == user && d['Pw'] == password) {
        json({
          'User': {'Name': user, 'Id': userId},
          'AccessToken': token,
          'ServerId': 'fake-jellyfin',
        });
      } else {
        res.statusCode = HttpStatus.unauthorized;
      }
    } else if (!_hasToken(req)) {
      res.statusCode = HttpStatus.unauthorized;
    } else if (req.method == 'GET' &&
        seg.length == 3 &&
        seg[0] == 'Users' &&
        seg[1] == userId &&
        seg[2] == 'Views') {
      what = 'views';
      json({
        'Items': [
          {'Name': 'Musique', 'Id': viewId, 'CollectionType': 'music'},
        ],
        'TotalRecordCount': 1,
        'StartIndex': 0,
      });
    } else if (req.method == 'GET' &&
        seg.length == 3 &&
        seg[0] == 'Users' &&
        seg[1] == userId &&
        seg[2] == 'Items') {
      what = 'items';
      final types = q['IncludeItemTypes'];
      final ids = q['Ids']?.split(',');
      final List<Map<String, Object?>> all;
      if (ids != null) {
        all = [for (final id in ids) ?song(id)];
      } else if (types == 'MusicAlbum') {
        all = [_album];
      } else if (types == 'Audio' &&
          (q['ParentId'] == viewId || q['ParentId'] == albumId)) {
        all = _songs;
      } else {
        all = const []; // playlists, anything else
      }
      final start = int.tryParse(q['StartIndex'] ?? '0') ?? 0;
      json({
        'Items': start >= all.length ? const [] : all.sublist(start),
        'TotalRecordCount': all.length,
        'StartIndex': start,
      });
    } else if (req.method == 'GET' &&
        seg.length == 4 &&
        seg[0] == 'Items' &&
        seg[2] == 'Images') {
      what = 'cover';
      res.headers.contentType = ContentType('image', 'png');
      res.contentLength = _png.length;
      res.add(_png);
    } else if (req.method == 'GET' &&
        seg.length == 3 &&
        seg[0] == 'Audio' &&
        seg[2] == 'universal') {
      what = 'stream';
      logged['id'] = seg[1];
      if (song(seg[1]) != null) {
        audio();
      } else {
        res.statusCode = HttpStatus.notFound;
      }
    } else if (req.method == 'GET' &&
        seg.length == 3 &&
        seg[0] == 'Items' &&
        seg[2] == 'Download') {
      what = 'download';
      logged['id'] = seg[1];
      if (song(seg[1]) != null) {
        audio();
      } else {
        res.statusCode = HttpStatus.notFound;
      }
    } else if (req.method == 'POST' &&
        seg.length == 4 &&
        seg[0] == 'Users' &&
        seg[1] == userId &&
        seg[2] == 'PlayedItems') {
      what = 'played';
      logged['id'] = seg[3];
      final s = song(seg[3]);
      if (s == null) {
        res.statusCode = HttpStatus.notFound;
      } else {
        final n = _plays[seg[3]] = playCount(seg[3]) + 1;
        json({'PlayCount': n, 'Played': true, 'Key': seg[3]});
      }
    } else {
      res.statusCode = HttpStatus.notFound;
    }
    requests.add(FakeRequest(what, res.statusCode, logged));
    await res.close();
  }
}
