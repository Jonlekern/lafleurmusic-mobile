import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:lafleurmusic/sources/jellyfin.dart';
import 'package:lafleurmusic/sources/source.dart';

import 'fake_playlist_servers.dart';

import 'fake_secret_store.dart';

void main() {
  late FakeJellyfin server;
  late FakeSecretStore secrets;
  late JellyfinSource src;
  setUp(() {
    server = FakeJellyfin();
    secrets = FakeSecretStore();
    src = JellyfinSource(
      accountId: 'acc1',
      base: Uri.parse('http://jf.example:8096'),
      user: 'max',
      password: 'pw-secret',
      headers: {'X-Proxy': 'k'},
      client: server.client(),
      secrets: secrets,
      deviceName: 'iPhone',
    );
  });

  test('a Jellyfin source writes playlists', () {
    expect(src, isA<PlaylistWriter>());
  });

  test('createPlaylist: POST /Playlists, the new id back; headers on every '
      'request; no token or password in any address', () async {
    final id = await src.createPlaylist('Soirée');
    expect(id, 'pl10');
    expect(server.lists['pl10']!.name, 'Soirée');
    for (final r in server.log) {
      expect(r.headers['X-Proxy'], 'k');
      expect(r.url.toString(), isNot(contains('tok-secret-1')));
      expect(r.url.toString(), isNot(contains('pw-secret')));
    }
  });

  test('addToPlaylist: POST /Playlists/{id}/Items?Ids=, in order', () async {
    await src.addToPlaylist('pl1', ['s4', 's1']);
    expect(server.songs('pl1'), ['s1', 's2', 's3', 's4', 's1']);
  });

  test('addToPlaylist: many songs go in several requests, in order', () async {
    final many = [for (var i = 0; i < 250; i++) 'n$i'];
    await src.addToPlaylist('pl1', many);
    expect(server.songs('pl1'), ['s1', 's2', 's3', ...many]);
    expect(
      server.log.where(
        (r) => r.method == 'POST' && r.url.path.endsWith('/Items'),
      ),
      hasLength(3),
    );
  });

  test('removeFromPlaylist: by the rows\' entry ids, the right copy of a song '
      'listed twice', () async {
    await src.addToPlaylist('pl1', ['s1']); // s1 now at 0 and 3
    await src.removeFromPlaylist('pl1', [3]);
    expect(server.lists['pl1']!.rows, [
      ('s1', 'e1'),
      ('s2', 'e2'),
      ('s3', 'e3'),
    ]);
    await src.removeFromPlaylist('pl1', [0, 2]);
    expect(server.songs('pl1'), ['s2']);
    final del = server.log.lastWhere((r) => r.method == 'DELETE');
    expect(del.url.queryParameters['EntryIds']!.split(','), ['e1', 'e3']);
  });

  test('movePlaylistItem: POST …/Items/{entry}/Move/{index}', () async {
    await src.movePlaylistItem('pl1', 0, 2);
    expect(server.songs('pl1'), ['s2', 's3', 's1']);
    expect(server.log.last.url.path, '/Playlists/pl1/Items/e1/Move/2');
    await expectLater(src.movePlaylistItem('pl1', 5, 0), throwsRangeError);
  });

  test('renamePlaylist: POST /Playlists/{id}; a server before 10.9: the item '
      'is updated instead', () async {
    await src.renamePlaylist('pl1', 'Route');
    expect(server.lists['pl1']!.name, 'Route');
    server.oldServer = true;
    await src.renamePlaylist('pl1', 'Rue');
    expect(server.lists['pl1']!.name, 'Rue');
    expect(server.log.last.url.path, '/Items/pl1');
  });

  test('deletePlaylist and readPlaylist', () async {
    final p = await src.readPlaylist('pl1');
    expect((p.id, p.name), ('pl1', 'Road'));
    expect(p.songIds, ['s1', 's2', 's3']);
    await src.deletePlaylist('pl1');
    expect(server.lists, isEmpty);
  });

  group('refused', () {
    test('403: PlaylistWriteRefused, nothing changed', () async {
      server.readOnly = true;
      await expectLater(
        src.addToPlaylist('pl1', ['s4']),
        throwsA(isA<PlaylistWriteRefused>()),
      );
      await expectLater(
        src.createPlaylist('X'),
        throwsA(isA<PlaylistWriteRefused>()),
      );
      expect(server.songs('pl1'), ['s1', 's2', 's3']);
    });

    test('a 401 that a fresh sign-in does not cure on a write is a refusal: '
        'the token stays (the password is right)', () async {
      server.deleteDenied = true;
      await expectLater(
        src.deletePlaylist('pl1'),
        throwsA(isA<PlaylistWriteRefused>()),
      );
      expect(secrets.data[JellyfinSource.tokenKey('acc1')], 'tok-secret-1');
      expect(server.lists, contains('pl1'));
    });
  });

  test('unreachable: a SourceNetworkException without the address', () async {
    final s = JellyfinSource(
      accountId: 'acc1',
      base: Uri.parse('http://jf.example:8096'),
      user: 'max',
      password: 'pw-secret',
      client: MockClient((_) async => throw const SocketException('down')),
    );
    await expectLater(
      s.addToPlaylist('pl1', ['s4']),
      throwsA(
        isA<SourceNetworkException>().having(
          (e) => '$e',
          'text',
          isNot(contains('jf.example')),
        ),
      ),
    );
  });
}
