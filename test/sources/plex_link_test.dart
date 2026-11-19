import 'dart:convert';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:lafleurmusic/app_version.dart';
import 'package:lafleurmusic/sources/plex_link.dart';

import 'fake_plex.dart';

void main() {
  group('PIN code', () {
    test(
      'POST plex.tv/api/v2/pins?strong=false, Plex headers, no token',
      () async {
        final tv = FakePlexTv();
        final link = tv.link();
        final pin = await link.requestPin();
        expect(pin.code, 'K7QX');
        expect(pin.id, 1234);
        final r = tv.log.single;
        expect(r.method, 'POST');
        expect(r.url.toString(), 'https://plex.tv/api/v2/pins?strong=false');
        expect(r.headers['X-Plex-Product'], 'LAFLEURMUSIC');
        expect(r.headers['X-Plex-Client-Identifier'], 'client-abc');
        expect(r.headers['X-Plex-Version'], appVersion);
        expect(r.headers['X-Plex-Platform'], 'iOS');
        expect(r.headers['X-Plex-Device-Name'], 'iPhone');
        expect(r.headers['Accept'], 'application/json');
        expect(r.headers.containsKey('X-Plex-Token'), isFalse);
      },
    );

    test('plex.tv refuses: a PlexException, no code', () async {
      final tv = FakePlexTv()..pinStatus = 503;
      await expectLater(tv.link().requestPin(), throwsA(isA<PlexException>()));
    });

    test('plex.tv unreachable: a PlexException (no URL in its text)', () async {
      final link = PlexLink(
        clientId: 'client-abc',
        client: MockClient((_) async => throw const SocketException('down')),
      );
      final e = await link.requestPin().then<Object?>(
        (_) => null,
        onError: (Object e) => e,
      );
      expect(e, isA<PlexException>());
      expect('$e', isNot(contains('plex.tv/api')));
    });

    test('polls GET /api/v2/pins/{id} every 2 s until the token', () {
      fakeAsync((fa) {
        final tv = FakePlexTv()..validateAfter = 3;
        final link = tv.link(now: fa.getClock(DateTime.utc(2026, 11, 19)).now);
        late PlexPin pin;
        link.requestPin().then((p) => pin = p);
        fa.flushMicrotasks();
        tv.log.clear();
        String? token;
        final wait = link.poll(pin);
        wait.token.then((t) => token = t);
        fa.flushMicrotasks();
        expect(tv.log, hasLength(1));
        fa.elapse(const Duration(milliseconds: 1999));
        expect(tv.log, hasLength(1));
        fa.elapse(const Duration(milliseconds: 1));
        expect(tv.log, hasLength(2));
        fa.elapse(const Duration(seconds: 2));
        expect(tv.log, hasLength(3));
        expect(token, 'user-token-1');
        expect(wait.expired, isFalse);
        for (final r in tv.log) {
          expect(r.method, 'GET');
          expect(r.url.toString(), 'https://plex.tv/api/v2/pins/1234');
          expect(r.headers['X-Plex-Client-Identifier'], 'client-abc');
        }
        // done: no timer left behind
        expect(fa.pendingTimers, isEmpty);
        fa.elapse(const Duration(minutes: 1));
        expect(tv.log, hasLength(3));
      });
    });

    test('Focus 1: never validated, the wait stops when the code expires', () {
      fakeAsync((fa) {
        final tv = FakePlexTv()..validateAfter = null;
        final link = tv.link(now: fa.getClock(DateTime.utc(2026, 11, 19)).now);
        late PlexPin pin;
        link.requestPin().then((p) => pin = p);
        fa.flushMicrotasks();
        tv.log.clear();
        var done = false;
        String? token = 'unset';
        final wait = link.poll(pin);
        wait.token.then((t) {
          done = true;
          token = t;
        });
        fa.elapse(const Duration(minutes: 14, seconds: 59));
        expect(done, isFalse);
        fa.elapse(const Duration(seconds: 2));
        expect(done, isTrue);
        expect(token, isNull);
        expect(wait.expired, isTrue);
        // one poll each 2 s over the 15 minutes, then nothing more
        expect(tv.log.length, inInclusiveRange(449, 451));
        expect(fa.pendingTimers, isEmpty);
        final n = tv.log.length;
        fa.elapse(const Duration(minutes: 5));
        expect(tv.log, hasLength(n));
      });
    });

    test(
      'the deadline is the PIN\'s own lifetime (expiresIn), not a fixed 15 min',
      () {
        fakeAsync((fa) {
          final tv = FakePlexTv()
            ..validateAfter = null
            ..expiresIn = 60;
          final link = tv.link(
            now: fa.getClock(DateTime.utc(2026, 11, 19)).now,
          );
          late PlexPin pin;
          link.requestPin().then((p) => pin = p);
          fa.flushMicrotasks();
          final wait = link.poll(pin);
          var done = false;
          wait.token.then((_) => done = true);
          fa.elapse(const Duration(seconds: 61));
          expect(done, isTrue);
          expect(wait.expired, isTrue);
          expect(fa.pendingTimers, isEmpty);
        });
      },
    );

    test('cancel stops the polling at once, no timer left', () {
      fakeAsync((fa) {
        final tv = FakePlexTv()..validateAfter = null;
        final link = tv.link(now: fa.getClock(DateTime.utc(2026, 11, 19)).now);
        late PlexPin pin;
        link.requestPin().then((p) => pin = p);
        fa.flushMicrotasks();
        tv.log.clear();
        String? token = 'unset';
        final wait = link.poll(pin);
        wait.token.then((t) => token = t);
        fa.elapse(const Duration(seconds: 5));
        final n = tv.log.length;
        wait.cancel();
        fa.flushMicrotasks();
        expect(token, isNull);
        expect(wait.expired, isFalse);
        expect(fa.pendingTimers, isEmpty);
        fa.elapse(const Duration(minutes: 20));
        expect(tv.log, hasLength(n));
      });
    });

    test('a PIN plex.tv no longer knows (404) is expired', () async {
      final tv = FakePlexTv()..validateAfter = null;
      final link = tv.link();
      final pin = await link.requestPin();
      tv.forgetPins = true;
      final wait = link.poll(pin);
      expect(await wait.token, isNull);
      expect(wait.expired, isTrue);
    });

    test('a network blip while waiting: the polling goes on', () {
      fakeAsync((fa) {
        final tv = FakePlexTv()..validateAfter = 3;
        final link = tv.link(now: fa.getClock(DateTime.utc(2026, 11, 19)).now);
        late PlexPin pin;
        link.requestPin().then((p) => pin = p);
        fa.flushMicrotasks();
        tv.failPolls = 1;
        String? token;
        link.poll(pin).token.then((t) => token = t);
        fa.elapse(const Duration(seconds: 7));
        expect(token, 'user-token-1');
      });
    });
  });

  group('servers', () {
    test(
      'GET /api/v2/resources?includeHttps=1&includeRelay=1, servers only',
      () async {
        final tv = FakePlexTv();
        final servers = await tv.link().servers('user-token-1');
        final r = tv.log.single;
        expect(
          r.url.toString(),
          'https://plex.tv/api/v2/resources?includeHttps=1&includeRelay=1',
        );
        expect(r.headers['X-Plex-Token'], 'user-token-1');
        expect(r.headers['X-Plex-Product'], 'LAFLEURMUSIC');
        // the player is not a server
        expect([for (final s in servers) s.name], ['Maison', 'Bureau']);
        final home = servers.first;
        expect(home.machineId, 'mach-home');
        expect(home.accessToken, 'server-token-home');
        expect(home.connections, hasLength(3));
      },
    );

    test('token refused by plex.tv: PlexException without the token', () async {
      final tv = FakePlexTv()..resourcesStatus = 401;
      final e = await tv
          .link()
          .servers('user-token-1')
          .then<Object?>((_) => null, onError: (Object e) => e);
      expect(e, isA<PlexException>());
      expect((e as PlexException).tokenRefused, isTrue);
      expect('$e', isNot(contains('user-token-1')));
    });

    test('connections are ordered: local, then remote, then relay', () {
      final s = PlexServer.fromResource(jsonDecode(homeResource) as Map)!;
      final ordered = orderConnections(s.connections);
      expect(
        [for (final c in ordered) c.uri.host],
        [
          '192-168-1-20.hash.plex.direct',
          '203-0-113-7.hash.plex.direct',
          'relay.plex.direct',
        ],
      );
    });

    test('the stored server never carries the token', () {
      final s = PlexServer.fromResource(jsonDecode(homeResource) as Map)!;
      final again = PlexServer.fromJson(jsonDecode(jsonEncode(s.toJson())));
      expect(jsonEncode(s.toJson()), isNot(contains('server-token-home')));
      expect(again.machineId, 'mach-home');
      expect(again.name, 'Maison');
      expect(again.accessToken, isNull);
      expect(
        [for (final c in again.connections) c.uri],
        [for (final c in s.connections) c.uri],
      );
      expect(
        [for (final c in again.connections) (c.local, c.relay)],
        [for (final c in s.connections) (c.local, c.relay)],
      );
    });
  });

  group('Focus 2: best address (GET /identity)', () {
    final server = PlexServer.fromResource(jsonDecode(homeResource) as Map)!;

    Future<PlexConnection?> best(FakePms pms) =>
        bestConnection(pms.client(), server, headers: const {'X-Custom': '1'});

    test('at home: the local address', () async {
      final pms = FakePms();
      final c = await best(pms);
      expect(c?.local, isTrue);
      expect(c?.uri.host, '192-168-1-20.hash.plex.direct');
      final probes = pms.log.where((r) => r.url.path == '/identity');
      expect(probes, isNotEmpty);
      expect(probes.first.headers['X-Custom'], '1');
    });

    test('local silent: the remote one', () async {
      final pms = FakePms()..down = {'192-168-1-20.hash.plex.direct'};
      final c = await best(pms);
      expect(c?.uri.host, '203-0-113-7.hash.plex.direct');
    });

    test('local and remote silent: the relay', () async {
      final pms = FakePms()
        ..down = {
          '192-168-1-20.hash.plex.direct',
          '203-0-113-7.hash.plex.direct',
        };
      final c = await best(pms);
      expect(c?.relay, isTrue);
    });

    test('a local address answered by another server is skipped', () async {
      final pms = FakePms()..otherMachine = {'192-168-1-20.hash.plex.direct'};
      final c = await best(pms);
      expect(c?.uri.host, '203-0-113-7.hash.plex.direct');
    });

    test('the local one wins even when the remote one answers first', () async {
      final pms = FakePms()
        ..delay = {
          '192-168-1-20.hash.plex.direct': const Duration(milliseconds: 50),
        };
      final c = await best(pms);
      expect(c?.local, isTrue);
    });

    test('nothing answers: null', () async {
      final pms = FakePms()
        ..down = {
          '192-168-1-20.hash.plex.direct',
          '203-0-113-7.hash.plex.direct',
          'relay.plex.direct',
        };
      expect(await best(pms), isNull);
    });
  });

  group('probe (server choice)', () {
    test('where it answers and how many music libraries', () async {
      final server = PlexServer.fromResource(jsonDecode(homeResource) as Map)!;
      final pms = FakePms();
      final link = PlexLink(clientId: 'client-abc', client: pms.client());
      final p = await link.probe(server);
      expect(p.connection?.local, isTrue);
      expect(p.musicLibraries, 2);
      final sections = pms.log.singleWhere(
        (r) => r.url.path == '/library/sections',
      );
      expect(sections.headers['X-Plex-Token'], 'server-token-home');
      expect(sections.url.query, isNot(contains('token')));
    });

    test('a server that answers nowhere: no address, no count', () async {
      final server = PlexServer.fromResource(jsonDecode(homeResource) as Map)!;
      final pms = FakePms()
        ..down = {
          '192-168-1-20.hash.plex.direct',
          '203-0-113-7.hash.plex.direct',
          'relay.plex.direct',
        };
      final link = PlexLink(clientId: 'client-abc', client: pms.client());
      final p = await link.probe(server);
      expect(p.connection, isNull);
      expect(p.musicLibraries, isNull);
    });
  });

  test('Plex header values have no comma (mpv splits on them)', () {
    final h = plexHeaders(
      clientId: 'client-abc',
      deviceName: 'iPhone',
      platform: 'iOS',
      token: 'tok',
    );
    for (final v in h.values) {
      expect(v, isNot(contains(',')));
    }
    expect(h['X-Plex-Token'], 'tok');
  });
}
