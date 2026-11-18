import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lafleurmusic/library/db.dart';
import 'package:lafleurmusic/library/models.dart';
import 'package:lafleurmusic/offline/device.dart';
import 'package:lafleurmusic/offline/downloader.dart';
import 'package:lafleurmusic/player/media_resolver.dart';
import 'package:lafleurmusic/settings.dart';
import 'package:lafleurmusic/sources/source.dart';
import 'package:lafleurmusic/tags/tag_reader.dart';
import 'package:lafleurmusic/tags/tag_writer.dart';

const _mb = 1024 * 1024;

class _Source implements MusicSource {
  @override
  String get accountId => 'acc';
  @override
  Map<String, String> get headers => {'X-Gate': 'open'};
  @override
  Uri downloadUri(String id) =>
      Uri.parse('https://srv/rest/download?id=$id&t=SECRET');
  @override
  Uri streamUri(String id) =>
      Uri.parse('https://srv/rest/stream?id=$id&t=SECRET');
  @override
  Uri coverUri(String id, int size) =>
      Uri.parse('https://srv/rest/getCoverArt?id=$id&size=$size&t=SECRET');
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Device implements Device {
  _Device(this.root);
  Directory root;
  PickedFolder? committed;
  int released = 0;
  int free = 100 * 1024 * _mb;
  bool access = true;
  int ensureCalls = 0;
  final announced = <String>[];
  @override
  Future<Directory> musicRoot() async => root;
  @override
  Future<bool> ensureAccess({bool readOthers = false}) async {
    ensureCalls++;
    return access;
  }

  @override
  Future<String> absolutePath(String key) async => key;
  @override
  Future<String> keyFor(String a) async => a;
  @override
  Future<int> freeBytes(String path) async => free;
  @override
  Future<void> announce(String path) async => announced.add(path);
  @override
  Future<bool> rootReachable() async => true;
  @override
  Future<PickedFolder?> pickFolder() async => null;
  @override
  Future<void> releaseCandidate() async => released++;
  @override
  Future<void> commitFolder(PickedFolder c) async {
    committed = c;
    root = Directory(c.path);
  }
}

class _Reader implements TagReader {
  TrackTags? result;
  Future<void> Function()? onRead;
  @override
  Future<TrackTags?> read(String path) async {
    await onRead?.call();
    return result;
  }
}

class _IO implements TagFileIO {
  final writes = <TagEdit>[];
  @override
  Future<TagEdit?> snapshot(TagEdit edit) async => edit;
  @override
  Future<bool> write(TagEdit edit) async {
    writes.add(edit);
    return true;
  }
}

Track _t(
  String id, {
  int size = 4,
  String? suffix = 'mp3',
  int? no = 1,
  String album = 'Alb',
  String? cover,
}) => Track(
  path: 'subsonic://acc/$id',
  accountId: 'acc',
  remoteId: id,
  title: 'Song $id',
  artist: 'Art',
  albumArtist: 'Art',
  album: album,
  trackNo: no,
  disc: 1,
  suffix: suffix,
  coverId: cover,
  durationMs: 1000,
  hasCover: false,
  size: size,
);

http.StreamedResponse _ok(
  List<int> body, {
  String type = 'audio/mpeg',
  int code = 200,
}) => http.StreamedResponse(
  Stream.value(body),
  code,
  contentLength: body.length,
  headers: {'content-type': type},
);

void main() {
  late Directory tmp, root;
  late LibraryDb db;
  late _Device device;
  late _Reader reader;
  late _IO io;
  late AppSettings settings;
  late List<http.BaseRequest> seen;
  late Future<http.StreamedResponse> Function(http.BaseRequest) handler;

  Downloader make() => Downloader(
    db: db,
    resolver: MediaResolver((_) async => _Source()),
    device: device,
    settings: () async => settings,
    client: () => _Client((r) {
      seen.add(r);
      return handler(r);
    }),
    tags: io,
    reader: reader,
  );

  Future<void> add(Track t) => db.upsertTrack(t);

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('dl');
    root = Directory('${tmp.path}/LAFLEURMUSIC');
    db = LibraryDb(NativeDatabase.memory());
    device = _Device(root);
    reader = _Reader()
      ..result = const TrackTags(
        title: 'T',
        artist: 'A',
        album: 'B',
        durationMs: 1,
        hasCover: true,
      );
    io = _IO();
    settings = AppSettings();
    seen = [];
    handler = (r) async => _ok([1, 2, 3, 4]);
  });
  tearDown(() async {
    await db.close();
    tmp.deleteSync(recursive: true);
  });

  test('download 200: file stored under Artist/Album, row done', () async {
    final d = make();
    await add(_t('1'));
    final r = await d.keep([_t('1')]);
    expect((r.ok, r.count, r.bytes), (true, 1, 4));
    await d.whenIdle();
    final row = (await db.offlineOf('subsonic://acc/1'))!;
    expect(row.state, 'done');
    expect(row.filePath, 'Art/Alb/01 Song 1.mp3');
    expect(row.size, 4);
    expect(File('${root.path}/${row.filePath}').readAsBytesSync(), [
      1,
      2,
      3,
      4,
    ]);
    expect(
      File('${root.path}/${row.filePath}.lafleur.part').existsSync(),
      isFalse,
    );
    expect(device.announced, ['${root.path}/Art/Alb/01 Song 1.mp3']);
    expect(device.ensureCalls, 1);
  });

  test('a queued row whose track is gone is dropped, the loop goes on', () async {
    final d = make();
    await add(_t('1'));
    await add(_t('2'));
    await db.queueOffline(['subsonic://acc/1', 'subsonic://acc/2'], OfflineReason.user);
    await db.deletePaths(['subsonic://acc/1']); // vanished from the server
    d.start();
    await d.whenIdle();
    expect(await db.offlineOf('subsonic://acc/1'), isNull);
    expect((await db.offlineOf('subsonic://acc/2'))!.state, 'done');
    expect(seen, hasLength(1)); // nothing requested for the vanished one
  });

  test('every request carries the account headers', () async {
    handler = (r) async =>
        r.url.path.endsWith('download') ? _ok([], code: 403) : _ok([1, 2]);
    final d = make();
    await add(_t('1', suffix: 'mp3', cover: 'c1'));
    reader.result = const TrackTags(
      title: '',
      artist: '',
      album: '',
      durationMs: 1,
      hasCover: false,
    );
    await d.keep([_t('1', cover: 'c1')]);
    await d.whenIdle();
    expect(seen.map((r) => r.url.path), [
      '/rest/download',
      '/rest/stream',
      '/rest/getCoverArt',
    ]);
    expect(seen.every((r) => r.headers['X-Gate'] == 'open'), isTrue);
  });

  test('Subsonic error body (200 + JSON) falls back to stream', () async {
    handler = (r) async => r.url.path.endsWith('download')
        ? _ok(
            '{"subsonic-response":{"status":"failed"}}'.codeUnits,
            type: 'application/json',
          )
        : _ok([9, 9], type: 'audio/flac');
    final d = make();
    await add(_t('1', suffix: null));
    await d.keep([_t('1', suffix: null)]);
    await d.whenIdle();
    final row = (await db.offlineOf('subsonic://acc/1'))!;
    expect(row.state, 'done');
    expect(row.filePath, endsWith('.flac')); // extension from Content-Type
  });

  test('tags and cover are written only when the file has neither', () async {
    reader.result = const TrackTags(
      title: '',
      artist: '',
      album: '',
      durationMs: 1,
      hasCover: false,
    );
    handler = (r) async => r.url.path.endsWith('getCoverArt')
        ? _ok([7, 7], type: 'image/jpeg')
        : _ok([1, 2, 3, 4]);
    final d = make();
    await add(_t('1', cover: 'c1'));
    await d.keep([_t('1', cover: 'c1')]);
    await d.whenIdle();
    final w = io.writes.single;
    expect(
      (w.title, w.artist, w.album, w.trackNo, w.disc),
      ('Song 1', 'Art', 'Alb', 1, 1),
    );
    expect(w.cover, Uint8List.fromList([7, 7]));

    io.writes.clear();
    reader.result = const TrackTags(
      title: 'x',
      artist: '',
      album: '',
      durationMs: 1,
      hasCover: false,
    );
    await add(_t('2'));
    await d.keep([_t('2')]);
    await d.whenIdle();
    expect(io.writes, isEmpty);
  });

  test(
    'network cut mid-body: loop stops, nothing counted, no partial',
    () async {
      handler = (r) async => http.StreamedResponse(
        () async* {
          yield [1, 2];
          throw const SocketException('cut');
        }(),
        200,
        contentLength: 4,
        headers: {'content-type': 'audio/mpeg'},
      );
      final d = make();
      await add(_t('1'));
      await add(_t('2', no: 2));
      await d.keep([_t('1'), _t('2', no: 2)]);
      await d.whenIdle();
      for (final id in ['1', '2']) {
        final row = (await db.offlineOf('subsonic://acc/$id'))!;
        expect((row.state, row.failures), ('queued', 0));
      }
      expect(seen, hasLength(1), reason: 'the loop stopped at the first drop');
      expect(root.listSync(recursive: true).whereType<File>(), isEmpty);
      // back online: the next start() resumes
      handler = (r) async => _ok([1, 2, 3, 4]);
      d.start();
      await d.whenIdle();
      expect((await db.offlineOf('subsonic://acc/2'))!.state, 'done');
    },
  );

  test('404 counts, row goes behind, 3rd marks it failed', () async {
    handler = (r) async => r.url.queryParameters['id'] == '1'
        ? _ok([], code: 404)
        : _ok([1, 2, 3, 4]);
    final d = make();
    await add(_t('1'));
    await add(_t('2', no: 2));
    await d.keep([_t('1'), _t('2', no: 2)]);
    await d.whenIdle();
    final ids = [
      for (final r in seen)
        if (r.url.path.endsWith('download')) r.url.queryParameters['id'],
    ];
    expect(ids, ['1', '2', '1', '1'], reason: '2 is not stuck behind 1');
    final one = (await db.offlineOf('subsonic://acc/1'))!;
    expect((one.state, one.failures), ('failed', 3));
    expect((await db.offlineOf('subsonic://acc/2'))!.state, 'done');
  });

  test('Subsonic "not found" (code 70) counts', () async {
    handler = (r) async => _ok(
      '{"subsonic-response":{"status":"failed","error":{"code":70}}}'.codeUnits,
      type: 'application/json',
    );
    final d = make();
    await add(_t('1'));
    await d.keep([_t('1')]);
    await d.whenIdle();
    expect((await db.offlineOf('subsonic://acc/1'))!.failures, 3);
  });

  test(
    '503, 401, other Subsonic errors: nothing counted, loop stops',
    () async {
      for (final code in [503, 429, 401, 403]) {
        seen.clear();
        handler = (r) async => _ok([], code: code);
        final d = make();
        await add(_t('1'));
        await add(_t('2', no: 2));
        await d.keep([_t('1'), _t('2', no: 2)]);
        await d.whenIdle();
        for (final id in ['1', '2']) {
          final row = (await db.offlineOf('subsonic://acc/$id'))!;
          expect((row.state, row.failures), ('queued', 0), reason: '$code');
        }
        expect(seen.every((r) => r.url.queryParameters['id'] == '1'), isTrue);
        await db.removeOffline(['subsonic://acc/1', 'subsonic://acc/2']);
      }
      handler = (r) async => _ok(
        '{"subsonic-response":{"status":"failed","error":{"code":40}}}'
            .codeUnits,
        type: 'application/json',
      );
      final d = make();
      await d.keep([_t('1')]);
      await d.whenIdle();
      expect((await db.offlineOf('subsonic://acc/1'))!.failures, 0);
    },
  );

  test('a local write error (FileSystemException) is not counted', () async {
    tmp.createSync(recursive: true);
    File(root.path).writeAsStringSync('not a folder'); // root cannot be created
    final d = make();
    await add(_t('1'));
    await d.keep([_t('1')]);
    await d.whenIdle();
    final row = (await db.offlineOf('subsonic://acc/1'))!;
    expect((row.state, row.failures), ('queued', 0));
  });

  test('a 200 HTML page (proxy login): nothing counted, loop stops', () async {
    handler = (r) async =>
        _ok('<html>login</html>'.codeUnits, type: 'text/html');
    final d = make();
    await add(_t('1'));
    await d.keep([_t('1')]);
    await d.whenIdle();
    final row = (await db.offlineOf('subsonic://acc/1'))!;
    expect((row.state, row.failures), ('queued', 0));
    expect(File(root.path).existsSync() && root.listSync().isNotEmpty, isFalse);
  });

  test('octet-stream and missing content type are accepted', () async {
    handler = (r) async => _ok([1, 2, 3, 4], type: 'application/octet-stream');
    final d = make();
    await add(_t('1'));
    await d.keep([_t('1')]);
    await d.whenIdle();
    expect((await db.offlineOf('subsonic://acc/1'))!.state, 'done');
  });

  test('pause then start at once does not stall', () async {
    final gate = Completer<void>();
    handler = (r) async {
      await gate.future;
      return _ok([1, 2, 3, 4]);
    };
    final d = make();
    await add(_t('1'));
    await add(_t('2', no: 2));
    await d.keep([_t('1'), _t('2', no: 2)]);
    while (d.current == null) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    d.pause();
    d.start();
    gate.complete();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await d.whenIdle();
    expect((await db.offlineOf('subsonic://acc/1'))!.state, 'done');
    expect((await db.offlineOf('subsonic://acc/2'))!.state, 'done');
  });

  test('the row is done before tags are read', () async {
    String? seenState;
    reader.onRead = () async =>
        seenState = (await db.offlineOf('subsonic://acc/1'))?.state;
    final d = make();
    await add(_t('1'));
    await d.keep([_t('1')]);
    await d.whenIdle();
    expect(seenState, 'done');
  });

  test('queued backlog counts toward the limit', () async {
    device.access = false; // rows stay queued
    settings.storageLimitBytes = 100 * _mb;
    final d = make();
    await add(_t('1', size: 60 * _mb));
    await add(_t('2', size: 60 * _mb, no: 2));
    expect((await d.keep([_t('1', size: 60 * _mb)])).ok, isTrue);
    await d.whenIdle();
    final r = await d.keep([_t('2', size: 60 * _mb, no: 2)]);
    expect((r.ok, r.neededBytes), (false, 60 * _mb));
    // the same track again is not counted twice
    expect((await d.keep([_t('1', size: 60 * _mb)])).ok, isTrue);
  });

  test('a failure moves on to the other tracks, order kept', () async {
    var n = 0;
    handler = (r) async {
      if (r.url.queryParameters['id'] == '1' && n++ < 1) {
        return _ok([], code: 500);
      }
      return _ok([1, 2, 3, 4]);
    };
    final d = make();
    for (final id in ['1', '2']) {
      await add(_t(id, no: int.parse(id)));
    }
    await d.keep([_t('2', no: 2), _t('1', no: 1)]);
    await d.whenIdle();
    expect((await db.offlineOf('subsonic://acc/1'))!.state, 'done');
    expect((await db.offlineOf('subsonic://acc/2'))!.state, 'done');
    final downloads = [
      for (final r in seen)
        if (r.url.path.endsWith('stream') || r.url.path.endsWith('download'))
          r.url.queryParameters['id'],
    ];
    expect(downloads.first, '1'); // album order, not the order passed
  });

  test('resumeAtLaunch wipes .part files and resumes queued rows', () async {
    final stale = File('${root.path}/Art/Alb/01 Song 1.mp3.lafleur.part')
      ..createSync(recursive: true)
      ..writeAsStringSync('xx');
    final foreign = File('${root.path}/Other/movie.mp4.part')
      ..createSync(recursive: true);
    await add(_t('1'));
    await db.queueOffline(['subsonic://acc/1'], OfflineReason.user);
    final d = make();
    await d.resumeAtLaunch();
    expect(stale.existsSync(), isFalse);
    expect(foreign.existsSync(), isTrue, reason: 'only our own .part files');
    await d.whenIdle();
    expect((await db.offlineOf('subsonic://acc/1'))!.state, 'done');
  });

  test(
    'too big for the limit or the free space: tooBig, nothing queued',
    () async {
      final d = make();
      settings.storageLimitBytes = 100 * _mb;
      await add(_t('1'));
      var r = await d.keep([_t('1', size: 150 * _mb)]);
      expect((r.ok, r.neededBytes), (false, 150 * _mb));
      expect(await db.nextQueued(), isNull);

      settings.storageLimitBytes = 10000 * _mb;
      device.free = 300 * _mb; // 100 MiB usable after the 200 MiB margin
      r = await d.keep([_t('1', size: 150 * _mb)]);
      expect((r.ok, r.neededBytes), (false, 150 * _mb));
      expect(await db.nextQueued(), isNull);

      // unknown size counts 10 MiB: fits
      r = await d.keep([_t('1', size: 0)]);
      expect((r.ok, r.bytes), (true, 10 * _mb));
      d.pause();
      await d.whenIdle();
    },
  );

  test('tracks already done are not counted again', () async {
    final d = make();
    await add(_t('1'));
    await d.keep([_t('1')]);
    await d.whenIdle();
    settings.storageLimitBytes = 4; // full already
    final r = await d.keep([_t('1')]);
    expect((r.ok, r.count), (true, 0));
  });

  test('one download at a time', () async {
    var running = 0, peak = 0;
    handler = (r) async {
      running++;
      peak = running > peak ? running : peak;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      running--;
      return _ok([1, 2, 3, 4]);
    };
    final d = make();
    for (final id in ['1', '2', '3']) {
      await add(_t(id, no: int.parse(id)));
    }
    await d.keep([_t('1'), _t('2', no: 2), _t('3', no: 3)]);
    d.start();
    await d.whenIdle();
    expect(peak, 1);
    expect(await db.offlineBytes(), 12);
  });

  test('two tracks with the same name get (2)', () async {
    final d = make();
    await add(_t('1'));
    await add(_t('2'));
    await d.keep([_t('1'), _t('2')]);
    await d.whenIdle();
    expect(
      (await db.offlineOf('subsonic://acc/1'))!.filePath,
      'Art/Alb/01 Song 1.mp3',
    );
    // a same-title track
    final t = _t('9').copyTitle('Song 1');
    await add(t);
    await d.keep([t]);
    await d.whenIdle();
    expect(
      (await db.offlineOf('subsonic://acc/9'))!.filePath,
      'Art/Alb/01 Song 1 (2).mp3',
    );
  });

  test('access refused: loop stops, nothing marked failed', () async {
    device.access = false;
    final d = make();
    await add(_t('1'));
    await d.keep([_t('1')]);
    await d.whenIdle();
    expect(d.accessDenied, isTrue);
    expect(seen, isEmpty);
    final row = (await db.offlineOf('subsonic://acc/1'))!;
    expect((row.state, row.failures), ('queued', 0));
  });

  test('forget deletes files under the root, cancels the current one, never outside', () async {
    final d = make();
    await add(_t('1'));
    await d.keep([_t('1')]);
    await d.whenIdle();
    final f = File('${root.path}/Art/Alb/01 Song 1.mp3');
    expect(f.existsSync(), isTrue);
    // a row pointing outside the root
    final outside = File('${tmp.path}/precious.mp3')..writeAsStringSync('x');
    await db.queueOffline(['subsonic://acc/2'], OfflineReason.user);
    await db.markOfflineDone('subsonic://acc/2', '../precious.mp3', 1);
    await d.forget(['subsonic://acc/1', 'subsonic://acc/2', '/local/a.mp3']);
    expect(f.existsSync(), isFalse);
    expect(Directory('${root.path}/Art').existsSync(), isFalse);
    expect(outside.existsSync(), isTrue);
    expect(await db.offlineOf('subsonic://acc/1'), isNull);
    expect(await db.offlineOf('subsonic://acc/2'), isNull);
  });

  test('forget cancels the download in progress', () async {
    final gate = Completer<void>();
    handler = (r) async => http.StreamedResponse(
      () async* {
        yield [1, 2];
        await gate.future;
        yield [3, 4];
      }(),
      200,
      contentLength: 4,
      headers: {'content-type': 'audio/mpeg'},
    );
    final d = make();
    await add(_t('1'));
    await d.keep([_t('1')]);
    while (d.current == null) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    gate.complete();
    await d.forget(['subsonic://acc/1']);
    await d.whenIdle();
    expect(await db.offlineOf('subsonic://acc/1'), isNull);
    expect(
      root.existsSync() ? root.listSync(recursive: true).whereType<File>() : [],
      isEmpty,
    );
  });

  test('failure texts never carry the URL token', () async {
    handler = (r) async => throw http.ClientException('boom', r.url);
    final d = make();
    await add(_t('1'));
    final logs = <String>[];
    await runZoned(
      () async {
        await d.keep([_t('1')]);
        await d.whenIdle();
      },
      zoneSpecification: ZoneSpecification(print: (_, _, _, s) => logs.add(s)),
    );
    expect(logs.join().contains('SECRET'), isFalse);
  });

  group('moveRoot', () {
    Future<Downloader> withDone(List<String> ids) async {
      final d = make();
      for (final id in ids) {
        await add(_t(id, no: int.parse(id)));
      }
      await d.keep([for (final id in ids) _t(id, no: int.parse(id))]);
      await d.whenIdle();
      return d;
    }

    test(
      'switching flow: old -> move -> commit -> new files, rows renamed',
      () async {
        final d = await withDone(['1']);
        final old = device.root;
        final to = Directory('${tmp.path}/sd');
        final c = PickedFolder(to.path);
        final r = await d.moveRoot(
          from: old,
          to: to,
          commit: () => device.commitFolder(c),
        );
        expect((r.ok, r.count, r.bytes), (true, 1, 4));
        expect(device.committed, same(c));
        expect(File('${to.path}/Art/Alb/01 Song 1.mp3').readAsBytesSync(), [
          1,
          2,
          3,
          4,
        ]);
        expect(File('${old.path}/Art/Alb/01 Song 1.mp3').existsSync(), isFalse);
        expect(
          (await db.offlineOf('subsonic://acc/1'))!.filePath,
          'Art/Alb/01 Song 1.mp3',
        );
      },
    );

    test('a done row whose file is gone is failed with no path', () async {
      final d = await withDone(['1', '2']);
      File('${root.path}/Art/Alb/02 Song 2.mp3').deleteSync();
      final to = Directory('${tmp.path}/sd');
      File('${to.path}/Art/Alb/02 Song 2.mp3')
        ..createSync(recursive: true)
        ..writeAsStringSync('user'); // a user file at the stale path
      final r = await d.moveRoot(from: device.root, to: to);
      expect((r.ok, r.count), (true, 1));
      final lost = (await db.offlineOf('subsonic://acc/2'))!;
      expect((lost.state, lost.filePath, lost.size), ('failed', null, 0));
      expect(
        File('${to.path}/Art/Alb/02 Song 2.mp3').readAsStringSync(),
        'user',
      );
      expect((await db.offlineOf('subsonic://acc/1'))!.state, 'done');
    });

    test('a failed move releases the candidate', () async {
      final d = await withDone(['1']);
      final r = await d.moveRoot(
        from: device.root,
        to: Directory('${tmp.path}/sd'),
        commit: () async => throw const FileSystemException('no'),
      );
      expect(r.ok, isFalse);
      expect(device.released, 1);
    });

    test('collision: the user file is kept, ours gets a free name', () async {
      final d = await withDone(['1']);
      final to = Directory('${tmp.path}/sd');
      final mine = File('${to.path}/Art/Alb/01 Song 1.mp3')
        ..createSync(recursive: true)
        ..writeAsStringSync('user');
      final r = await d.moveRoot(from: device.root, to: to);
      expect(r.ok, isTrue);
      expect(mine.readAsStringSync(), 'user');
      final row = (await db.offlineOf('subsonic://acc/1'))!;
      expect(row.filePath, 'Art/Alb/01 Song 1 (2).mp3');
      expect(File('${to.path}/${row.filePath}').readAsBytesSync(), [
        1,
        2,
        3,
        4,
      ]);
    });

    test('error midway: only our copies removed, user file kept', () async {
      final d = await withDone(['1', '2']);
      final to = Directory('${tmp.path}/sd');
      final mine = File('${to.path}/Art/Alb/01 Song 1.mp3')
        ..createSync(recursive: true)
        ..writeAsStringSync('user');
      final r = await d.moveRoot(
        from: device.root,
        to: to,
        commit: () async => throw const FileSystemException('refused'),
      );
      expect(r.ok, isFalse);
      expect(
        to.listSync(recursive: true).whereType<File>().map((f) => f.path),
        [mine.path],
      );
      expect(mine.readAsStringSync(), 'user');
      expect(
        device.root.listSync(recursive: true).whereType<File>(),
        hasLength(2),
      );
    });

    test(
      'not enough room on the target: tooBig, nothing copied, queue resumes',
      () async {
        final d = await withDone(['1']);
        device.free = 100 * _mb; // under the margin
        final to = Directory('${tmp.path}/sd');
        final r = await d.moveRoot(from: device.root, to: to);
        expect((r.ok, r.neededBytes), (false, 4));
        expect(File('${root.path}/Art/Alb/01 Song 1.mp3').existsSync(), isTrue);
        expect(to.listSync(), isEmpty);
        device.free = 100 * 1024 * _mb;
        await add(_t('5', no: 5));
        await d.keep([_t('5', no: 5)]);
        await d.whenIdle();
        expect((await db.offlineOf('subsonic://acc/5'))!.state, 'done');
      },
    );

    test(
      'keep during the move waits, then downloads into the new root',
      () async {
        final d = await withDone(['1']);
        final to = Directory('${tmp.path}/sd');
        final move = d.moveRoot(
          from: device.root,
          to: to,
          commit: () async {
            await Future<void>.delayed(const Duration(milliseconds: 30));
            await device.commitFolder(PickedFolder(to.path));
          },
        );
        await add(_t('7', no: 7));
        await d.keep([_t('7', no: 7)]);
        await move;
        await d.whenIdle();
        final row = (await db.offlineOf('subsonic://acc/7'))!;
        expect(row.state, 'done');
        expect(File('${to.path}/${row.filePath}').existsSync(), isTrue);
        expect(File('${root.path}/${row.filePath}').existsSync(), isFalse);
      },
    );
  });
}

extension on Track {
  Track copyTitle(String title) => Track(
    path: path,
    accountId: accountId,
    remoteId: remoteId,
    title: title,
    artist: artist,
    albumArtist: albumArtist,
    album: album,
    trackNo: trackNo,
    disc: disc,
    suffix: suffix,
    durationMs: durationMs,
    hasCover: hasCover,
    size: size,
  );
}

/// Client factice : [send] passe par le gestionnaire ; `close` ne fait rien de plus.
class _Client extends http.BaseClient {
  _Client(this._h);
  final Future<http.StreamedResponse> Function(http.BaseRequest) _h;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) => _h(request);
}
