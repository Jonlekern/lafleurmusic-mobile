import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lafleurmusic/library/db.dart';
import 'package:lafleurmusic/library/models.dart' show unknownAlbumName;
import 'package:lafleurmusic/library/sync.dart';
import 'package:lafleurmusic/player/media_resolver.dart' show remoteCover;
import 'package:lafleurmusic/sources/plex.dart';
import 'package:lafleurmusic/sources/plex_link.dart';
import 'package:lafleurmusic/sources/source.dart';

import 'fake_plex.dart';
import 'fake_secret_store.dart';

String fx(String name) => File('test/fixtures/plex/$name').readAsStringSync();

final home = PlexServer.fromResource(resourceJson(homeResource))!;

/// A fake Plex Media Server serving the recorded answers in test/fixtures/plex.
class Library {
  final pms = FakePms();
  final log = <http.Request>[];

  /// Answers per `/library/sections/{id}/all`; [albumsFailing]: that section answers 500.
  Map<String, String> albums = {
    '1': fx('albums_s1.json'),
    '3': fx('albums_s3.json'),
  };
  Set<String> albumsFailing = {};
  Set<String> childrenFailing = {};
  Set<String> itemsFailing = {'901'};
  bool ignoreOffset = false;
  Uint8List cover = Uint8List.fromList(const [1, 2, 3]);
  bool noSections = false;

  Future<http.Response> handle(http.Request r) async {
    final p = r.url.path;
    final host = r.url.host;
    final isLibrary =
        p.startsWith('/library/sections/') ||
        p.startsWith('/library/metadata/') ||
        p.startsWith('/playlists') ||
        p.startsWith('/photo/');
    if (!isLibrary && !(p == '/library/sections' && noSections)) {
      return pms.handle(r);
    }
    log.add(r);
    if (host != homeLocal) throw const SocketException('not here');
    if (!pms.tokens.contains(r.headers['X-Plex-Token'])) {
      return http.Response('<html>Unauthorized</html>', 401);
    }
    if (p == '/library/sections') {
      return jsonResponse('{"MediaContainer":{"size":0}}');
    }
    final m = RegExp(r'^/library/sections/(\d+)/all$').firstMatch(p);
    if (m != null) {
      if (r.url.queryParameters['type'] != '9') return http.Response('', 400);
      final id = m.group(1)!;
      if (albumsFailing.contains(id)) return http.Response('', 500);
      return jsonResponse(
        _slice(r, albums[id] ?? '{"MediaContainer":{"size":0}}'),
      );
    }
    final c = RegExp(r'^/library/metadata/(\d+)/children$').firstMatch(p);
    if (c != null) {
      final id = c.group(1)!;
      if (childrenFailing.contains(id)) return http.Response('', 500);
      final f = File('test/fixtures/plex/children_$id.json');
      return f.existsSync()
          ? jsonResponse(_slice(r, f.readAsStringSync()))
          : http.Response('', 404);
    }
    if (p == '/playlists') {
      if (r.url.queryParameters['playlistType'] != 'audio') {
        return http.Response('', 400);
      }
      return jsonResponse(fx('playlists.json'));
    }
    final i = RegExp(r'^/playlists/(\d+)/items$').firstMatch(p);
    if (i != null) {
      final id = i.group(1)!;
      if (itemsFailing.contains(id)) return http.Response('', 500);
      final f = File('test/fixtures/plex/playlist_${id}_items.json');
      return jsonResponse(
        f.existsSync()
            ? _slice(r, f.readAsStringSync())
            : '{"MediaContainer":{"size":0}}',
      );
    }
    if (p == '/photo/:/transcode') {
      return http.Response.bytes(
        cover,
        200,
        headers: {'content-type': 'image/jpeg'},
      );
    }
    return http.Response('', 404);
  }

  /// The slice asked by X-Plex-Container-Start / -Size, like a real server.
  String _slice(http.Request r, String body) {
    final d = jsonDecode(body) as Map;
    final mc = d['MediaContainer'] as Map;
    final all = (mc['Metadata'] as List?) ?? const [];
    final start = ignoreOffset
        ? 0
        : int.parse(r.headers['X-Plex-Container-Start'] ?? '0');
    final size = int.parse(r.headers['X-Plex-Container-Size'] ?? '100000');
    final page = all.skip(start).take(size).toList();
    return jsonEncode({
      'MediaContainer': {
        'size': page.length,
        'totalSize': all.length,
        'offset': start,
        if (page.isNotEmpty) 'Metadata': page,
      },
    });
  }

  MockClient client() => MockClient(handle);

