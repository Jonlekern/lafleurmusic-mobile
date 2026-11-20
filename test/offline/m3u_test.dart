import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/library/db.dart';
import 'package:lafleurmusic/library/models.dart';
import 'package:lafleurmusic/offline/device.dart';
import 'package:lafleurmusic/offline/m3u.dart';

class _Device implements Device {
  _Device(this.root);
  Directory root;
  bool reachable = true;
  final announced = <String>[];
  @override
  Future<Directory> keptRoot() async => root;
  @override
  Future<Directory> visibleRoot() async => root;
  @override
  Future<bool> rootReachable() async => reachable;
  @override
  Future<void> announce(String path) async => announced.add(path);
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Track _t(
  String id, {
  String acc = 'acc',
  String title = 'Song',
  String artist = 'Art',
  String album = 'Alb',
  int seconds = 200,
}) => Track(
  path: 'subsonic://$acc/$id',
  accountId: acc,
  remoteId: id,
  title: title,
  artist: artist,
  albumArtist: artist,
  album: album,
  trackNo: 1,
  durationMs: seconds * 1000,
  hasCover: false,
  size: 4,
);

void main() {
  group('buildM3u8', () {
    test('header, one #EXTINF per song, the paths as given', () {
      expect(
        buildM3u8(const [
          M3uEntry(
            seconds: 222,
            artist: 'Johnny',
            title: 'Ocean Drive',
            path: '../Johnny/Studio Lafleur/01 Ocean Drive.mp3',
          ),
          M3uEntry(
            seconds: 245,
            artist: 'LAFLEURSTUDIO',
            title: 'Lafleur Surf',
            path: '../LAFLEURSTUDIO/Lafleur Surf/01 Lafleur Surf.flac',
          ),
        ]),
        '#EXTM3U\n'
        '#EXTINF:222,Johnny - Ocean Drive\n'
        '../Johnny/Studio Lafleur/01 Ocean Drive.mp3\n'
        '#EXTINF:245,LAFLEURSTUDIO - Lafleur Surf\n'
        '../LAFLEURSTUDIO/Lafleur Surf/01 Lafleur Surf.flac\n',
      );
    });

    test(
      'special characters kept as UTF-8, a line break never splits a line',
      () {
        final text = buildM3u8(const [
          M3uEntry(
            seconds: 61,
            artist: 'Björk, Été',
            title: 'Ça va\nbien # 1',
            path: '../Björk/Été #1/01 Ça va.mp3',
          ),
        ]);
        expect(
          text,
          '#EXTM3U\n'
          '#EXTINF:61,Björk, Été - Ça va bien # 1\n'
          '../Björk/Été #1/01 Ça va.mp3\n',
        );
      },
    );
  });

  group('PlaylistFiles', () {
    late Directory tmp, root;
    late LibraryDb db;
    late _Device device;
    late PlaylistFiles files;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('m3u');
      root = Directory('${tmp.path}/LAFLEURMUSIC')..createSync();
      db = LibraryDb(NativeDatabase.memory());
      device = _Device(root);
      files = PlaylistFiles(db, device);
    });
    tearDown(() async {
      await db.close();
      tmp.deleteSync(recursive: true);
    });

    /// A finished copy of [path] at [rel] (the file is written too).
    Future<void> copy(String path, String rel) async {
      File('${root.path}/$rel')
        ..createSync(recursive: true)
        ..writeAsBytesSync([1, 2, 3, 4]);
      await db.queueOffline([path], OfflineReason.user);
      await db.markOfflineDone(path, rel, 4);
    }

    File m3u(String name) => File('${root.path}/Playlists/$name');

    Future<void> seed() async {
      await db.upsertTracks([
        _t('1', title: 'Ocean Drive', artist: 'Johnny', album: 'Studio'),
        _t('2', title: 'Lafleur Surf', artist: 'LAFLEURSTUDIO', album: 'Surf'),
        _t('3', title: 'Nightcall', artist: 'Kavinsky', album: 'Night'),
      ]);
      // s1 twice, s9 absent from the account (no track row)
      await db.replacePlaylists('acc', [
        (
          id: 'p1',
          name: 'Soirée: été/2026',
          paths: [
            'subsonic://acc/1',
            'subsonic://acc/2',
            'subsonic://acc/9',
            'subsonic://acc/3',
            'subsonic://acc/1',
          ],
        ),
      ]);
      await db.setKeptPlaylist('acc', 'p1', '');
    }

    test(
      'Review Focus 4: order kept, the duplicate twice, the absent song and '
      'the songs without a copy left out; paths relative to the file',
      () async {
        await seed();
        await copy('subsonic://acc/1', 'Johnny/Studio/01 Ocean Drive.mp3');
        await copy('subsonic://acc/3', 'Kavinsky/Night/01 Nightcall.mp3');
        await files.refresh();
        final f = m3u('Soirée_ été_2026.m3u8');
        expect(
          f.readAsStringSync(),
          '#EXTM3U\n'
          '#EXTINF:200,Johnny - Ocean Drive\n'
          '../Johnny/Studio/01 Ocean Drive.mp3\n'
          '#EXTINF:200,Kavinsky - Nightcall\n'
          '../Kavinsky/Night/01 Nightcall.mp3\n'
          '#EXTINF:200,Johnny - Ocean Drive\n'
          '../Johnny/Studio/01 Ocean Drive.mp3\n',
        );
        // every path resolves from the playlist's folder
        for (final line in f.readAsLinesSync().where(
          (l) => !l.startsWith('#'),
        )) {
          expect(
            File('${f.parent.path}/$line').existsSync(),
            isTrue,
            reason: line,
          );
        }
        expect(
          (await db.keptPlaylistRows()).single.fileName,
          'Soirée_ été_2026.m3u8',
        );
        expect(device.announced, [f.path]);
        expect(
          Directory('${root.path}/Playlists').listSync().length,
          1,
          reason: 'no temporary file left',
        );
      },
    );

    test(
      'a copy arriving rewrites it; the same content is not rewritten',
      () async {
        await seed();
        await copy('subsonic://acc/1', 'Johnny/Studio/01 Ocean Drive.mp3');
        await files.refresh();
        await files.refresh();
        expect(device.announced.length, 1);
        await copy(
          'subsonic://acc/2',
          'LAFLEURSTUDIO/Surf/01 Lafleur Surf.mp3',
        );
        await files.refresh();
        final lines = m3u('Soirée_ été_2026.m3u8').readAsLinesSync();
        expect(lines.where((l) => !l.startsWith('#')), [
          '../Johnny/Studio/01 Ocean Drive.mp3',
          '../LAFLEURSTUDIO/Surf/01 Lafleur Surf.mp3',
          '../Johnny/Studio/01 Ocean Drive.mp3',
        ]);
      },
    );

    test('a twin\'s copy on another account counts', () async {
      await seed();
      await db.upsertTracks([
        _t(
          'x',
          acc: 'B',
          title: 'Nightcall',
          artist: 'Kavinsky',
          album: 'Night',
        ),
      ]);
      await copy('subsonic://B/x', 'Kavinsky/Night/01 Nightcall.mp3');
      await files.refresh();
      expect(
        m3u('Soirée_ été_2026.m3u8').readAsLinesSync().last,
        '../Kavinsky/Night/01 Nightcall.mp3',
      );
    });

    test(
      'no copy finished yet but songs queued: no file, the playlist stays kept',
      () async {
        await seed();
        await db.queueOffline(['subsonic://acc/1'], OfflineReason.user);
        await files.refresh();
        expect(Directory('${root.path}/Playlists').existsSync(), isFalse);
        expect(await db.keptPlaylistRows(), hasLength(1));
      },
    );

    test('the last copy leaving removes the file and the record', () async {
      await seed();
      await copy('subsonic://acc/1', 'Johnny/Studio/01 Ocean Drive.mp3');
      await files.refresh();
      final f = m3u('Soirée_ été_2026.m3u8');
      expect(f.existsSync(), isTrue);
      await db.removeOffline(['subsonic://acc/1']);
      await files.refresh();
      expect(f.existsSync(), isFalse);
      expect(await db.keptPlaylistRows(), isEmpty);
      expect(device.announced.last, f.path, reason: 'Android forgets it');
    });

    test('a name already taken by a file of the user: another name, '
        'and the user\'s file is never touched', () async {
      await seed();
      final mine = m3u('Soirée_ été_2026.m3u8')
        ..createSync(recursive: true)
        ..writeAsStringSync('#EXTM3U\nmine.mp3\n');
      await copy('subsonic://acc/1', 'Johnny/Studio/01 Ocean Drive.mp3');
      await files.refresh();
      expect(m3u('Soirée_ été_2026 (2).m3u8').existsSync(), isTrue);
      await files.remove('acc', 'p1');
      expect(m3u('Soirée_ été_2026 (2).m3u8').existsSync(), isFalse);
      expect(mine.readAsStringSync(), '#EXTM3U\nmine.mp3\n');
      expect(await db.keptPlaylistRows(), isEmpty);
    });

    test('two playlists with the same name get two files', () async {
      await seed();
      await db.replacePlaylists('B', [
        (id: 'q', name: 'Soirée: été/2026', paths: ['subsonic://B/x']),
      ]);
      await db.upsertTracks([_t('x', acc: 'B', title: 'Other')]);
      await db.setKeptPlaylist('B', 'q', '');
      await copy('subsonic://acc/1', 'Johnny/Studio/01 Ocean Drive.mp3');
      await copy('subsonic://B/x', 'Art/Alb/01 Other.mp3');
      await files.refresh();
      expect(
        Directory('${root.path}/Playlists')
            .listSync()
            .map((e) => e.uri.pathSegments.last)
            .toSet(),
        {'Soirée_ été_2026.m3u8', 'Soirée_ été_2026 (2).m3u8'},
      );
    });

    test('a playlist that is not kept never gets a file; hand-placed .m3u8 untouched', () async {
      await seed();
      await db.dropKeptPlaylist('acc', 'p1');
      final hand = m3u('Soirée_ été_2026.m3u8')
        ..createSync(recursive: true)
        ..writeAsStringSync('x');
      await copy('subsonic://acc/1', 'Johnny/Studio/01 Ocean Drive.mp3');
      await files.refresh();
      expect(hand.readAsStringSync(), 'x');
      expect(Directory('${root.path}/Playlists').listSync(), hasLength(1));
    });

    test('folder unreachable: nothing written nor deleted', () async {
      await seed();
      await copy('subsonic://acc/1', 'Johnny/Studio/01 Ocean Drive.mp3');
      device.reachable = false;
      await files.refresh();
      expect(Directory('${root.path}/Playlists').existsSync(), isFalse);
    });

    test(
      'leaving a folder (move): our file there goes, the next refresh writes '
      'it in the new folder',
      () async {
        await seed();
        await copy('subsonic://acc/1', 'Johnny/Studio/01 Ocean Drive.mp3');
        await files.refresh();
        final old = root;
        await files.leave(old);
        expect(m3u('Soirée_ été_2026.m3u8').existsSync(), isFalse);
        expect(Directory('${old.path}/Playlists').existsSync(), isFalse);
        expect((await db.keptPlaylistRows()).single.fileName, '');
      },
    );
  });
}
