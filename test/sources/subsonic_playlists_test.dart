import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lafleurmusic/sources/source.dart';

import 'fake_playlist_servers.dart';

import 'package:lafleurmusic/sources/subsonic.dart';

SubsonicSource make(http.Client c, {Map<String, String> headers = const {}}) =>
    SubsonicSource(
      accountId: 'acc1',
      base: Uri.parse('https://music.example.com'),
      user: 'johnny',
      password: 'pw-secret',
      headers: headers,
      client: c,
      salt: () => 'abc',
    );

List<String> songs(FakeNavidrome s, String id) => s.lists[id]!.songs;

void main() {
  late FakeNavidrome server;
  late SubsonicSource src;
  setUp(() {
    server = FakeNavidrome();
    src = make(server.client(), headers: {'X-Proxy': 'k'});
  });

  test('a Subsonic source writes playlists', () {
    expect(src, isA<PlaylistWriter>());
  });

  test('createPlaylist returns the new id; the account headers go with every '
      'write; the password never travels', () async {
    final id = await src.createPlaylist('Soirée');
    expect(id, 'pl10');
    expect(server.lists['pl10']!.name, 'Soirée');
    expect(songs(server, 'pl10'), isEmpty);
    for (final r in server.log) {
      expect(r.headers['X-Proxy'], 'k');
      expect(r.url.toString(), isNot(contains('pw-secret')));
    }
  });

  test('createPlaylist on an old server (no playlist in the answer) finds the '
      'new one by name', () async {
    server.oldCreate = true;
    server.lists['pl2'] = (name: 'Soirée', songs: ['s9']);
    final id = await src.createPlaylist('Soirée');
    expect(id, 'pl10'); // the last one with that name: the one just made
  });

  test(
    'addToPlaylist appends in order, a song twice when sent twice',
    () async {
      await src.addToPlaylist('pl1', ['s4', 's1']);
      expect(songs(server, 'pl1'), ['s1', 's2', 's3', 's4', 's1']);
      final add = server.log.last.url.queryParametersAll['songIdToAdd'];
      expect(add, ['s4', 's1']);
    },
  );

  test('removeFromPlaylist takes the rows at those positions out', () async {
    await src.removeFromPlaylist('pl1', [2, 0]);
    expect(songs(server, 'pl1'), ['s2']);
  });

  test('renamePlaylist and deletePlaylist', () async {
    await src.renamePlaylist('pl1', 'Route');
    expect(server.lists['pl1']!.name, 'Route');
    expect(songs(server, 'pl1'), ['s1', 's2', 's3']);
    await src.deletePlaylist('pl1');
    expect(server.lists, isEmpty);
  });

  test('readPlaylist: the name and the songs in order', () async {
    final p = await src.readPlaylist('pl1');
    expect((p.id, p.name), ('pl1', 'Road'));
    expect(p.songIds, ['s1', 's2', 's3']);
  });

  group('movePlaylistItem', () {
    test('rewrites the whole list with createPlaylist?playlistId=', () async {
      await src.movePlaylistItem('pl1', 0, 2);
      expect(songs(server, 'pl1'), ['s2', 's3', 's1']);
      expect(server.lists['pl1']!.name, 'Road');
      final w = server.log.last;
      expect(w.url.path, endsWith('/createPlaylist.view'));
      expect(w.url.queryParameters['playlistId'], 'pl1');
      expect(w.url.queryParametersAll['songId'], ['s2', 's3', 's1']);
      await src.movePlaylistItem('pl1', 2, 0);
      expect(songs(server, 'pl1'), ['s1', 's2', 's3']);
    });

    test('out of range: nothing sent', () async {
      await expectLater(src.movePlaylistItem('pl1', 0, 3), throwsRangeError);
      expect(server.log.where((r) => r.url.path.contains('create')), isEmpty);
    });

    final long = [
      for (var i = 0; i < 600; i++) 'song-id-${i.toString().padLeft(14, '0')}',
    ];

    test(
      'a long list goes in one form POST when the server takes it',
      () async {
        server.formPost = true;
        server.lists['big'] = (name: 'Big', songs: [...long]);
        await src.movePlaylistItem('big', 599, 0);
        expect(songs(server, 'big'), [long.last, ...long.take(599)]);
        final w = server.log.last;
        expect(w.method, 'POST');
        expect(w.url.path, endsWith('/createPlaylist.view'));
        expect(w.url.toString().length, lessThan(SubsonicSource.maxUrlLength));
        expect(
          w.headers['content-type'],
          startsWith('application/x-www-form-urlencoded'),
        );
        expect(w.url.toString(), isNot(contains('pw-secret')));
      },
    );

    test('a long list on a server without form POST: refused before anything '
        'is sent (never half written)', () async {
      server.lists['big'] = (name: 'Big', songs: [...long]);
      await expectLater(
        src.movePlaylistItem('big', 599, 0),
        throwsA(isA<PlaylistTooLong>()),
      );
      expect(songs(server, 'big'), long);
      expect(server.log.where((r) => r.url.path.contains('create')), isEmpty);
    });
  });

  test('a long add without form POST goes in slices, in order', () async {
    final many = [
      for (var i = 0; i < 500; i++) 'id-${i.toString().padLeft(20, '0')}',
    ];
    server.maxUrl = SubsonicSource.maxUrlLength;
    await src.addToPlaylist('pl1', many);
    expect(songs(server, 'pl1'), ['s1', 's2', 's3', ...many]);
    final adds = server.log.where((r) => r.url.path.contains('updatePlaylist'));
    expect(adds.length, greaterThan(1));
  });

  test(
    'a long remove without form POST goes in slices, last positions first',
    () async {
      final many = [for (var i = 0; i < 800; i++) 's$i'];
      server.lists['big'] = (name: 'Big', songs: [...many]);
      server.maxUrl = SubsonicSource.maxUrlLength;
      final gone = [for (var i = 0; i < 800; i += 2) i];
      await src.removeFromPlaylist('big', gone);
      expect(songs(server, 'big'), [for (var i = 1; i < 800; i += 2) 's$i']);
      expect(
        server.log.where((r) => r.url.path.contains('updatePlaylist')).length,
        greaterThan(1),
      );
    },
  );

  group('refused', () {
    test(
      'error 50 (no rights): PlaylistWriteRefused, nothing changed',
      () async {
        server.readOnly = true;
        await expectLater(
          src.addToPlaylist('pl1', ['s4']),
          throwsA(isA<PlaylistWriteRefused>()),
        );
        await expectLater(
          src.createPlaylist('X'),
          throwsA(isA<PlaylistWriteRefused>()),
        );
        expect(songs(server, 'pl1'), ['s1', 's2', 's3']);
      },
    );

    test('HTTP 403: PlaylistWriteRefused', () async {
      server.forbidden = true;
      await expectLater(
        src.renamePlaylist('pl1', 'Y'),
        throwsA(isA<PlaylistWriteRefused>()),
      );
    });
  });

  test('unreachable: a SourceNetworkException without the address', () async {
    final s = make(
      MockClient((_) async => throw const SocketException('no route')),
    );
    await expectLater(
      s.addToPlaylist('pl1', ['s4']),
      throwsA(
        isA<SourceNetworkException>().having(
          (e) => e.toString(),
          'text',
          isNot(contains('music.example.com')),
        ),
      ),
    );
  });
}
