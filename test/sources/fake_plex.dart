import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lafleurmusic/sources/plex.dart';
import 'package:lafleurmusic/sources/plex_link.dart';

import 'fake_secret_store.dart';

/// A fake plex.tv and fake Plex Media Servers (never the real ones). Addresses are
/// documentation ranges (RFC 5737) dressed as plex.direct names.

http.Response jsonResponse(String body, [int code = 200]) =>
    http.Response(body, code, headers: {'content-type': 'application/json'});

const homeLocal = '192-168-1-20.hash.plex.direct';
const homeRemote = '203-0-113-7.hash.plex.direct';
const homeRelay = 'relay.plex.direct';
const officeRemote = '198-51-100-4.hash2.plex.direct';

/// Remote listed first on purpose: the app orders them itself.
const homeResource =
    '''
{"name":"Maison","product":"Plex Media Server","provides":"server",
 "clientIdentifier":"mach-home","accessToken":"server-token-home","owned":true,
 "connections":[
  {"protocol":"https","address":"203.0.113.7","port":32400,"uri":"https://$homeRemote:32400","local":false,"relay":false,"IPv6":false},
  {"protocol":"https","address":"192.168.1.20","port":32400,"uri":"https://$homeLocal:32400","local":true,"relay":false,"IPv6":false},
  {"protocol":"https","address":"relay","port":8443,"uri":"https://$homeRelay:8443","local":false,"relay":true,"IPv6":false}
 ]}''';

const officeResource =
    '''
{"name":"Bureau","product":"Plex Media Server","provides":"server",
 "clientIdentifier":"mach-office","accessToken":"server-token-office","owned":false,
 "connections":[
  {"protocol":"https","address":"198.51.100.4","port":32400,"uri":"https://$officeRemote:32400","local":false,"relay":false,"IPv6":false}
 ]}''';

const playerResource = '''
{"name":"iPhone de Max","product":"Plexamp","provides":"client,player",
 "clientIdentifier":"player-1","connections":[]}''';

/// Plex Media Servers answering on the hosts above.
class FakePms {
  final log = <http.Request>[];

  /// Hosts that never answer (a SocketException).
  Set<String> down = {};

  /// Hosts that never answer at all (the request hangs).
  Set<String> hang = {};

  /// Hosts answered by some other server (another machineIdentifier).
  Set<String> otherMachine = {};

  /// Hosts that answer late.
  Map<String, Duration> delay = {};

  /// Tokens the servers accept; anything else is a 401.
  Set<String> tokens = {'server-token-home', 'server-token-office'};

  static String? machineOf(String host) => switch (host) {
    homeLocal || homeRemote || homeRelay => 'mach-home',
    officeRemote => 'mach-office',
    _ => null,
  };

  Future<http.Response> handle(http.Request r) async {
    log.add(r);
    final host = r.url.host;
    final d = delay[host];
    if (d != null) await Future<void>.delayed(d);
    if (hang.contains(host)) await Completer<void>().future;
    if (down.contains(host)) throw const SocketException('no route to host');
    final machine = otherMachine.contains(host)
        ? 'someone-else'
        : machineOf(host);
    if (machine == null) throw const SocketException('unknown host');
    switch (r.url.path) {
      case '/identity':
        return jsonResponse(
          '{"MediaContainer":{"size":0,"claimed":true,'
          '"machineIdentifier":"$machine","version":"1.41.0"}}',
        );
      case '/library/sections':
        if (!tokens.contains(r.headers['X-Plex-Token'])) {
          return http.Response('<html>Unauthorized</html>', 401);
        }
        final dirs = machine == 'mach-home'
            ? '[{"key":"1","type":"artist","title":"Musique"},'
                  '{"key":"2","type":"movie","title":"Films"},'
                  '{"key":"3","type":"artist","title":"Concerts"}]'
            : '[{"key":"1","type":"artist","title":"Musique"}]';
        return jsonResponse('{"MediaContainer":{"size":3,"Directory":$dirs}}');
    }
    return http.Response('', 404);
  }

  MockClient client() => MockClient(handle);
}

/// plex.tv: PIN codes and the account's resources; other hosts go to [pms].
class FakePlexTv {
  FakePlexTv({FakePms? pms}) : pms = pms ?? FakePms();
  final FakePms pms;
  final log = <http.Request>[];

  /// The code is validated on this poll (1 = the first); null = never.
  int? validateAfter = 1;
  int pinStatus = 201;
  int resourcesStatus = 200;
  int expiresIn = 900;

  /// plex.tv forgot the PIN (404 on poll).
  bool forgetPins = false;

  /// The next polls fail with a network error.
  int failPolls = 0;
  String userToken = 'user-token-1';

  /// Who owns [userToken] on plex.tv (`GET /api/v2/user`).
  String userUuid = 'user-uuid-1';
  int userStatus = 200;

  /// plex.tv does not answer at all.
  bool down = false;

  /// plex.tv never answers (the request hangs).
  bool hang = false;
  List<String> resources = [homeResource, officeResource, playerResource];
  int _polls = 0;
  int pinsMade = 0;

  /// Codes handed out, one per request.
  List<String> codes = ['K7QX', 'B2RT', 'M9LP'];

