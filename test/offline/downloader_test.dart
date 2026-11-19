import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/services.dart' show PlatformException;
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

/// The source of account [accountId], on its own host.
class _AccSource extends _Source {
  _AccSource(this.accountId);
  @override
  final String accountId;
  @override
  Uri downloadUri(String id) =>
      Uri.parse('https://$accountId.srv/rest/download?id=$id&t=SECRET');
  @override
  Uri streamUri(String id) =>
      Uri.parse('https://$accountId.srv/rest/stream?id=$id&t=SECRET');
}

class _Device implements Device {
  _Device(this.root);
  Directory root;
  PickedFolder? committed;
  int released = 0;
  int free = 100 * 1024 * _mb;
  bool access = true;
  Object? accessError;
  int ensureCalls = 0;
  final announced = <String>[];
  void Function()? onReachable;
  @override
  Future<Directory> musicRoot() async => root;
  @override
  Future<bool> ensureAccess({bool readOthers = false}) async {
    ensureCalls++;
    final e = accessError;
    if (e != null) throw e;
    return access;
  }

  @override
  Future<String> absolutePath(String key) async => key;
  @override
  Future<String> keyFor(String a) async => a;
  @override
  Future<int> freeBytes(String path) async => freeFn?.call() ?? free;
  int Function()? freeFn;
  @override
  Future<void> announce(String path) async => announced.add(path);
  bool reachable = true;
  @override
  Future<bool> rootReachable() async {
    onReachable?.call();
    return reachable;
  }

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
  int grow = 0; // bytes appended to the file, like real tags and cover
  bool fail = false;
  @override
  Future<TagEdit?> snapshot(TagEdit edit) async => edit;
  @override
  Future<bool> write(TagEdit edit) async {
    if (fail) throw StateError('taglib');
    writes.add(edit);
    if (grow > 0) {
      File(edit.path)
          .writeAsBytesSync(List.filled(grow, 9), mode: FileMode.append);
    }
    return true;
  }
}

