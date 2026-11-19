// A small Subsonic server for the end-to-end run (plan 1, task 10), in the test process itself.
// It answers from the responses recorded in test/fixtures/subsonic/ (copied below: a phone can't
// read the repo; test/fake_subsonic_test.dart checks they still match) and streams (and gives for download) a.flac.
// Like a Navidrome behind a proxy, it refuses every request without `X-Lafleur-Test: ok` (403),
// and it checks the token: md5(password + salt), otherwise Subsonic error 40.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'fixture_bytes.dart';

const fakeHeader = 'X-Lafleur-Test';
const fakeHeaderValue = 'ok';

/// test/fixtures/subsonic/ping.json
const pingJson =
    '{"subsonic-response":{"status":"ok","version":"1.16.1","type":"navidrome",'
    '"serverVersion":"0.54.0","openSubsonic":true}}';

/// test/fixtures/subsonic/error40.json
const error40Json =
    '{"subsonic-response":{"status":"failed","version":"1.16.1","type":"navidrome",'
    '"serverVersion":"0.54.0","openSubsonic":true,'
    '"error":{"code":40,"message":"Wrong username or password"}}}';

/// test/fixtures/subsonic/getAlbumList2.json
const albumList2Json =
    '{"subsonic-response":{"status":"ok","version":"1.16.1","type":"navidrome",'
    '"serverVersion":"0.54.0","openSubsonic":true,"albumList2":{"album":['
    '{"id":"al-1","name":"Studio Lafleur","artist":"LAFLEURSTUDIO","artistId":"ar-1",'
    '"coverArt":"al-1","songCount":10,"duration":2400,"year":2024},'
    '{"id":"al-2","name":"Lafleur Surf","artist":"Johnny","artistId":"ar-2",'
    '"coverArt":"al-2","songCount":8,"duration":1900,"year":2023},'
    '{"id":"al-3","name":"Summer Mix","artist":"Divers","artistId":"ar-3",'
    '"songCount":12,"duration":3100}]}}}';

/// test/fixtures/subsonic/getAlbum.json
const albumJson =
    '{"subsonic-response":{"status":"ok","version":"1.16.1","type":"navidrome",'
    '"serverVersion":"0.54.0","openSubsonic":true,"album":{"id":"al-1",'
    '"name":"Studio Lafleur","artist":"LAFLEURSTUDIO","coverArt":"al-1","songCount":2,"song":['
    '{"id":"s-1","title":"Night Drive","artist":"Kavinsky","album":"Studio Lafleur",'
    '"albumArtist":"LAFLEURSTUDIO","track":1,"discNumber":1,"genre":"Synthwave",'
    '"duration":215,"size":8601234,"suffix":"flac","coverArt":"al-1","playCount":3,'
    '"replayGain":{"trackGain":-6.5,"albumGain":-7.2,"trackPeak":0.98}},'
    '{"id":"s-2","title":"Surf Break","artist":"Johnny","album":"Studio Lafleur",'
    '"albumArtist":"LAFLEURSTUDIO","track":2,"genre":"Surf","duration":180.5,'
    '"size":5400000,"suffix":"mp3","coverArt":"al-1"}]}}}';

/// A second album, one song, for the offline run (`secondAlbum: true`): the one never kept.
const album2Json =
    '{"subsonic-response":{"status":"ok","version":"1.16.1","type":"navidrome",'
    '"serverVersion":"0.54.0","openSubsonic":true,"album":{"id":"al-2",'
    '"name":"Lafleur Surf","artist":"Johnny","coverArt":"al-2","songCount":1,"song":['
    '{"id":"s-3","title":"Wave Rider","artist":"Johnny","album":"Lafleur Surf",'
    '"albumArtist":"Johnny","track":1,"genre":"Surf","duration":3,'
    '"size":54439,"suffix":"flac","coverArt":"al-2"}]}}}';

/// 1×1 PNG for getCoverArt.
const _pngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

/// Every request the server saw: method name (`ping`, `stream`…) and its outcome.
class FakeRequest {
  FakeRequest(this.method, this.status, this.params);
  final String method;
  final int status;
  final Map<String, String> params;
  @override
  String toString() => '$method → $status';
}

class FakeSubsonic {
  FakeSubsonic._(
    this._server,
    this.user,
    this.password,
    this.secondAlbum,
    this.topPlays,
    this.playlists,
  );

  final HttpServer _server;
  final String user, password;
  final bool secondAlbum;

  /// The songs carry a play count: the Top 100 is not empty, so at home the app keeps them
  /// by itself. Off: nothing is kept unless the run asks for it.
  final bool topPlays;
  final requests = <FakeRequest>[];

  /// Server playlists (getPlaylists / getPlaylist): id → (name, song ids). Empty: none.
  final Map<String, (String, List<String>)> playlists;

  /// Cuts the server: every connection is closed without an answer (the app sees a network
  /// error, like a phone out of reach of its server). Nothing is recorded in [requests].
  bool down = false;

  /// Connections cut while [down].
  int refused = 0;
  final _song = base64Decode(aFlacBase64);
  final _png = base64Decode(_pngBase64);