  PlexSource source({
    FakeSecretStore? secrets,
    Map<String, String> headers = const {},
  }) {
    final s = secrets ?? FakeSecretStore();
    s.data[PlexSource.tokenKey('acc1')] = 'server-token-home';
    return PlexSource(
      accountId: 'acc1',
      server: home,
      clientId: 'client-abc',
      headers: headers,
      client: client(),
      secrets: s,
      deviceName: 'iPhone',
      platform: 'iOS',
    );
  }
}

Future<List<SourceAlbum>> allAlbums(PlexSource s, {int pageSize = 500}) async =>
    [await for (final page in s.albums(pageSize: pageSize)) ...page];

void main() {
  setUp(PlexSource.resetStateForTests);
  tearDown(PlexSource.resetStateForTests);

  group('albums', () {
    test('every music library is read, an album in two counts once', () async {
      final lib = Library();
      final albums = await allAlbums(lib.source());
      expect([for (final a in albums) a.id], ['11', '12', '13', '21']);
      final abbey = albums.first;
      expect(abbey.name, 'Abbey Road');
      expect(abbey.artist, 'The Beatles'); // the album's artist (parentTitle)
      expect(abbey.songCount, 2);
      expect(abbey.coverId, '/library/metadata/11/thumb/1700000011');
      // movies (section 2) are never asked
      final asked = lib.log.map((r) => r.url.path).toSet();
      expect(
        asked,
        containsAll(['/library/sections/1/all', '/library/sections/3/all']),
      );
      expect(asked, isNot(contains('/library/sections/2/all')));
    });

    test('pages of the asked size, token in a header only', () async {
      final lib = Library();
      final pages = [
        await for (final p in lib.source().albums(pageSize: 2)) p.length,
      ];
      expect(pages, [2, 1, 1]); // section 3: its second album was already seen
      final all = lib.log.where((r) => r.url.path == '/library/sections/1/all');
      expect(
        [for (final r in all) r.headers['X-Plex-Container-Start']],
        ['0', '2'],
      );
      expect(all.first.headers['X-Plex-Container-Size'], '2');
      expect(all.first.headers['Accept'], 'application/json');
      for (final r in lib.log) {
        expect(r.url.toString(), isNot(contains('server-token-home')));
        expect(r.headers['X-Plex-Token'], 'server-token-home');
      }
    });

    test('an album without a name is the unknown album', () async {
      final albums = await allAlbums(Library().source());
      expect(albums.singleWhere((a) => a.id == '13').name, unknownAlbumName);
      expect(albums.singleWhere((a) => a.id == '13').coverId, isNull);
    });

    test(
      'a server ignoring the offset fails the run instead of looping',
      () async {
        final lib = Library()..ignoreOffset = true;
        await expectLater(
          allAlbums(lib.source(), pageSize: 2),
          throwsA(isA<PlexException>()),
        );
      },
    );

    test('custom headers go with every library request', () async {
      final lib = Library();
      await allAlbums(lib.source(headers: {'CF-Access-Client-Id': 'abc'}));
      for (final r in lib.log) {
        expect(r.headers['CF-Access-Client-Id'], 'abc');
      }
    });

    test('revoked token (401): to reconnect', () async {
      final lib = Library();
      lib.pms.tokens = {};
      await expectLater(
        allAlbums(lib.source()),
        throwsA(
          isA<PlexException>().having(
            (e) => e.tokenRefused,
            'tokenRefused',
            isTrue,
          ),
        ),
      );
    });

    test(
      'a section that fails stops the listing (nothing half-read is complete)',
      () async {
        final lib = Library()..albumsFailing = {'3'};
        await expectLater(
          allAlbums(lib.source()),
          throwsA(isA<PlexException>()),
        );
      },
    );
  });

  group('songs', () {
    test('fields of a track', () async {
      final lib = Library();
      final s = lib.source();
      await allAlbums(s);
      final songs = await s.albumSongs('11');
      expect(songs, hasLength(2));
      final a = songs[0];
      expect(a.id, '101');
      expect(a.title, 'Come Together');
      expect(a.artist, 'The Beatles');
      expect(a.albumArtist, 'The Beatles');
      expect(a.album, 'Abbey Road');
      expect((a.track, a.disc), (1, 1));
      expect(a.durationMs, 259000);
      expect(a.size, 31000000);
      expect(a.suffix, 'flac');
      expect(a.playCount, 3);
      expect(a.coverId, '/library/metadata/11/thumb/1700000011');
      final b = songs[1];
      expect(b.artist, 'George Harrison'); // originalTitle
      expect(b.albumArtist, 'The Beatles');
      expect(b.playCount, 0);
      expect(b.suffix, 'mp3');
    });

    test(
      'compilation: album artist is the album\'s, not the track\'s',
      () async {
        final s = Library().source();
        final songs = await s.albumSongs('12');
        expect([for (final x in songs) x.artist], ['A', 'B']);
        expect({for (final x in songs) x.albumArtist}, {'Various Artists'});
        expect(songs[1].disc, 2);
        expect(songs[1].suffix, 'm4a'); // "m4a,mp4"
      },
    );

    test('loose album: unknown album name, no disc', () async {
      final s = Library().source();
      final song = (await s.albumSongs('13')).single;
      expect(song.album, unknownAlbumName);
      expect(song.disc, isNull);
      expect(song.albumArtist, 'Solo');
    });

    test('no cover on the album: no cover id', () async {
      final songs = await Library().source().albumSongs('13');
      expect(songs.single.coverId, isNull);
    });

    test('an album that fails is an error', () async {
      final lib = Library()..childrenFailing = {'11'};
      await expectLater(
        lib.source().albumSongs('11'),
        throwsA(isA<PlexException>()),
      );
    });
  });

  group('playlists', () {
    test(
      'songs in order (a song twice stays twice), unreadable one is null',
      () async {
        final lists = await Library().source().playlists();
        expect([for (final l in lists) l.name], ['Favoris', 'Cassée', 'Vide']);
        expect(lists[0].songIds, ['101', '211', '101']);
        expect(lists[1].songIds, isNull);
        expect(lists[2].songIds, isEmpty);
      },
    );

    test('playlists list refused: an error', () async {
      final lib = Library();
      lib.pms.tokens = {};
      await expectLater(
        lib.source().playlists(),
        throwsA(isA<PlexException>()),
      );
    });
  });

  group('covers', () {
    test('coverUri: transcode of the thumb, no token in the address', () async {
      final s = Library().source();
      await s.prepare();
      final u = s.coverUri('/library/metadata/11/thumb/1700000011', 300);
      expect(u.path, '/photo/:/transcode');
      expect(u.queryParameters['url'], '/library/metadata/11/thumb/1700000011');
      expect(u.queryParameters['width'], '300');
      expect(u.queryParameters['height'], '300');
      expect(u.toString(), isNot(contains('server-token-home')));
      expect(u.host, homeLocal);
    });

    test(
      'remoteCover loads the token first and sends it as a header',
      () async {
        final lib = Library();
        final s = lib.source(); // nothing prepared yet
        final bytes = await remoteCover(
          s,
          '/library/metadata/11/thumb/1700000011',
          64,
        );
        expect(bytes, [1, 2, 3]);
        final r = lib.log.singleWhere(
          (r) => r.url.path == '/photo/:/transcode',
        );
        expect(r.headers['X-Plex-Token'], 'server-token-home');
        expect(r.url.toString(), isNot(contains('server-token-home')));
      },
    );

    test('a refused cover is null', () async {
      final lib = Library();
      final s = lib.source();
      await s.prepare();
      lib.pms.tokens = {};
      expect(await remoteCover(s, '/library/metadata/11/thumb/1', 64), isNull);
    });
  });

  group('sync', () {
    Future<int> count(LibraryDb db) async =>
        (await db.select(db.tracks).get()).length;

    test('plex:// keys, merge key fields, playlists; a second sync changes nothing', () async {
      final db = LibraryDb(NativeDatabase.memory());
      addTearDown(db.close);
      final r = await LibrarySync(db).run(Library().source());
      expect(r.complete, isTrue);
      expect(r.added, 6); // 101 102 121 122 131 211
      final t = await db.trackByPath('plex://acc1/101');
      expect(
        (t!.album, t.albumArtist, t.suffix, t.size),
        ('Abbey Road', 'The Beatles', 'flac', 31000000),
      );
      expect(t.coverId, '/library/metadata/11/thumb/1700000011');
      expect(
        (await db.trackByPath('plex://acc1/131'))!.album,
        unknownAlbumName,
      );
      final r2 = await LibrarySync(db).run(Library().source());
      expect((r2.added, r2.updated, r2.removed, r2.complete), (0, 0, 0, true));
    });

    test('R3: a server answering 0 albums deletes nothing', () async {
      final db = LibraryDb(NativeDatabase.memory());
      addTearDown(db.close);
      await LibrarySync(db).run(Library().source());
      final before = await count(db);
      expect(before, 6);
      final empty = Library()..albums = {};
      var r = await LibrarySync(db).run(empty.source());
      expect((r.complete, r.removed), (false, 0));
      // no music section at all
      final none = Library()..noSections = true;
      r = await LibrarySync(db).run(none.source());
      expect(r.removed, 0);
      expect(await count(db), before);
    });

    test('an error mid-listing deletes nothing', () async {
      final db = LibraryDb(NativeDatabase.memory());
      addTearDown(db.close);
      await LibrarySync(db).run(Library().source());
      final lib = Library()..albumsFailing = {'3'};
      final r = await LibrarySync(db).run(lib.source());
      expect((r.complete, r.removed), (false, 0));
      expect(await count(db), 6);
    });
  });
}