Track _t(
  String id, {
  String acc = 'acc',
  int size = 4,
  String? suffix = 'mp3',
  int? no = 1,
  String album = 'Alb',
  String? cover,
}) => Track(
  path: 'subsonic://$acc/$id',
  accountId: acc,
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

/// [LibraryDb] whose folder-move write can be made to fail.
class _Db extends LibraryDb {
  _Db() : super(NativeDatabase.memory());
  bool failMove = false;
  final doneSeen =
      <(String, int, int?)>[]; // path, row size, file length right then
  Directory? doneRoot;
  @override
  Future<void> markOfflineDone(String trackPath, String filePath, int size) {
    final f = File('${doneRoot!.path}/$filePath');
    doneSeen.add((filePath, size, f.existsSync() ? f.lengthSync() : null));
    return super.markOfflineDone(trackPath, filePath, size);
  }

  /// Runs once, right before the next [isKeptPlaylist] (a « Retirer » in between).
  Future<void> Function()? beforeIsKept;
  @override
  Future<bool> isKeptPlaylist(String accountId, String playlistId) async {
    final f = beforeIsKept;
    beforeIsKept = null;
    await f?.call();
    return super.isKeptPlaylist(accountId, playlistId);
  }

  @override
  Future<void> applyOfflineMove(Map<String, String> newRel, List<String> lost) {
    if (failMove) throw StateError('db closed');
    return super.applyOfflineMove(newRel, lost);
  }
}

void main() {
  late Directory tmp, root;
  late _Db db;
  late _Device device;
  late _Reader reader;
  late _IO io;
  late AppSettings settings;
  late List<http.BaseRequest> seen;
  late Future<http.StreamedResponse> Function(http.BaseRequest) handler;

  bool Function()? gate;

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
    mayAutoDownload: gate == null ? null : () => gate!(),
  );

  Future<void> add(Track t) => db.upsertTrack(t);

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('dl');
    root = Directory('${tmp.path}/LAFLEURMUSIC');
    db = _Db();
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
    db.doneRoot = root;
    settings = AppSettings();
    seen = [];
    gate = null;
    handler = (r) async => _ok([1, 2, 3, 4]);
  });
  tearDown(() async {
    await db.close();
    tmp.deleteSync(recursive: true);
  });

  test('top100 rows wait for the gate, user rows go anyway', () async {
    var home = false;
    gate = () => home;
    final d = make();
    await add(_t('1'));
    await add(_t('2', no: 2));
    await d.keep([_t('1')], reason: OfflineReason.top100);
    await d.keep([_t('2', no: 2)]);
    await d.whenIdle();
    expect((await db.offlineOf('subsonic://acc/2'))!.state, 'done');
    expect((await db.offlineOf('subsonic://acc/1'))!.state, 'queued');
    home = true;
    d.start();
    await d.whenIdle();
    expect((await db.offlineOf('subsonic://acc/1'))!.state, 'done');
  });

  test('keep the row shown; a twin already kept or queued: no second copy, '
      'and a Top 100 copy of the twin becomes the user\'s', () async {
    final d = make();
    await add(_t('1'));
    await add(_t('1', acc: 'B')); // the same song on B
    await add(_t('2', no: 2));
    await add(_t('2', acc: 'B', no: 2));
    await add(_t('3', no: 3));
    await db.queueOffline(['subsonic://B/1'], OfflineReason.top100);
    await db.markOfflineDone('subsonic://B/1', 'Art/Alb/01.mp3', 4);
    await db.queueOffline(['subsonic://B/2'], OfflineReason.user);
    final r = await d.keep([_t('1'), _t('2', no: 2), _t('3', no: 3)]);
    expect(r.count, 1, reason: 'only acc/3 is new');
    await d.whenIdle();
    expect(await db.offlineOf('subsonic://acc/1'), isNull);
    expect(await db.offlineOf('subsonic://acc/2'), isNull);
    expect(await db.offlineOf('subsonic://acc/3'), isNotNull);
    expect((await db.offlineOf('subsonic://B/1'))!.reason, 'user');
  });

  test('Retirer on the row shown removes the twin\'s copy on another account '
      'and blocks every twin from the Top 100 (Q8)', () async {
    final d = make();
    await add(_t('1')); // kept on acc
    await add(_t('1', acc: 'B')); // the row shown (acc hidden)
    await d.keep([_t('1')]);
    await d.whenIdle();
    final file = File(
      '${root.path}/${(await db.offlineOf('subsonic://acc/1'))!.filePath}',
    );
    expect(file.existsSync(), isTrue);
    final seenBy = await db.watchOfflineWithTwins().first;
    expect(seenBy['subsonic://B/1']?.state, 'done', reason: 'shown kept');
    await d.forget(['subsonic://B/1'], byUser: true);
    expect(await db.offlineOf('subsonic://acc/1'), isNull);
    expect(file.existsSync(), isFalse);
    expect(await db.autoKeepBlockedFor('subsonic://acc/1'), isTrue);
    expect(await db.autoKeepBlockedFor('subsonic://B/1'), isTrue);
    // the Top 100 meets the other twin: not kept again
    final r = await d.keep([_t('1')], reason: OfflineReason.top100);
    expect(r.count, 0);
    expect(await db.offlineOf('subsonic://acc/1'), isNull);
    // a user « Garder » lifts the blocks of the twins too
    await d.keep([_t('1', acc: 'B')]);
    await d.whenIdle();
    expect(await db.autoKeepBlockedFor('subsonic://acc/1'), isFalse);
  });

  test('own row failed, the twin\'s copy done: no new download', () async {
    final d = make();
    await add(_t('1'));
    await add(_t('1', acc: 'B'));
    await db.queueOffline(['subsonic://B/1'], OfflineReason.user);
    await db.markOfflineDone('subsonic://B/1', 'Art/Alb/01.mp3', 4);
    await db.queueOffline(['subsonic://acc/1'], OfflineReason.user);
    for (var i = 0; i < 3; i++) {
      await db.markOfflineFailed('subsonic://acc/1');
    }
    final r = await d.keep([_t('1')]);
    expect(r.count, 0);
    expect(
      await db.offlineOf('subsonic://acc/1'),
      isNull,
      reason: 'no « À réessayer » row left to download a second copy',
    );
  });

  /// Two rows whose files differ only by case: one file where names ignore case
  /// (iOS, Android shared storage, macOS), two files where they don't (Linux, app storage).
  /// [b] is written last, so on a folder that ignores case both names hold B's bytes.
  Future<(File, File)> caseTwins(String a, String b) async {
    await add(_t('1'));
    await add(_t('1', acc: 'B'));
    final fa = File('${root.path}/$a')
      ..createSync(recursive: true)
      ..writeAsBytesSync([1, 2, 3, 4]);
    final fb = File('${root.path}/$b')
      ..createSync(recursive: true)
      ..writeAsBytesSync([5, 6, 7, 8]);
    await db.queueOffline(['subsonic://acc/1'], OfflineReason.top100);
    await db.markOfflineDone('subsonic://acc/1', a, 4);
    await db.queueOffline(['subsonic://B/1'], OfflineReason.user);
    await db.markOfflineDone('subsonic://B/1', b, 4);
    return (fa, fb);
  }

  bool sameFile(File a, File b) =>
      a.existsSync() &&
      b.existsSync() &&
      FileSystemEntity.identicalSync(a.path, b.path);

  test('two rows naming one file (a copy deleted by hand, its name reused): '
      'forgetting one keeps the file the other uses', () async {
    final d = make();
    final (fa, fb) = await caseTwins(
      'Art/Alb/01 Song 1.mp3',
      'art/alb/01 song 1.mp3',
    );
    final one = sameFile(fa, fb);
    await d.forget(['subsonic://acc/1'], only: OfflineReason.top100);
    expect(await db.offlineOf('subsonic://acc/1'), isNull);
    expect(fb.existsSync(), isTrue, reason: 'B still plays it');
    // names that keep their case: acc's own file was another file, and it went
    expect(fa.existsSync(), one);
    await d.forget(['subsonic://B/1']);
    expect(fb.existsSync(), isFalse);
    expect(fa.existsSync(), isFalse);
  });

  test('the same file under names differing by an accented capital: the other '
      'row keeps it', () async {
    final d = make();
    final (fa, fb) = await caseTwins('Été/Alb/01.mp3', 'été/Alb/01.mp3');
    final one = sameFile(fa, fb);
    await d.forget(['subsonic://acc/1'], only: OfflineReason.top100);
    expect(fb.existsSync(), isTrue, reason: 'B still plays it');
    expect(fa.existsSync(), one);
  });

  test(
    'cancelAuto drops the top100 download in flight, user rows go on',
    () async {
      final hold = Completer<void>();
      handler = (r) async {
        await hold.future;
        return _ok([1, 2, 3, 4]);
      };
      var home = true;
      gate = () => home;
      final d = make();
      await add(_t('1'));
      await add(_t('2', no: 2));
      await d.keep([_t('1')], reason: OfflineReason.top100);
      while (d.current == null) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      home = false; // left home: mobile data
      d.cancelAuto();
      await d.keep([_t('2', no: 2)]); // user row asked meanwhile
      hold.complete();
      await d.whenIdle();
      expect((await db.offlineOf('subsonic://acc/1'))!.state, 'queued');
      expect((await db.offlineOf('subsonic://acc/2'))!.state, 'done');
      expect(
        root.existsSync() &&
            root
                .listSync(recursive: true)
                .whereType<File>()
                .any((f) => f.path.contains('Song 1')),
        isFalse,
      );
    },
  );

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
    expect(Directory('${root.path}/Art/Alb').listSync().map((e) => e.path), [
      '${root.path}/Art/Alb/01 Song 1.mp3',
    ]);
    expect(device.announced, ['${root.path}/Art/Alb/01 Song 1.mp3']);
    expect(device.ensureCalls, 1);
  });

  test('a stopped loop keeps its last error, without the URL', () async {
    // a file where the artist folder should go: the copy cannot be written
    File('${root.path}/Art').createSync(recursive: true);
    final d = make();
    await add(_t('1'));
    await d.keep([_t('1')]);
    await d.whenIdle();
    expect((await db.offlineOf('subsonic://acc/1'))!.state, 'queued');
    expect(d.lastError, startsWith('FileSystemException'));

    handler = (r) async => throw http.ClientException('boom', r.url);
    d.start();
    await d.whenIdle();
    expect(d.lastError, startsWith('ClientException'));
    expect(d.lastError, isNot(contains('SECRET')));
    expect(d.lastError, isNot(contains('srv')));
  });

  test(
    'a queued row whose track is gone is dropped, the loop goes on',
    () async {
      final d = make();
      await add(_t('1'));
      await add(_t('2'));
      await db.queueOffline([
        'subsonic://acc/1',
        'subsonic://acc/2',
      ], OfflineReason.user);
      await db.deletePaths(['subsonic://acc/1']); // vanished from the server
      d.start();
      await d.whenIdle();
      expect(await db.offlineOf('subsonic://acc/1'), isNull);
      expect((await db.offlineOf('subsonic://acc/2'))!.state, 'done');
      expect(seen, hasLength(1)); // nothing requested for the vanished one
    },
  );

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

  test('the row is done with the final size, tags already written', () async {
    reader.result = const TrackTags(
      title: '',
      artist: '',
      album: '',
      durationMs: 1,
      hasCover: false,
    );
    io.grow = 100;
    final d = make();
    await add(_t('1'));
    await d.keep([_t('1')]);
    await d.whenIdle();
    final row = (await db.offlineOf('subsonic://acc/1'))!;
    final file = File('${root.path}/${row.filePath}');
    expect(file.lengthSync(), 104);
    expect(row.size, 104);
    // right when it became done, the file was already final
    expect(db.doneSeen, [('Art/Alb/01 Song 1.mp3', 104, 104)]);
    expect(io.writes.single.path, endsWith('01 Song 1.lafleur-part.mp3'));
  });

  test('a tag failure keeps the untagged copy', () async {
    reader.result = const TrackTags(
      title: '',
      artist: '',
      album: '',
      durationMs: 1,
      hasCover: false,
    );
    io.fail = true;
    final d = make();
    await add(_t('1'));
    await d.keep([_t('1')]);
    await d.whenIdle();
    final row = (await db.offlineOf('subsonic://acc/1'))!;
    expect((row.state, row.size), ('done', 4));
    expect(Directory('${root.path}/Art/Alb').listSync().length, 1);
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
    expect(
      root.existsSync() &&
          root.listSync(recursive: true).whereType<File>().isNotEmpty,
      isFalse,
    );
  });

  test('octet-stream and missing content type are accepted', () async {
    handler = (r) async => _ok([1, 2, 3, 4], type: 'application/octet-stream');
    final d = make();
    await add(_t('1'));
    await d.keep([_t('1')]);
    await d.whenIdle();
    expect((await db.offlineOf('subsonic://acc/1'))!.state, 'done');
  });

  test('pause then resume at once does not stall', () async {
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
    d.resume();
    gate.complete();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await d.whenIdle();
    expect((await db.offlineOf('subsonic://acc/1'))!.state, 'done');
    expect((await db.offlineOf('subsonic://acc/2'))!.state, 'done');
  });

  test('tags are read from the partial file, before the row is done', () async {
    String? seenState;
    reader.onRead = () async =>
        seenState = (await db.offlineOf('subsonic://acc/1'))?.state;
    final d = make();
    await add(_t('1'));
    await d.keep([_t('1')]);
    await d.whenIdle();
    expect(seenState, 'queued');
    expect((await db.offlineOf('subsonic://acc/1'))!.state, 'done');
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
    expect(
      (r.ok, r.neededBytes),
      (false, 20 * _mb),
    ); // 120 promised, 100 allowed
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
    final stale = File('${root.path}/Art/Alb/01 Song 1.lafleur-part.mp3')
      ..createSync(recursive: true)
      ..writeAsStringSync('xx');
    final legacy = File('${root.path}/Art/Alb/02 Old.mp3.lafleur.part')
      ..createSync(recursive: true);
    final foreign = File('${root.path}/Other/movie.mp4.part')
      ..createSync(recursive: true);
    await add(_t('1'));
    await db.queueOffline(['subsonic://acc/1'], OfflineReason.user);
    final d = make();
    await d.resumeAtLaunch();
    expect(stale.existsSync(), isFalse);
    expect(legacy.existsSync(), isFalse);
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
      expect(
        (r.ok, r.neededBytes),
        (false, 50 * _mb),
      ); // 150 asked, 100 allowed
      expect(await db.nextQueued(), isNull);

      settings.storageLimitBytes = 10000 * _mb;
      device.free = 300 * _mb; // 100 MiB usable after the 200 MiB margin
      r = await d.keep([_t('1', size: 150 * _mb)]);
      expect((r.ok, r.neededBytes), (false, 50 * _mb)); // 150 asked, 100 usable
      expect(await db.nextQueued(), isNull);

      // unknown size counts 10 MiB: fits
      r = await d.keep([_t('1', size: 0)]);
      expect((r.ok, r.bytes), (true, 10 * _mb));
      d.pause();
      await d.whenIdle();
    },
  );

  test('tooBig reports the shortfall, not the whole request', () async {
    final d = make();
    await add(_t('1'));
    settings.storageLimitBytes = 500 * _mb;
    var r = await d.keep([_t('1', size: 790 * _mb)]);
    expect((r.ok, r.neededBytes), (false, 290 * _mb));
    // the larger of the two shortfalls: 100 MiB usable on the disk, limit 10000
    settings.storageLimitBytes = 10000 * _mb;
    device.free = 300 * _mb;
    r = await d.keep([_t('1', size: 790 * _mb)]);
    expect((r.ok, r.neededBytes), (false, 690 * _mb));
  });

  // Top 100 copies 1..[n] (played i times, 1 MiB each, files on disk) and user copies u1..[users].
  Future<void> seedCopies(int n, {int users = 0}) async {
    Future<void> copy(String id, OfflineReason why) async {
      final t = _t(id, size: _mb);
      await add(t);
      await db.queueOffline([t.path], why);
      final rel = 'Art/Alb/$id.mp3';
      File('${root.path}/$rel')
        ..createSync(recursive: true)
        ..writeAsBytesSync(List.filled(4, 1));
      await db.markOfflineDone(t.path, rel, _mb);
    }

    for (var i = 1; i <= n; i++) {
      await copy('$i', OfflineReason.top100);
      for (var k = 0; k < i; k++) {
        await db.addPlay('subsonic://acc/$i', DateTime(2026, 1, 1, 0, 0, k));
      }
    }
    for (var i = 1; i <= users; i++) {
      await copy('u$i', OfflineReason.user);
    }
  }

  Future<Set<String>> kept(OfflineReason why) async => {
    for (final r in await db.offlineRows())
      if (r.reason == why.name) r.trackPath.substring('subsonic://acc/'.length),
  };

  test(
    'a user keep over the limit evicts the least played Top 100 copies',
    () async {
      final d = make();
      settings.storageLimitBytes = 10 * _mb;
      await seedCopies(9);
      await add(_t('20', size: _mb * 3 ~/ 2));
      await add(_t('21', size: _mb * 3 ~/ 2));
      // 9 MiB kept + 3 MiB asked, 10 MiB allowed: two copies must go
      final r = await d.keep([
        _t('20', size: _mb * 3 ~/ 2),
        _t('21', size: _mb * 3 ~/ 2),
      ]);
      expect((r.ok, r.count), (true, 2));
      expect(await kept(OfflineReason.top100), {
        for (var i = 3; i <= 9; i++) '$i',
      });
      expect(await kept(OfflineReason.user), {'20', '21'});
      expect(
        await db.autoKeepBlocked(),
        isEmpty,
        reason: 'evicted, not removed',
      );
      expect(File('${root.path}/Art/Alb/1.mp3').existsSync(), isFalse);
      expect(File('${root.path}/Art/Alb/2.mp3').existsSync(), isFalse);
      expect(File('${root.path}/Art/Alb/3.mp3').existsSync(), isTrue);
      await d.whenIdle();
    },
  );

  test(
    'a Top 100 copy outside the Top goes first, user copies never',
    () async {
      final d = make();
      settings.storageLimitBytes = 10 * _mb;
      await seedCopies(3, users: 6);
      await add(_t('9')); // kept by the Top 100, never played: lowest rank
      await db.queueOffline(['subsonic://acc/9'], OfflineReason.top100);
      await db.markOfflineDone('subsonic://acc/9', 'Art/Alb/9.mp3', _mb);
      await add(_t('20', size: _mb));
      final r = await d.keep([_t('20', size: _mb)]);
      expect(r.ok, isTrue);
      expect(await kept(OfflineReason.top100), {
        '1',
        '2',
        '3',
      }); // only '9' went
      expect(await kept(OfflineReason.user), {
        for (var i = 1; i <= 6; i++) 'u$i',
        '20',
      });
      await d.whenIdle();
    },
  );

  test('not enough Top 100 space: tooBig as before, nothing evicted', () async {
    final d = make();
    settings.storageLimitBytes = 10 * _mb;
    await seedCopies(1, users: 9);
    await add(_t('20', size: _mb * 3));
    final r = await d.keep([_t('20', size: _mb * 3)]);
    expect(
      (r.ok, r.neededBytes),
      (false, 3 * _mb),
    ); // 10 kept + 3 asked - 10 allowed
    expect(await kept(OfflineReason.top100), {'1'});
    expect(await kept(OfflineReason.user), hasLength(9));
    expect(await db.nextQueued(), isNull);
  });

  test('the Top 100 own keeps never evict anything', () async {
    final d = make();
    settings.storageLimitBytes = 10 * _mb;
    await seedCopies(10);
    await add(_t('20', size: _mb));
    final r = await d.keep([_t('20', size: _mb)], reason: OfflineReason.top100);
    expect(r.ok, isFalse);
    expect(await kept(OfflineReason.top100), hasLength(10));
  });

  test(
    'evicted copies free disk space only once their files are gone',
    () async {
      final d = make();
      settings.storageLimitBytes = 1000 * _mb;
      await seedCopies(3);
      // 200 MiB margin + 1 MiB usable, plus 1 MiB per copy file really deleted
      int gone() =>
          [for (var i = 1; i <= 3; i++) File('${root.path}/Art/Alb/$i.mp3')]
              .where((f) => !f.existsSync())
              .length;
      device.freeFn = () => 201 * _mb + gone() * _mb;
      await add(_t('20', size: _mb * 5 ~/ 2));
      final r = await d.keep([_t('20', size: _mb * 5 ~/ 2)]);
      // 2.5 MiB asked, 1 usable: 1.5 short, so two copies (1 and 2) are evicted
      expect(r.ok, isTrue);
      expect(await kept(OfflineReason.top100), {'3'});
      await d.whenIdle();
    },
  );

  test(
    'a copy that could not be freed on disk: tooBig with what is left',
    () async {
      final d = make();
      settings.storageLimitBytes = 1000 * _mb;
      await seedCopies(3);
      device.free = 201 * _mb; // deleting files frees nothing here
      await add(_t('20', size: _mb * 5 ~/ 2));
      final r = await d.keep([_t('20', size: _mb * 5 ~/ 2)]);
      expect((r.ok, r.neededBytes), (false, _mb * 3 ~/ 2));
      // the copies really went (eviction is not undone): the least played first
      expect(await kept(OfflineReason.top100), {'3'});
    },
  );

  test(
    'a failed Top 100 row is not freeable: tooBig, nothing evicted',
    () async {
      final d = make();
      settings.storageLimitBytes = 10 * _mb;
      await seedCopies(1, users: 9);
      await db.markOfflineFailed('subsonic://acc/1');
      await db.markOfflineFailed('subsonic://acc/1');
      await db.markOfflineFailed('subsonic://acc/1');
      expect((await db.offlineOf('subsonic://acc/1'))!.state, 'failed');
      await add(_t('20', size: 2 * _mb));
      final r = await d.keep([_t('20', size: 2 * _mb)]);
      // 9 MiB done + 2 asked - 10 allowed; the failed row frees nothing
      expect((r.ok, r.neededBytes), (false, _mb));
      expect(await kept(OfflineReason.top100), {'1'});
    },
  );

  test('only disk short: queued Top 100 rows are not evicted', () async {
    final d = make();
    settings.storageLimitBytes = 1000 * _mb;
    await seedCopies(2);
    await add(_t('8'));
    await db.queueOffline([
      'subsonic://acc/8',
    ], OfflineReason.top100); // least played, frees no disk
    device.freeFn = () =>
        201 * _mb +
        [for (var i = 1; i <= 2; i++) File('${root.path}/Art/Alb/$i.mp3')]
                .where((f) => !f.existsSync())
                .length *
            _mb;
    await add(_t('20', size: _mb * 2));
    final r = await d.keep([_t('20', size: _mb * 2)]);
    expect(r.ok, isTrue);
    expect(await kept(OfflineReason.top100), {'8', '2'});
    await d.whenIdle();
  });

  test('a block set between the Top 100 snapshot and its keep wins', () async {
    final d = make();
    await add(_t('1'));
    await d.forget(['subsonic://acc/1'], byUser: true);
    final r = await d.keep([_t('1')], reason: OfflineReason.top100);
    expect(r.ok, isTrue);
    expect(await db.offlineOf('subsonic://acc/1'), isNull);
    await db.queueOffline(['subsonic://acc/1'], OfflineReason.top100);
    expect(await db.offlineOf('subsonic://acc/1'), isNull);
    await d.whenIdle();
  });

  test(
    'a Top 100 keep racing a user eviction cannot take the freed room',
    () async {
      final d = make();
      settings.storageLimitBytes = 10 * _mb;
      await seedCopies(10);
      await add(_t('20', size: _mb));
      await add(_t('1', size: _mb)); // the copy about to be evicted
      final user = d.keep([_t('20', size: _mb)]);
      final auto = d.keep([_t('1', size: _mb)], reason: OfflineReason.top100);
      expect((await user).ok, isTrue);
      expect((await auto).ok, isFalse);
      expect((await db.offlineOf('subsonic://acc/20'))!.reason, 'user');
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

  test('a partial file of that name is not taken over', () async {
    final part = File('${root.path}/Art/Alb/01 Song 1.lafleur-part.mp3')
      ..createSync(recursive: true);
    final d = make();
    await add(_t('1'));
    await d.keep([_t('1')]);
    await d.whenIdle();
    final row = (await db.offlineOf('subsonic://acc/1'))!;
    expect(row.filePath, 'Art/Alb/01 Song 1 (2).mp3');
    expect(part.existsSync(), isTrue);
  });

  test('an iCloud placeholder of that name is taken: ours gets (2)', () async {
    final ph = File('${root.path}/Art/Alb/.01 Song 1.mp3.icloud')
      ..createSync(recursive: true);
    final d = make();
    await add(_t('1'));
    await d.keep([_t('1')]);
    await d.whenIdle();
    expect(
      (await db.offlineOf('subsonic://acc/1'))!.filePath,
      'Art/Alb/01 Song 1 (2).mp3',
    );
    expect(ph.existsSync(), isTrue);
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

  test(
    'chosen folder unreachable: forget drops the rows but deletes no file',
    () async {
      final d = make();
      await add(_t('1'));
      await d.keep([_t('1')]);
      await d.whenIdle();
      // the chosen folder is gone: musicRoot() answers with the default one,
      // where the same relative path is somebody else's file
      final other = File('${root.path}/Art/Alb/01 Song 1.mp3');
      expect(other.existsSync(), isTrue);
      device.reachable = false;
      await d.forget(['subsonic://acc/1']);
      expect(await db.offlineOf('subsonic://acc/1'), isNull);
      expect(other.existsSync(), isTrue);
    },
  );

  test('chosen folder unreachable: no .part sweep, no move', () async {
    final part = File('${root.path}/x.lafleur-part.mp3')
      ..createSync(recursive: true);
    device.reachable = false;
    final d = make();
    await d.resumeAtLaunch();
    await d.whenIdle();
    expect(part.existsSync(), isTrue);
    final r = await d.moveRoot(from: root, to: Directory('${tmp.path}/sd'));
    expect(r.ok, isFalse);
    expect(device.released, 1);
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

  group('chosen folder unreachable', () {
    test('keep is refused, nothing queued', () async {
      device.reachable = false;
      final d = make();
      await add(_t('1'));
      final r = await d.keep([_t('1')]);
      expect((r.ok, r.folderUnavailable), (false, true));
      expect(await db.offlineOf('subsonic://acc/1'), isNull);
      expect(seen, isEmpty);
    });

    test(
      'the loop stops before a row, nothing counted, nothing written',
      () async {
        final d = make();
        await add(_t('1'));
        await db.queueOffline(['subsonic://acc/1'], OfflineReason.user);
        device.reachable = false;
        d.start();
        await d.whenIdle();
        final row = (await db.offlineOf('subsonic://acc/1'))!;
        expect((row.state, row.failures), ('queued', 0));
        expect(seen, isEmpty);
        expect(root.existsSync(), isFalse, reason: 'never the default folder');
        device.reachable = true;
        d.start();
        await d.whenIdle();
        expect((await db.offlineOf('subsonic://acc/1'))!.state, 'done');
      },
    );
  });

  test('one row the server refuses (500): sent to the back uncounted, its '
      'account skipped this run, other accounts download', () async {
    handler = (r) async => r.url.queryParameters['id'] == '1'
        ? _ok([], code: 500)
        : _ok([1, 2, 3, 4]);
    final d = make();
    await add(_t('1'));
    await add(_t('2', no: 2));
    await add(_t('3', acc: 'other', album: 'Other'));
    await d.keep([
      _t('1'),
      _t('2', no: 2),
      _t('3', acc: 'other', album: 'Other'),
    ]);
    await d.whenIdle();
    final one = (await db.offlineOf('subsonic://acc/1'))!;
    expect((one.state, one.failures), ('queued', 0));
    expect((await db.offlineOf('subsonic://other/3'))!.state, 'done');
    expect(
      (await db.offlineOf('subsonic://acc/2'))!.state,
      'queued',
      reason: 'same account: skipped for this run',
    );
    // next run: 1 went behind, so 2 goes first
    d.start();
    await d.whenIdle();
    expect((await db.offlineOf('subsonic://acc/2'))!.state, 'done');
    expect((await db.offlineOf('subsonic://acc/1'))!.failures, 0);
  });

  test(
    'a source that cannot be built skips its account, not the queue',
    () async {
      final d = Downloader(
        db: db,
        resolver: MediaResolver(
          (id) async =>
              id == 'broken' ? throw StateError('no password') : _Source(),
        ),
        device: device,
        settings: () async => settings,
        client: () => _Client((r) async {
          seen.add(r);
          return _ok([1, 2, 3, 4]);
        }),
        tags: io,
        reader: reader,
      );
      await add(_t('1', acc: 'broken'));
      await add(_t('2', album: 'B'));
      await d.keep([_t('1', acc: 'broken'), _t('2', album: 'B')]);
      await d.whenIdle();
      expect((await db.offlineOf('subsonic://broken/1'))!.failures, 0);
      expect((await db.offlineOf('subsonic://acc/2'))!.state, 'done');
    },
  );

  group('user pause', () {
    test('sticks until Resume: automatic starts are ignored', () async {
      final d = make();
      await add(_t('1'));
      await db.queueOffline(['subsonic://acc/1'], OfflineReason.user);
      d.pause();
      d.start(); // app back to the foreground, server back, at home…
      await d.whenIdle();
      expect(seen, isEmpty);
      expect(d.userPaused, isTrue);
      await add(_t('2', no: 2));
      await d.keep([_t('2', no: 2)], reason: OfflineReason.top100);
      await d.whenIdle();
      expect(seen, isEmpty, reason: 'a Top 100 keep is automatic');
      d.resume();
      await d.whenIdle();
      expect((await db.offlineOf('subsonic://acc/1'))!.state, 'done');
      expect(d.userPaused, isFalse);
    });

    test('a new keep by the user resumes', () async {
      final d = make();
      d.pause();
      await add(_t('1'));
      await d.keep([_t('1')]);
      await d.whenIdle();
      expect((await db.offlineOf('subsonic://acc/1'))!.state, 'done');
    });
  });

  test('ensureAccess throwing ends the run quietly, with its error', () async {
    device.accessError = PlatformException(code: 'busy');
    final d = make();
    await add(_t('1'));
    await d.keep([_t('1')]);
    await d.whenIdle();
    expect(d.lastError, isNotNull);
    expect((await db.offlineOf('subsonic://acc/1'))!.state, 'queued');
    device.accessError = null;
    d.start();
    await d.whenIdle();
    expect((await db.offlineOf('subsonic://acc/1'))!.state, 'done');
  });

  test('resumeAtLaunch: a start() during the sweep waits for it', () async {
    final stale = File('${root.path}/Art/Alb/01 Song 1.lafleur-part.mp3')
      ..createSync(recursive: true);
    await add(_t('1'));
    await db.queueOffline(['subsonic://acc/1'], OfflineReason.user);
    final d = make();
    bool? sweptFirst;
    handler = (r) async {
      sweptFirst ??= !stale.existsSync();
      return _ok([1, 2, 3, 4]);
    };
    device.onReachable = () {
      device.onReachable = null;
      d.start(); // the app comes back while the folder is listed
    };
    await d.resumeAtLaunch();
    await d.whenIdle();
    expect(sweptFirst, isTrue);
    expect((await db.offlineOf('subsonic://acc/1'))!.state, 'done');
  });

  test('forget tells the media library about the removed file', () async {
    final d = make();
    await add(_t('1'));
    await d.keep([_t('1')]);
    await d.whenIdle();
    device.announced.clear();
    await d.forget(['subsonic://acc/1']);
    expect(device.announced, ['${root.path}/Art/Alb/01 Song 1.mp3']);
  });

  group('adoptRoot (old folder unreachable)', () {
    test(
      'done copies become failed without a path, then the folder is committed',
      () async {
        final d = make();
        await add(_t('1'));
        await d.keep([_t('1')]);
        await d.whenIdle();
        device.reachable = false;
        var committed = false;
        final r = await d.adoptRoot(commit: () async => committed = true);
        expect((r.ok, committed), (true, true));
        final row = (await db.offlineOf('subsonic://acc/1'))!;
        expect((row.state, row.filePath, row.size), ('failed', null, 0));
      },
    );

    test('a failed commit changes no row', () async {
      final d = make();
      await add(_t('1'));
      await d.keep([_t('1')]);
      await d.whenIdle();
      device.reachable = false;
      final r = await d.adoptRoot(
        commit: () async => throw const FileSystemException('no'),
      );
      expect(r.ok, isFalse);
      expect(device.released, 1);
      final row = (await db.offlineOf('subsonic://acc/1'))!;
      expect((row.state, row.filePath), ('done', 'Art/Alb/01 Song 1.mp3'));
    });
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

    test('moving: an iCloud placeholder at the target is not reused', () async {
      final d = await withDone(['1']);
      final to = Directory('${tmp.path}/sd');
      File('${to.path}/Art/Alb/.01 Song 1.mp3.icloud')
          .createSync(recursive: true);
      final r = await d.moveRoot(from: device.root, to: to);
      expect(r.ok, isTrue);
      expect(
        (await db.offlineOf('subsonic://acc/1'))!.filePath,
        'Art/Alb/01 Song 1 (2).mp3',
      );
    });

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

    test(
      'the rows are written before the commit; a failed write commits nothing',
      () async {
        final d = await withDone(['1']);
        final to = Directory('${tmp.path}/sd');
        File('${to.path}/Art/Alb/01 Song 1.mp3')
          ..createSync(recursive: true)
          ..writeAsStringSync('user'); // ours would be renamed (2)
        db.failMove = true;
        var committed = false;
        final r = await d.moveRoot(
          from: device.root,
          to: to,
          commit: () async => committed = true,
        );
        expect((r.ok, committed), (false, false));
        expect(
          (await db.offlineOf('subsonic://acc/1'))!.filePath,
          'Art/Alb/01 Song 1.mp3',
        );
        expect(File('${root.path}/Art/Alb/01 Song 1.mp3').existsSync(), isTrue);
        expect(
          File('${to.path}/Art/Alb/01 Song 1 (2).mp3').existsSync(),
          isFalse,
        );
        expect(device.released, 1);
      },
    );

    test('a failed commit puts the old paths back', () async {
      final d = await withDone(['1']);
      final to = Directory('${tmp.path}/sd');
      File('${to.path}/Art/Alb/01 Song 1.mp3')
        ..createSync(recursive: true)
        ..writeAsStringSync('user');
      final r = await d.moveRoot(
        from: device.root,
        to: to,
        commit: () async => throw const FileSystemException('refused'),
      );
      expect(r.ok, isFalse);
      final row = (await db.offlineOf('subsonic://acc/1'))!;
      expect((row.state, row.filePath), ('done', 'Art/Alb/01 Song 1.mp3'));
    });

    test('same folder: nothing moves, the candidate is released', () async {
      final d = await withDone(['1']);
      final r = await d.moveRoot(from: device.root, to: Directory(root.path));
      expect(r.ok, isTrue);
      expect(device.released, 1);
    });

    test('moved files are announced, old and new', () async {
      final d = await withDone(['1']);
      device.announced.clear();
      final to = Directory('${tmp.path}/sd');
      await d.moveRoot(from: device.root, to: to);
      expect(
        device.announced,
        unorderedEquals([
          '${to.path}/Art/Alb/01 Song 1.mp3',
          '${root.path}/Art/Alb/01 Song 1.mp3',
        ]),
      );
    });

    test(
      'an iCloud placeholder (not downloaded) stops the move, nothing lost',
      () async {
        final d = await withDone(['1']);
        final f = File('${root.path}/Art/Alb/01 Song 1.mp3');
        f.renameSync('${root.path}/Art/Alb/.01 Song 1.mp3.icloud');
        final to = Directory('${tmp.path}/sd');
        final r = await d.moveRoot(from: device.root, to: to);
        expect(r.ok, isFalse);
        final row = (await db.offlineOf('subsonic://acc/1'))!;
        expect((row.state, row.filePath), ('done', 'Art/Alb/01 Song 1.mp3'));
      },
    );

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
        expect(
          (r.ok, r.neededBytes),
          (false, 4 + 100 * _mb),
        ); // 4 bytes, -100 MiB usable
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

  group('server playlists', () {
    File m3u(Directory r, String name) => File('${r.path}/Playlists/$name');

    Future<void> seedLists() async {
      for (var i = 1; i <= 3; i++) {
        await add(_t('$i', no: i));
      }
      await db.replacePlaylists('acc', [
        // 1 twice, 9 absent from the account
        (
          id: 'p',
          name: 'Soirée',
          paths: [
            'subsonic://acc/1',
            'subsonic://acc/9',
            'subsonic://acc/2',
            'subsonic://acc/1',
          ],
        ),
        (
          id: 'q',
          name: 'Running',
          paths: ['subsonic://acc/2', 'subsonic://acc/3'],
        ),
      ]);
    }

    List<String> songs(File f) =>
        f.readAsLinesSync().where((l) => !l.startsWith('#')).toList();

    test('Garder: each song once, the absent one skipped; the .m3u8 follows the copies', () async {
      await seedLists();
      final d = make();
      final r = await d.keepPlaylist('acc', 'p');
      expect((r.ok, r.count), (true, 2));
      await d.whenIdle();
      expect(seen, hasLength(2));
      final f = m3u(root, 'Soirée.m3u8');
      expect(songs(f), [
        '../Art/Alb/01 Song 1.mp3',
        '../Art/Alb/02 Song 2.mp3',
        '../Art/Alb/01 Song 1.mp3',
      ]);
      expect(
        f.readAsStringSync(),
        startsWith('#EXTM3U\n#EXTINF:1,Art - Song 1\n'),
      );
      expect(device.announced, contains(f.path));
    });

    test(
      'a song removed by the user leaves the file; the last one removes it',
      () async {
        await seedLists();
        final d = make();
        await d.keepPlaylist('acc', 'p');
        await d.whenIdle();
        final f = m3u(root, 'Soirée.m3u8');
        await d.forget(['subsonic://acc/1'], byUser: true);
        expect(songs(f), ['../Art/Alb/02 Song 2.mp3']);
        await d.forget(['subsonic://acc/2'], byUser: true);
        expect(f.existsSync(), isFalse);
        expect(await db.keptPlaylistRows(), isEmpty);
      },
    );

    test('Retirer a playlist: its file and songs go, except the songs of '
        'another kept playlist', () async {
      await seedLists();
      final d = make();
      await d.keepPlaylist('acc', 'p');
      await d.keepPlaylist('acc', 'q');
      await d.whenIdle();
      expect(await d.playlistSongsToForget('acc', 'p'), [
        'subsonic://acc/1',
        'subsonic://acc/9',
      ]);
      await d.forgetPlaylist('acc', 'p');
      expect(m3u(root, 'Soirée.m3u8').existsSync(), isFalse);
      expect(await db.offlineOf('subsonic://acc/1'), isNull);
      expect((await db.offlineOf('subsonic://acc/2'))!.state, 'done');
      expect(songs(m3u(root, 'Running.m3u8')), [
        '../Art/Alb/02 Song 2.mp3',
        '../Art/Alb/03 Song 3.mp3',
      ]);
      expect(
        [for (final k in await db.keptPlaylistRows()) k.playlistId],
        ['q'],
      );
    });

    test('Garder again keeps the same file name', () async {
      await seedLists();
      final d = make();
      await d.keepPlaylist('acc', 'p');
      await d.whenIdle();
      await d.keepPlaylist('acc', 'p');
      await d.whenIdle();
      expect(Directory('${root.path}/Playlists').listSync(), hasLength(1));
    });

    Future<void> settled(Downloader d) async {
      await pumpEventQueue();
      await d.whenPlaylistsSettled();
      await d.whenIdle();
    }

    test('copies failed (folder adopted): still kept; « Réessayer » brings the '
        '.m3u8 back in the new folder', () async {
      await seedLists();
      final d = make();
      await d.keepPlaylist('acc', 'q');
      await d.whenIdle();
      final to = Directory('${tmp.path}/new');
      final r = await d.adoptRoot(commit: () async => device.root = to);
      expect(r.ok, isTrue);
      await d.forget(const []); // a refresh while every copy is failed
      expect(
        [for (final k in await db.keptPlaylistRows()) k.playlistId],
        ['q'],
      );
      // « Réessayer » = keep the failed songs again
      await d.keep([_t('2', no: 2), _t('3', no: 3)]);
      await d.whenIdle();
      expect(songs(m3u(to, 'Running.m3u8')), [
        '../Art/Alb/02 Song 2.mp3',
        '../Art/Alb/03 Song 3.mp3',
      ]);
    });

    test('Q10: a kept playlist gone from its server: our file and record go, '
        'its songs stay kept', () async {
      await seedLists();
      final d = make()..followPlaylists();
      await d.keepPlaylist('acc', 'q');
      await d.whenIdle();
      final f = m3u(root, 'Running.m3u8');
      expect(f.existsSync(), isTrue);
      await db.replacePlaylists('acc', [
        (id: 'p', name: 'Soirée', paths: ['subsonic://acc/1']),
      ]);
      await settled(d);
      expect(f.existsSync(), isFalse);
      expect(await db.keptPlaylistRows(), isEmpty);
      expect((await db.offlineOf('subsonic://acc/3'))!.state, 'done');
    });

    test('Q10: its account removed: our file and record go', () async {
      await seedLists();
      final d = make()..followPlaylists();
      await d.keepPlaylist('acc', 'q');
      await d.whenIdle();
      await db.deleteAccountPlaylists('acc');
      await settled(d);
      expect(m3u(root, 'Running.m3u8').existsSync(), isFalse);
      expect(await db.keptPlaylistRows(), isEmpty);
    });

    test(
      'Q11: Retirer a playlist does not block its songs from the Top 100',
      () async {
        await seedLists();
        final d = make();
        await d.keepPlaylist('acc', 'q');
        await d.whenIdle();
        await d.forgetPlaylist('acc', 'q');
        expect(await db.offlineOf('subsonic://acc/3'), isNull);
        expect(await db.autoKeepBlockedFor('subsonic://acc/3'), isFalse);
        final r = await d.keep([_t('3', no: 3)], reason: OfflineReason.top100);
        expect(r.count, 1);
      },
    );

    test('Q12: songs a kept playlist gains at a sync are kept; one the user '
        'removed before is not', () async {
      await seedLists();
      await add(_t('4', no: 4));
      final d = make()..followPlaylists();
      await d.keepPlaylist('acc', 'q');
      await d.whenIdle();
      await d.forget(['subsonic://acc/3'], byUser: true);
      await db.replacePlaylists('acc', [
        (
          id: 'q',
          name: 'Running',
          paths: ['subsonic://acc/2', 'subsonic://acc/3', 'subsonic://acc/4'],
        ),
      ]);
      await settled(d);
      expect((await db.offlineOf('subsonic://acc/4'))!.reason, 'user');
      expect(await db.offlineOf('subsonic://acc/3'), isNull);
      expect(songs(m3u(root, 'Running.m3u8')), [
        '../Art/Alb/02 Song 2.mp3',
        '../Art/Alb/04 Song 4.mp3',
      ]);
    });

    test('moving the folder: the .m3u8 moves with the copies', () async {
      await seedLists();
      final d = make();
      await d.keepPlaylist('acc', 'q');
      await d.whenIdle();
      final from = root;
      final to = Directory('${tmp.path}/sd');
      final r = await d.moveRoot(
        from: from,
        to: to,
        commit: () async => device.root = to,
      );
      expect(r.ok, isTrue);
      expect(m3u(from, 'Running.m3u8').existsSync(), isFalse);
      expect(songs(m3u(to, 'Running.m3u8')), [
        '../Art/Alb/02 Song 2.mp3',
        '../Art/Alb/03 Song 3.mp3',
      ]);
    });
  });

  group('one account out of reach (LAN address away from home)', () {
    var down = {'acc'};

    /// The same album on acc (first in the accounts screen) and on B; acc's server
    /// does not answer (a network error, the account marked unreachable).
    Downloader twins() {
      handler = (r) async {
        if (r.url.host == 'acc.srv') throw const SocketException('no route');
        return _ok([1, 2, 3, 4]);
      };
      return Downloader(
        db: db,
        resolver: MediaResolver((id) async => _AccSource(id)),
        device: device,
        settings: () async => settings,
        client: () => _Client((r) {
          seen.add(r);
          return handler(r);
        }),
        tags: io,
        reader: reader,
        reachable: (id) => !down.contains(id),
      );
    }

    setUp(() async {
      down = {'acc'};
      for (final (i, id) in ['acc', 'B'].indexed) {
        await db
            .into(db.accountRows)
            .insert(
              AccountRowsCompanion.insert(
                id: id,
                type: 'subsonic',
                name: id,
                base: 'https://music.example.com',
                user: 'u',
                position: i,
              ),
            );
      }
      for (var i = 1; i <= 2; i++) {
        await add(_t('$i', no: i));
        await add(_t('$i', acc: 'B', no: i));
      }
    });

    test(
      'keeping the album takes each song from the account that answers',
      () async {
        final d = twins();
        final r = await d.keep([
          _t('1'),
          _t('2', no: 2),
        ], origin: KeepOrigin.albumOf);
        expect(r.ok, isTrue);
        await d.whenIdle();
        expect((await db.offlineOf('subsonic://B/1'))?.state, 'done');
        expect((await db.offlineOf('subsonic://B/2'))?.state, 'done');
        expect(await db.offlineOf('subsonic://acc/1'), isNull);
        expect(seen.where((r) => r.url.host == 'acc.srv'), isEmpty);
        // the album removal still finds them through the twins
        expect(
          await d.toForgetFrom(KeepOrigin.albumOf(_t('1')), [
            'subsonic://acc/1',
            'subsonic://acc/2',
          ]),
          ['subsonic://acc/1', 'subsonic://acc/2'],
        );
      },
    );

    test('songs queued on it (kept at home) move to a twin; a song with no '
        'twin waits, and the other songs still download', () async {
      await add(_t('3', no: 3)); // only on acc
      await add(_t('9', acc: 'B', no: 9, album: 'Other'));
      await db.queueOffline([
        'subsonic://acc/3',
        'subsonic://acc/1',
        'subsonic://acc/2',
        'subsonic://B/9',
      ], OfflineReason.user);
      final d = twins();
      d.start();
      await d.whenIdle();
      expect((await db.offlineOf('subsonic://B/1'))?.state, 'done');
      expect((await db.offlineOf('subsonic://B/2'))?.state, 'done');
      expect((await db.offlineOf('subsonic://B/9'))?.state, 'done');
      expect(await db.offlineOf('subsonic://acc/1'), isNull);
      final waiting = (await db.offlineOf('subsonic://acc/3'))!;
      expect((waiting.state, waiting.failures), ('queued', 0));
    });

    test('a network error on an account not yet marked down still stops the '
        'queue (the phone itself is offline)', () async {
      down = {};
      await db.queueOffline([
        'subsonic://acc/1',
        'subsonic://B/2',
      ], OfflineReason.user);
      final d = twins();
      d.start();
      await d.whenIdle();
      expect((await db.offlineOf('subsonic://B/2'))?.state, 'queued');
    });

    test(
      'a copy that failed on one account is tried again from a twin',
      () async {
        down = {};
        await db.queueOffline(['subsonic://acc/1'], OfflineReason.user);
        for (var i = 0; i < 3; i++) {
          await db.markOfflineFailed('subsonic://acc/1');
        }
        final d = twins();
        await d.keep([_t('1')], origin: KeepOrigin.songOf);
        await d.whenIdle();
        expect(await db.offlineOf('subsonic://acc/1'), isNull);
        expect((await db.offlineOf('subsonic://B/1'))?.state, 'done');
      },
    );
  });

  group('keep origins (Q13)', () {
    final albumOrigin = KeepOrigin.albumOf(_t('1'));
    const albumPaths = [
      'subsonic://acc/1',
      'subsonic://acc/2',
      'subsonic://acc/3',
    ];

    /// Album Alb (1, 2, 3) kept whole, playlist « r » (2, 3, 4) kept: 2 and 3 shared.
    Future<Downloader> both() async {
      for (var i = 1; i <= 3; i++) {
        await add(_t('$i', no: i));
      }
      await add(_t('4', no: 4, album: 'Other'));
      await db.replacePlaylists('acc', [
        (
          id: 'r',
          name: 'Mix',
          paths: ['subsonic://acc/2', 'subsonic://acc/3', 'subsonic://acc/4'],
        ),
      ]);
      final d = make();
      await d.keep([
        for (var i = 1; i <= 3; i++) _t('$i', no: i),
      ], origin: KeepOrigin.albumOf);
      await d.keepPlaylist('acc', 'r');
      await d.whenIdle();
      return d;
    }

    Future<Set<String>> kept() async => {
      for (final r in await db.offlineRows()) r.trackPath,
    };

    test(
      'removing the playlist: the songs the album also keeps stay',
      () async {
        final d = await both();
        expect(await d.playlistSongsToForget('acc', 'r'), ['subsonic://acc/4']);
        await d.forgetPlaylist('acc', 'r');
        expect(await kept(), albumPaths.toSet());
        expect(await db.originsOf('subsonic://acc/2'), {albumOrigin});
      },
    );

    test(
      'removing the album: the songs the kept playlist also keeps stay',
      () async {
        final d = await both();
        expect(await d.toForgetFrom(albumOrigin, albumPaths), [
          'subsonic://acc/1',
        ]);
        await d.forgetFrom(albumOrigin, albumPaths);
        expect(await kept(), {
          'subsonic://acc/2',
          'subsonic://acc/3',
          'subsonic://acc/4',
        });
        expect(await db.autoKeepBlockedFor('subsonic://acc/1'), isTrue);
        expect(
          File('${root.path}/Playlists/Mix.m3u8')
              .readAsLinesSync()
              .where((l) => !l.startsWith('#')),
          hasLength(3),
          reason: 'the playlist file is untouched',
        );
      },
    );

    test(
      'removing one song removes it whatever keeps it, and its reasons',
      () async {
        final d = await both();
        await d.forget(['subsonic://acc/2'], byUser: true);
        expect(await db.offlineOf('subsonic://acc/2'), isNull);
        expect(await db.originsOf('subsonic://acc/2'), isEmpty);
        // later removing the playlist: 3 still has its album, 4 goes
        await d.forgetPlaylist('acc', 'r');
        expect(await kept(), {'subsonic://acc/1', 'subsonic://acc/3'});
      },
    );

    test(
      'a twin\'s reason counts (the same song on another account)',
      () async {
        await add(_t('1'));
        await add(_t('1', acc: 'B'));
        final d = make();
        await d.keep([_t('1', acc: 'B')], origin: KeepOrigin.songOf);
        await d.keep([_t('1')], origin: KeepOrigin.albumOf);
        await d.whenIdle();
        expect(
          await d.toForgetFrom(albumOrigin, ['subsonic://acc/1']),
          isEmpty,
        );
      },
    );

    test('a kept playlist with no copy left is dropped with its reasons: they '
        'no longer hold its songs when their album is removed', () async {
      final d = await both();
      // its songs' rows went away (gone from the server meanwhile, for one)
      await db.removeOffline([
        'subsonic://acc/2',
        'subsonic://acc/3',
        'subsonic://acc/4',
      ]);
      await d.playlistFiles.refresh();
      expect(await db.keptPlaylistRows(), isEmpty);
      expect(await db.originsOf('subsonic://acc/2'), {albumOrigin});
      await d.keep([_t('2', no: 2)], origin: KeepOrigin.albumOf);
      await d.whenIdle();
      expect(await d.toForgetFrom(albumOrigin, albumPaths), albumPaths);
    });

    test('a Top 100 copy has no reason: an album removal takes it', () async {
      await add(_t('1'));
      final d = make();
      await d.keep([_t('1')], reason: OfflineReason.top100);
      await d.whenIdle();
      await d.forgetFrom(albumOrigin, ['subsonic://acc/1']);
      expect(await db.offlineOf('subsonic://acc/1'), isNull);
    });

    test('at launch, a kept playlist keeps its songs without any copy, except '
        'one the user removed himself', () async {
      final d = await both();
      await d.forget(['subsonic://acc/4'], byUser: true); // blocked
      await add(_t('5', no: 5, album: 'Other'));
      await db.replacePlaylists('acc', [
        (
          id: 'r',
          name: 'Mix',
          paths: [
            'subsonic://acc/2',
            'subsonic://acc/3',
            'subsonic://acc/4',
            'subsonic://acc/5',
          ],
        ),
      ]); // no follower: the gain is seen at the next launch
      expect(await db.offlineOf('subsonic://acc/5'), isNull);
      await d.resumeAtLaunch();
      await d.whenIdle();
      expect((await db.offlineOf('subsonic://acc/5'))!.state, 'done');
      expect(await db.offlineOf('subsonic://acc/4'), isNull);
      expect(await db.originsOf('subsonic://acc/5'), {
        KeepOrigin.playlist('acc', 'r'),
      });
    });

    /// Playlist r gains song 5 on the server (no follower: nothing kept yet).
    Future<Downloader> gains() async {
      final d = await both();
      await add(_t('5', no: 5, album: 'Other'));
      await db.replacePlaylists('acc', [
        (
          id: 'r',
          name: 'Mix',
          paths: [
            'subsonic://acc/2',
            'subsonic://acc/3',
            'subsonic://acc/4',
            'subsonic://acc/5',
          ],
        ),
      ]);
      return d;
    }

    test(
      'a playlist removed between the listing and the keep keeps nothing',
      () async {
        final d = await gains();
        db.beforeIsKept = () => db.dropKeptPlaylist('acc', 'r');
        await d.syncPlaylists();
        expect(await db.offlineOf('subsonic://acc/5'), isNull);
      },
    );

    test('Retirer and the catch-up never interleave', () async {
      final d = await gains();
      await Future.wait([d.syncPlaylists(), d.forgetPlaylist('acc', 'r')]);
      await d.whenIdle();
      expect(await db.offlineOf('subsonic://acc/5'), isNull);
      expect(await db.offlineOf('subsonic://acc/4'), isNull);
      expect(await db.keptPlaylistRows(), isEmpty);
    });

    test('the catch-up keeps the user\'s Pause', () async {
      final d = await gains();
      d.pause();
      await d.syncPlaylists();
      expect(d.userPaused, isTrue);
      expect((await db.offlineOf('subsonic://acc/5'))!.state, 'queued');
    });

    test('Q15: a kept playlist gone from its server: its songs stay, kept for '
        'themselves', () async {
      final d = await both()
        ..followPlaylists();
      await db.replacePlaylists('acc', const []);
      await pumpEventQueue();
      await d.whenPlaylistsSettled();
      expect(await db.keptPlaylistRows(), isEmpty);
      expect(await db.originsOf('subsonic://acc/4'), {'song'});
      expect(await db.originsOf('subsonic://acc/2'), {albumOrigin, 'song'});
      // still removable one by one, and an album removal no longer takes 4
      expect(await d.toForgetFrom(albumOrigin, albumPaths), [
        'subsonic://acc/1',
      ]);
    });
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
