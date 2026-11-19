// A fake plex.tv and a fake Plex Media Server for the end-to-end run (plan 5), in the test
// process itself, next to the fake Navidrome and Jellyfin. Never the real ones.
//
// plex.tv: a code (PIN) is handed out and validated at the first poll, then `/api/v2/user` and
// `/api/v2/resources` (one server, with a single local `http://127.0.0.1` address).
// The server carries the SAME album as the other fakes ("Studio Lafleur" by LAFLEURSTUDIO, Night
// Drive and Surf Break; the album artist is the grandparent) so the app merges them. It streams
// and gives for download a.flac, serves a cover, and counts the listens it receives.
// Like the real thing: everything but `/identity` needs the token (`X-Plex-Token`), else 401.
// test/sources/fake_plex.dart holds the unit tests' fakes of the same API.
import 'dart:convert';
import 'dart:io';

import 'fake_subsonic.dart' show FakeRequest;
import 'fixture_bytes.dart';

/// 1×1 PNG for the covers.
const _pngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

class FakePlex {
  FakePlex._(this._tv, this._pms);

  static const machineId = 'fake-plex-machine';
  static const albumKey = '311';
  static const code = 'K7QX';
  static const userUuid = 'fake-plex-user';

  /// The token plex.tv hands out once the code is typed, and the server's own token.
  static const userToken = 'fake-plex-user-token';
  static const serverToken = 'fake-plex-server-token';

  final HttpServer _tv, _pms;

  /// What plex.tv saw (`pin`, `poll`, `user`, `resources`) and what the server saw (`identity`,
  /// `sections`, `albums`, `children`, `song`, `cover`, `stream`, `download`, `scrobble`…).
  final tvRequests = <FakeRequest>[];
  final requests = <FakeRequest>[];

  /// Cuts the server: every connection is closed without an answer. Nothing is recorded.
  bool down = false;

  final _plays = <String, int>{};
  final _song = base64Decode(aFlacBase64);
  final _png = base64Decode(_pngBase64);

  /// Listens received for [songKey] (`/:/scrobble`).
  int playCount(String songKey) => _plays[songKey] ?? 0;

  static Future<FakePlex> start() async {
    final tv = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final pms = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = FakePlex._(tv, pms);
    tv.listen(fake._handleTv);
    pms.listen(fake._handlePms);
    return fake;
  }

  /// plex.tv's address for [PlexLink] (its `plexTv`).
  Uri get plexTv => Uri.parse('http://127.0.0.1:${_tv.port}');

  Future<void> close() async {
    await _tv.close(force: true);
    await _pms.close(force: true);
  }

  // ---- plex.tv ------------------------------------------------------------------------------

  String get _resource => jsonEncode({
    'name': 'Fake Plex',
    'product': 'Plex Media Server',
    'provides': 'server',
    'clientIdentifier': machineId,
    'accessToken': serverToken,
    'owned': true,
    'connections': [
      {
        'protocol': 'http',
        'address': '127.0.0.1',
        'port': _pms.port,
        'uri': 'http://127.0.0.1:${_pms.port}',
        'local': true,
        'relay': false,
        'IPv6': false,
      },
    ],
  });

  Future<void> _handleTv(HttpRequest req) async {
    final res = req.response;
    final path = req.uri.path;
    var what = '${req.method} $path';
    await req.drain<void>();
    void json(Object body, [int code = 200]) {
      res.statusCode = code;
      res.headers.contentType = ContentType.json;
      res.write(jsonEncode(body));
    }

    final authed = req.headers.value('x-plex-token') == userToken;
    if (req.method == 'POST' && path == '/api/v2/pins') {
      what = 'pin';
      json({
        'id': 1234,
        'code': code,
        'trusted': false,
        'expiresIn': 900,
        'authToken': null,
      }, 201);
    } else if (req.method == 'GET' && path == '/api/v2/pins/1234') {
      what = 'poll';
      // typed on plex.tv/link at once: validated by the first poll
      json({'id': 1234, 'code': code, 'authToken': userToken});
    } else if (req.method == 'GET' && path == '/api/v2/user') {
      what = 'user';
      if (authed) {
        json({'id': 42, 'uuid': userUuid, 'username': 'fake', 'title': 'fake'});
      } else {
        res.statusCode = HttpStatus.unauthorized;
      }
    } else if (req.method == 'GET' && path == '/api/v2/resources') {
      what = 'resources';
      if (authed) {
        res.statusCode = 200;
        res.headers.contentType = ContentType.json;
        res.write('[$_resource]');
      } else {
        res.statusCode = HttpStatus.unauthorized;
      }
    } else {
      res.statusCode = HttpStatus.notFound;
    }
    tvRequests.add(FakeRequest(what, res.statusCode, const {}));
    await res.close();
  }

  // ---- the server ---------------------------------------------------------------------------