  Future<http.Response> handle(http.Request r) async {
    if (r.url.host != 'plex.tv') return pms.handle(r);
    log.add(r);
    if (down) throw const SocketException('plex.tv down');
    if (hang) await Completer<void>().future;
    final path = r.url.path;
    if (r.method == 'POST' && path == '/api/v2/pins') {
      if (pinStatus >= 300) return http.Response('', pinStatus);
      final code = codes[pinsMade % codes.length];
      pinsMade++;
      _polls = 0;
      return jsonResponse(
        '{"id":${1233 + pinsMade},"code":"$code","trusted":false,'
        '"expiresIn":$expiresIn,"expiresAt":"2026-11-19T10:15:00Z",'
        '"authToken":null}',
        201,
      );
    }
    if (r.method == 'GET' && path.startsWith('/api/v2/pins/')) {
      if (failPolls > 0) {
        failPolls--;
        throw const SocketException('blip');
      }
      if (forgetPins) return http.Response('', 404);
      _polls++;
      final v = validateAfter;
      final token = v != null && _polls >= v ? '"$userToken"' : 'null';
      return jsonResponse(
        '{"id":${path.split('/').last},"code":"K7QX","authToken":$token}',
      );
    }
    if (r.method == 'GET' && path == '/api/v2/user') {
      if (userStatus != 200) return http.Response('', userStatus);
      if (r.headers['X-Plex-Token'] != userToken) {
        return http.Response('', 401);
      }
      return jsonResponse(
        '{"id":42,"uuid":"$userUuid","username":"max","title":"max"}',
      );
    }
    if (r.method == 'GET' && path == '/api/v2/resources') {
      if (resourcesStatus != 200) return http.Response('', resourcesStatus);
      if (r.headers['X-Plex-Token'] != userToken) {
        return http.Response('', 401);
      }
      return jsonResponse('[${resources.join(',')}]');
    }
    return http.Response('', 404);
  }

  MockClient client() => MockClient(handle);

  PlexLink link({DateTime Function()? now}) => PlexLink(
    clientId: 'client-abc',
    client: client(),
    deviceName: 'iPhone',
    platform: 'iOS',
    now: now,
  );
}

/// Decoded JSON of a resource above.
Map resourceJson(String r) => jsonDecode(r) as Map;

const albumOf = {
  '101': '11',
  '102': '11',
  '121': '12',
  '122': '12',
  '211': '21',
};

/// A fake Plex Media Server: songs (`/library/metadata/{id}`), albums' children, listens.
class Pms {
  final pms = FakePms();
  final log = <http.Request>[];
  Set<String> gone = {}; // songs the server doesn't have
  Set<String> noPart = {}; // songs that have no file
  Set<String> childrenFailing = {};
  Map<String, int> scrobbleStatus = {}; // per key
  int songStatus = 200; // forced status for a song read
  bool twoParts = false;

  Map song(String id) {
    final file = File('test/fixtures/plex/children_${albumOf[id]}.json');
    final items =
        (jsonDecode(file.readAsStringSync())['MediaContainer']['Metadata']
                as List)
            .cast<Map>();
    final m = Map.of(items.firstWhere((m) => m['ratingKey'] == id));
    m['parentRatingKey'] = albumOf[id];
    if (noPart.contains(id)) {
      m['Media'] = [<String, Object?>{}];
    } else if (twoParts) {
      final media = Map.of((m['Media'] as List).first as Map);
      media['Part'] = [
        ...(media['Part'] as List),
        {'id': 9, 'key': '/library/parts/9/1/file.wav', 'size': 1},
      ];
      m['Media'] = [media];
    }
    return m;
  }

  bool isDown(http.Request r) => pms.down.contains(r.url.host);

  Future<http.Response> handle(http.Request r) async {
    final p = r.url.path;
    if (isDown(r)) throw const SocketException('no route to host');
    if (r.url.host == homeLocal || r.url.host == homeRemote) {
      final one = RegExp(r'^/library/metadata/(\d+)$').firstMatch(p);
      if (one != null) {
        log.add(r);
        final id = one.group(1)!;
        if (songStatus != 200) return http.Response('', songStatus);
        if (gone.contains(id) || !albumOf.containsKey(id)) {
          return http.Response('', 404);
        }
        return jsonResponse(
          jsonEncode({
            'MediaContainer': {
              'size': 1,
              'Metadata': [song(id)],
            },
          }),
        );
      }
      final kids = RegExp(r'^/library/metadata/(\d+)/children$').firstMatch(p);
      if (kids != null) {
        log.add(r);
        final id = kids.group(1)!;
        if (childrenFailing.contains(id)) return http.Response('', 500);
        final f = File('test/fixtures/plex/children_$id.json');
        return f.existsSync()
            ? jsonResponse(f.readAsStringSync())
            : http.Response('', 404);
      }
      if (p == '/:/scrobble') {
        log.add(r);
        final k = r.url.queryParameters['key'];
        final code = scrobbleStatus[k] ?? 200;
        return http.Response('', code);
      }
    }
    return pms.handle(r);
  }

  PlexSource source({
    FakeSecretStore? secrets,
    DateTime Function()? now,
    int? partsMax,
  }) {
    final s = secrets ?? FakeSecretStore();
    s.data[PlexSource.tokenKey('acc1')] = 'server-token-home';
    return PlexSource(
      accountId: 'acc1',
      server: PlexServer.fromResource(resourceJson(homeResource))!,
      clientId: 'client-abc',
      client: MockClient(handle),
      secrets: s,
      deviceName: 'iPhone',
      platform: 'iOS',
      now: now,
      partsMax: partsMax ?? 20000,
    );
  }

  List<String> get paths => [for (final r in log) r.url.path];
}