  /// Serves on 127.0.0.1, random port.
  static Future<FakeSubsonic> start({
    String user = 'johnny',
    String password = 'lafleur-e2e',
    bool secondAlbum = false,
    bool topPlays = true,
    Map<String, (String, List<String>)> playlists = const {},
  }) async {
    // port 0: every call gets its own port, so two servers can run at once
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = FakeSubsonic._(
      server,
      user,
      password,
      secondAlbum,
      topPlays,
      playlists,
    );
    server.listen(fake._handle);
    return fake;
  }

  String get address => 'http://127.0.0.1:${_server.port}';

  Future<void> close() => _server.close(force: true);

  /// Only the albums whose songs we recorded (al-1), so the library is consistent.
  String get _albumList {
    final d = jsonDecode(albumList2Json) as Map<String, dynamic>;
    final r = d['subsonic-response'] as Map<String, dynamic>;
    final list = ((r['albumList2'] as Map)['album'] as List)
        .cast<Map<String, dynamic>>()
        .where((a) => a['id'] == 'al-1' || (secondAlbum && a['id'] == 'al-2'))
        .map(
          (a) => a['id'] == 'al-1'
              ? {...a, 'songCount': 2, 'duration': 395}
              : {...a, 'songCount': 1, 'duration': 3},
        )
        .toList();
    (r['albumList2'] as Map)['album'] = list;
    return jsonEncode(d);
  }

  static const _ok = {
    'status': 'ok',
    'version': '1.16.1',
    'type': 'navidrome',
    'serverVersion': '0.54.0',
    'openSubsonic': true,
  };

  bool _authOk(Map<String, String> q) {
    final salt = q['s'], token = q['t'];
    if (q['u'] != user || salt == null || token == null) return false;
    return md5.convert(utf8.encode('$password$salt')).toString() == token;
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    if (down) {
      refused++;
      (await res.detachSocket(writeHeaders: false)).destroy();
      return;
    }
    final q = req.uri.queryParameters;
    final last = req.uri.pathSegments.isEmpty ? '' : req.uri.pathSegments.last;
    final method = last.endsWith('.view')
        ? last.substring(0, last.length - '.view'.length)
        : last;
    void json(String body) {
      res.headers.contentType = ContentType.json;
      res.write(body);
    }

    if (req.headers.value(fakeHeader) != fakeHeaderValue) {
      res.statusCode = HttpStatus.forbidden;
      res.write('Forbidden');
    } else if (!req.uri.path.contains('/rest/')) {
      res.statusCode = HttpStatus.notFound;
    } else if (!_authOk(q)) {
      json(error40Json);
    } else {
      switch (method) {
        case 'ping':
        case 'scrobble':
          json(pingJson);
        case 'getAlbumList2':
          // one page: the second one (offset > 0) is empty
          json(
            (int.tryParse(q['offset'] ?? '0') ?? 0) > 0
                ? albumList2Json.replaceFirst(
                    RegExp(r'"album":\[.*\]'),
                    '"album":[]',
                  )
                : _albumList,
          );
        case 'getAlbum':
          if (q['id'] == 'al-1') {
            json(
              topPlays
                  ? albumJson
                  : albumJson.replaceFirst(',"playCount":3', ''),
            );
          } else if (secondAlbum && q['id'] == 'al-2') {
            json(album2Json);
          } else {
            res.statusCode = HttpStatus.notFound;
          }
        case 'getPlaylists':
          json(
            jsonEncode({
              'subsonic-response': {
                ..._ok,
                'playlists': {
                  'playlist': [
                    for (final e in playlists.entries)
                      {
                        'id': e.key,
                        'name': e.value.$1,
                        'songCount': e.value.$2.length,
                      },
                  ],
                },
              },
            }),
          );
        case 'getPlaylist':
          final pl = playlists[q['id']];
          if (pl == null) {
            res.statusCode = HttpStatus.notFound;
          } else {
            json(
              jsonEncode({
                'subsonic-response': {
                  ..._ok,
                  'playlist': {
                    'id': q['id'],
                    'name': pl.$1,
                    'songCount': pl.$2.length,
                    'entry': [
                      for (final id in pl.$2) {'id': id},
                    ],
                  },
                },
              }),
            );
          }
        case 'getCoverArt':
          res.headers.contentType = ContentType('image', 'png');
          res.contentLength = _png.length;
          res.add(_png);
        case 'stream':
        case 'download':
          if (const ['s-1', 's-2', 's-3'].contains(q['id'])) {
            res.headers.contentType = ContentType('audio', 'flac');
            res.contentLength = _song.length;
            res.add(_song);
          } else {
            res.statusCode = HttpStatus.notFound;
          }
        default:
          res.statusCode = HttpStatus.notFound;
      }
    }
    // never the token or the salt in the log
    requests.add(
      FakeRequest(method, res.statusCode, {
        for (final e in q.entries)
          if (e.key != 't' && e.key != 's') e.key: e.value,
      }),
    );
    await res.close();
  }
}