  static const _album = {
    'ratingKey': albumKey,
    'key': '/library/metadata/$albumKey/children',
    'type': 'album',
    'title': 'Studio Lafleur',
    'parentTitle': 'LAFLEURSTUDIO',
    'leafCount': 2,
    'year': 2024,
    'thumb': '/library/metadata/$albumKey/thumb/1700000311',
  };

  Map<String, Object?> _songJson(
    String key,
    String title,
    String artist,
    int track,
    String genre,
    int seconds,
  ) => {
    'ratingKey': key,
    'type': 'track',
    'title': title,
    'grandparentTitle': 'LAFLEURSTUDIO',
    'originalTitle': artist,
    'parentTitle': 'Studio Lafleur',
    'parentRatingKey': albumKey,
    'index': track,
    'parentIndex': 1,
    'duration': seconds * 1000,
    'viewCount': 0,
    'parentThumb': '/library/metadata/$albumKey/thumb/1700000311',
    'Genre': [
      {'tag': genre},
    ],
    'Media': [
      {
        'id': 9000 + track,
        'container': 'flac',
        'Part': [
          {
            'id': 9000 + track,
            'key': '/library/parts/${9000 + track}/1700000000/file.flac',
            'size': _song.length,
            'container': 'flac',
          },
        ],
      },
    ],
  };

  // the same songs as the fake Navidrome's getAlbum, under Plex keys
  late final List<Map<String, Object?>> _songs = [
    _songJson('321', 'Night Drive', 'Kavinsky', 1, 'Synthwave', 215),
    _songJson('322', 'Surf Break', 'Johnny', 2, 'Surf', 180),
  ];

  Future<void> _handlePms(HttpRequest req) async {
    final res = req.response;
    if (down) {
      (await res.detachSocket(writeHeaders: false)).destroy();
      return;
    }
    final path = req.uri.path;
    final q = req.uri.queryParameters;
    var what = '${req.method} $path';
    final logged = <String, String>{...q};
    await req.drain<void>();
    void json(Object body) {
      res.headers.contentType = ContentType.json;
      res.write(jsonEncode({'MediaContainer': body}));
    }

    // a page of [all], as `X-Plex-Container-Start/Size` ask for it
    void page(List<Map<String, Object?>> all) {
      final start =
          int.tryParse(req.headers.value('x-plex-container-start') ?? '') ?? 0;
      final size =
          int.tryParse(req.headers.value('x-plex-container-size') ?? '') ??
          all.length;
      final items = start >= all.length
          ? const <Map<String, Object?>>[]
          : all.sublist(start, (start + size).clamp(0, all.length));
      json({
        'size': items.length,
        'totalSize': all.length,
        'offset': start,
        'Metadata': items,
      });
    }

    void audio() {
      res.headers.contentType = ContentType('audio', 'flac');
      res.contentLength = _song.length;
      res.add(_song);
    }

    Map<String, Object?>? song(String key) {
      for (final s in _songs) {
        if (s['ratingKey'] == key) return s;
      }
      return null;
    }

    final seg = req.uri.pathSegments;
    if (req.method == 'GET' && path == '/identity') {
      what = 'identity';
      json({'size': 0, 'claimed': true, 'machineIdentifier': machineId});
    } else if (req.headers.value('x-plex-token') != serverToken &&
        q['X-Plex-Token'] != serverToken) {
      res.statusCode = HttpStatus.unauthorized;
    } else if (path == '/library/sections') {
      what = 'sections';
      json({
        'size': 1,
        'Directory': [
          {'key': '1', 'type': 'artist', 'title': 'Musique'},
        ],
      });
    } else if (path == '/library/sections/1/all') {
      what = 'albums';
      page(const [_album]);
    } else if (path == '/library/metadata/$albumKey/children') {
      what = 'children';
      page(_songs);
    } else if (seg.length == 3 &&
        seg[0] == 'library' &&
        seg[1] == 'metadata' &&
        song(seg[2]) != null) {
      what = 'song';
      logged['id'] = seg[2];
      page([song(seg[2])!]);
    } else if (path == '/playlists') {
      what = 'playlists';
      page(const []);
    } else if (path == '/photo/:/transcode') {
      what = 'cover';
      res.headers.contentType = ContentType('image', 'png');
      res.contentLength = _png.length;
      res.add(_png);
    } else if (path.startsWith('/library/parts/') && path.endsWith('.flac')) {
      what = q['download'] == '1' ? 'download' : 'stream';
      logged['part'] = seg[2];
      audio();
    } else if (path == '/:/scrobble') {
      what = 'scrobble';
      final key = q['key'] ?? '';
      if (song(key) == null) {
        res.statusCode = HttpStatus.notFound;
      } else {
        _plays[key] = playCount(key) + 1;
      }
    } else {
      res.statusCode = HttpStatus.notFound;
    }
    requests.add(FakeRequest(what, res.statusCode, logged));
    await res.close();
  }
}
