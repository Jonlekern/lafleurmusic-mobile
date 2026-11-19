import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:lafleurmusic/sources/plex.dart';
import 'package:lafleurmusic/sources/plex_link.dart';
import 'package:lafleurmusic/sources/source.dart';

import 'fake_playlist_servers.dart';

import 'fake_secret_store.dart';

void main() {
  setUp(PlexSource.resetStateForTests);
  late FakePlexPlaylists server;
  late PlexSource src;
  setUp(() {
    server = FakePlexPlaylists();
    src = server.source();
  });

  test('a Plex source writes playlists', () {
    expect(src, isA<PlaylistWriter>());
  });

  test('createPlaylist: POST /playlists on this server (its machine id in the '
      'uri); the token only in a header', () async {
    final id = await src.createPlaylist('Soirée');
    expect(id, '910');
    expect(server.lists['910']!.title, 'Soirée');
    expect(server.songs('910'), isEmpty);
    for (final r in server.log) {
      expect(r.headers['X-Proxy'], 'k');
      expect(r.url.toString(), isNot(contains('server-token-home')));
    }
  });

  test('addToPlaylist: PUT …/items?uri=server://{machine}/…/library/metadata/'
      '{ratingKeys}', () async {
    await src.addToPlaylist('900', ['300', '101']);
    expect(server.songs('900'), ['101', '211', '102', '300', '101']);
    final put = server.log.last;
    expect(put.method, 'PUT');
    expect(
      put.url.queryParameters['uri'],
      '$plexLibraryUri/library/metadata/300,101',
    );
  });

  test('removeFromPlaylist: by the rows\' playlistItemID (the right copy of a '
      'song listed twice)', () async {
    await src.addToPlaylist('900', ['101']); // 101 at 0 and 3
    await src.removeFromPlaylist('900', [3]);
    expect(server.lists['900']!.rows.first, ('101', 1));
    expect(server.songs('900'), ['101', '211', '102']);
    await src.removeFromPlaylist('900', [0, 2]);
    expect(server.songs('900'), ['211']);
  });

  test('movePlaylistItem: PUT …/items/{item}/move?after=…, to the top without '
      'after', () async {
    await src.movePlaylistItem('900', 0, 2);
    expect(server.songs('900'), ['211', '102', '101']);
    expect(server.log.last.url.queryParameters['after'], '3');
    await src.movePlaylistItem('900', 2, 0);
    expect(server.songs('900'), ['101', '211', '102']);
    expect(server.log.last.url.queryParameters, isNot(contains('after')));
    await src.movePlaylistItem('900', 0, 1);
    expect(server.songs('900'), ['211', '101', '102']);
    await expectLater(src.movePlaylistItem('900', 0, 3), throwsRangeError);
  });

  test('renamePlaylist, readPlaylist, deletePlaylist', () async {
    await src.renamePlaylist('900', 'Route');
    final p = await src.readPlaylist('900');
    expect((p.id, p.name), ('900', 'Route'));
    expect(p.songIds, ['101', '211', '102']);
    await src.deletePlaylist('900');
    expect(server.lists, isEmpty);
  });

  test('403: PlaylistWriteRefused, nothing changed', () async {
    server.readOnly = true;
    await expectLater(
      src.addToPlaylist('900', ['300']),
      throwsA(isA<PlaylistWriteRefused>()),
    );
    await expectLater(
      src.createPlaylist('X'),
      throwsA(isA<PlaylistWriteRefused>()),
    );
    expect(server.songs('900'), ['101', '211', '102']);
  });

  test('401: « À reconnecter » (the token is refused)', () async {
    String? relink;
    PlexSource.onTokenRefused = (id) => relink = id;
    final s = FakeSecretStore()
      ..data[PlexSource.tokenKey('acc1')] = 'old-token';
    final other = PlexSource(
      accountId: 'acc1',
      server: home,
      clientId: 'client-abc',
      client: MockClient(server.handle),
      secrets: s,
    );
    await expectLater(
      other.addToPlaylist('900', ['300']),
      throwsA(
        isA<PlexException>().having((e) => e.tokenRefused, 'relink', true),
      ),
    );
    expect(relink, 'acc1');
  });

  test('no address answers: a SourceNetworkException', () async {
    server.down = true;
    await expectLater(
      src.addToPlaylist('900', ['300']),
      throwsA(isA<SourceNetworkException>()),
    );
  });
}
