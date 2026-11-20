import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lafleurmusic/library/db.dart';
import 'package:lafleurmusic/library/models.dart';
import 'package:lafleurmusic/offline/device.dart';
import 'package:lafleurmusic/offline/downloader.dart';
import 'package:lafleurmusic/offline/local_folder.dart';
import 'package:lafleurmusic/offline/paths.dart' show isPartialName;
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
  Map<String, String> get headers => const {};
  @override
  Uri downloadUri(String id) => Uri.parse('https://srv/rest/download?id=$id');
  @override
  Uri streamUri(String id) => Uri.parse('https://srv/rest/stream?id=$id');
  @override
  Uri coverUri(String id, int size) => Uri.parse('https://srv/cover?id=$id');
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Client extends http.BaseClient {
  _Client(this._h);
  final Future<http.StreamedResponse> Function(http.BaseRequest) _h;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) => _h(request);
}

class _IO implements TagFileIO {
  @override
  Future<TagEdit?> snapshot(TagEdit edit) async => edit;
  @override
  Future<bool> write(TagEdit edit) async => true;
}

class _Reader implements TagReader {
  @override
  Future<TrackTags?> read(String path) async => TrackTags(
    title: 'T ${path.split('/').last}',
    artist: 'Art',
    album: 'Alb',
    durationMs: 1000,
    hasCover: false,
  );
}

/// A phone with the default visible folder, maybe a chosen one ([AppSettings.musicFolder],
/// answering while [chosenAnswers]) and the app's private folder; `keepInApp` lives in the
/// same [AppSettings] the downloader reads.
class _Phone implements Device {
  _Phone(this.settings, this.byDefault, this.private);
  final AppSettings settings;
  final Directory byDefault, private;
  bool chosenAnswers = true;
  int free = 100 * 1024 * _mb;
  int accessAsks = 0;
  int privateCreates = 0;
  final announced = <String>[];

  /// Runs inside [setKeepInApp]: [before] ahead of the change, [after] once it is saved.
  Future<void> Function()? before, after;

  @override
  Future<Directory> visibleRoot() async {
    final c = settings.musicFolder;
    return c != null && chosenAnswers ? Directory(c) : byDefault;
  }

  @override
  Future<Directory> keptRoot() async =>
      settings.keepInApp ? await privateRoot() : await visibleRoot();

  @override
  Future<Directory> privateRoot({bool create = true}) async {
    if (create && !private.existsSync()) {
      privateCreates++;
      private.createSync(recursive: true);
    }
    return private;
  }

  @override
  Future<void> setKeepInApp(bool value, {bool forgetFolder = false}) async {
    await before?.call();
    settings.keepInApp = value;
    if (forgetFolder) settings.musicFolder = null;
    await after?.call();
  }

  @override
  Future<bool> rootReachable() async =>
      settings.keepInApp || await visibleReachable();

  @override
  Future<bool> visibleReachable() async =>
      settings.musicFolder == null || chosenAnswers;

  @override
  Future<bool> ensureAccess({bool readOthers = false}) async {
    accessAsks++;
    return true;
  }

  @override
  Future<String> absolutePath(String key) async => key.startsWith(appScheme)
      ? '${private.path}/${key.substring(appScheme.length)}'
      : key;

  @override
  Future<String> keyFor(String a) async => a.startsWith('${private.path}/')
      ? '$appScheme${a.substring(private.path.length + 1)}'
      : a;

  @override
  Future<int> freeBytes(String path) async => free;

  @override
  Future<void> announce(String path) async => announced.add(path);

  @override
  Future<PickedFolder?> pickFolder() async => null;
  @override
  Future<void> releaseCandidate() async {}
  @override
  Future<void> commitFolder(PickedFolder c) async =>
      settings.musicFolder = c.path;
}

/// A database whose move write can be held (the app killed right there).
class _Db extends LibraryDb {
  _Db() : super(NativeDatabase.memory());
  Future<void>? holdMove;
  @override
  Future<void> applyOfflineMove(
    Map<String, String> newRel,
    List<String> lost,
  ) async {
    final h = holdMove;
    if (h != null) await h;
    return super.applyOfflineMove(newRel, lost);
  }
}

Track _t(String id, {int no = 1, int size = 4}) => Track(
  path: 'subsonic://acc/$id',
  accountId: 'acc',
  remoteId: id,
  title: 'Song $id',
  artist: 'Art',
  albumArtist: 'Art',
  album: 'Alb',
  trackNo: no,
  disc: 1,
  suffix: 'mp3',
  durationMs: 1000,
  hasCover: false,
  size: size,
);

http.StreamedResponse _ok(List<int> body) => http.StreamedResponse(
  Stream.value(body),
  200,
  contentLength: body.length,
  headers: {'content-type': 'audio/mpeg'},
);

/// Every file under [d], relative, sorted (none if it does not exist).
List<String> _files(Directory d) {
  if (!d.existsSync()) return [];
  return [
    for (final e in d.listSync(recursive: true))
      if (e is File) e.path.substring(d.path.length + 1),
  ]..sort();
}

void main() {
  late Directory tmp, byDefault, chosen, private;
  late _Db db;
  late AppSettings settings;
  late _Phone phone;
  late Future<http.StreamedResponse> Function(http.BaseRequest) handler;

  Downloader make() => Downloader(
    db: db,
    resolver: MediaResolver((_) async => _Source()),
    device: phone,
    settings: () async => settings,
    client: () => _Client((r) => handler(r)),
    tags: _IO(),
    reader: _Reader(),
  );

  LocalFolder folder(Downloader d) => LocalFolder(
    db: db,
    device: phone,
    reader: _Reader(),
    inFlight: () => d.targetPath,
    moving: () => d.movingFiles,
  );

  /// Songs 1..[n] kept (downloaded), and playlist « Soirée » with 1 and 2 kept.
  Future<Downloader> keptSongs({int n = 3}) async {
    final d = make();
    for (var i = 1; i <= n; i++) {
      await db.upsertTrack(_t('$i', no: i));
    }
    await db.replacePlaylists('acc', [
      (
        id: 'p',
        name: 'Soirée',
        paths: ['subsonic://acc/1', 'subsonic://acc/2'],
      ),
    ]);
    await d.keepPlaylist('acc', 'p');
    await d.keep([for (var i = 3; i <= n; i++) _t('$i', no: i)]);
    await d.whenIdle();
    await d.whenPlaylistsSettled();
    return d;
  }

  /// Each kept row: its file is in the kept root, and nowhere else.
  Future<void> expectKeptWhereTheSettingSays() async {
    final kept = await phone.keptRoot();
    final other = settings.keepInApp ? await phone.visibleRoot() : private;
    for (final r in await db.offlineRows()) {
      if (r.state != OfflineState.done.name) continue;
      expect(
        File('${kept.path}/${r.filePath}').existsSync(),
        isTrue,
        reason: '${r.trackPath} in ${kept.path}',
      );
      expect(
        File('${other.path}/${r.filePath}').existsSync(),
        isFalse,
        reason: '${r.trackPath} left in ${other.path}',
      );
    }
  }

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('move');
    byDefault = Directory('${tmp.path}/Documents/LAFLEURMUSIC')
      ..createSync(recursive: true);
    chosen = Directory('${tmp.path}/iCloud/Music')..createSync(recursive: true);
    private = Directory('${tmp.path}/Library/LAFLEURMUSIC');
    db = _Db();
    settings = AppSettings();
    phone = _Phone(settings, byDefault, private);
    handler = (r) async => _ok([1, 2, 3, 4]);
  });
  tearDown(() async {
    await db.close();
    tmp.deleteSync(recursive: true);
  });

  test('the private folder is not made until songs go there', () async {
    final d = await keptSongs();
    expect(private.existsSync(), isFalse);
    await d.moveKept(toApp: true);
    expect(private.existsSync(), isTrue);
  });

  test('into the app and back: each kept file and each .m3u8 returns to the '
      'same relative path; rows follow', () async {
    final d = await keptSongs();
    final before = _files(byDefault);
    expect(before, contains('Playlists/Soirée.m3u8'));
    final rows = {
      for (final r in await db.offlineRows()) r.trackPath: r.filePath,
    };

    final r = await d.moveKept(toApp: true);
    expect((r.ok, r.count, r.bytes), (true, 3, 12));
    expect(settings.keepInApp, isTrue);
    expect(_files(private), before);
    expect(_files(byDefault), isEmpty);
    expect({
      for (final r in await db.offlineRows()) r.trackPath: r.filePath,
    }, rows);
    await expectKeptWhereTheSettingSays();
    // the originals leaving the visible folder are told to the media library
    // (ChannelDevice itself never announces the private folder: device_roots_test)
    expect(
      phone.announced,
      containsAll(['${byDefault.path}/Art/Alb/01 Song 1.mp3']),
    );

    final back = await d.moveKept(toApp: false);
    expect((back.ok, back.count), (true, 3));
    expect(settings.keepInApp, isFalse);
    expect(_files(byDefault), before);
    expect(_files(private), isEmpty);
    expect({
      for (final r in await db.offlineRows()) r.trackPath: r.filePath,
    }, rows);
    await expectKeptWhereTheSettingSays();
    expect(
      File('${byDefault.path}/Playlists/Soirée.m3u8').readAsStringSync(),
      contains('../Art/Alb/01 Song 1.mp3'),
    );
  });

  test('already there: nothing to do', () async {
    final d = await keptSongs();
    final r = await d.moveKept(toApp: false);
    expect((r.ok, r.count), (true, 0));
    expect(private.existsSync(), isFalse);
  });

  test('2. not enough room: refused with the shortfall of the sum of the kept '
      'files, nothing moved', () async {
    final d = await keptSongs();
    final before = _files(byDefault);
    phone.free = 200 * _mb + 10; // usable: 10 bytes, kept: 3 x 4 bytes
    final r = await d.moveKept(toApp: true);
    expect((r.ok, r.neededBytes), (false, 12 - 10));
    expect(settings.keepInApp, isFalse);
    expect(_files(byDefault), before);
    expect(_files(private), isEmpty);
    await expectKeptWhereTheSettingSays();
  });

  test('1. a download under way stops cleanly and finishes in the new '
      'folder, no half file left', () async {
    final d = await keptSongs(n: 2);
    final gate = Completer<void>();
    handler = (r) async {
      final c = StreamController<List<int>>();
      c.add([1, 2]);
      unawaited(
        gate.future.then((_) async {
          c.add([3, 4]);
          await c.close();
        }),
      );
      return http.StreamedResponse(
        c.stream,
        200,
        contentLength: 4,
        headers: {'content-type': 'audio/mpeg'},
      );
    };
    await db.upsertTrack(_t('9', no: 9));
    await d.keep([_t('9', no: 9)]);
    while (!_files(byDefault).any(isPartialName)) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    final move = d.moveKept(toApp: true);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    handler = (r) async => _ok([1, 2, 3, 4]);
    gate.complete();
    final r = await move;
    expect(r.ok, isTrue);
    await d.whenIdle();
    final row = (await db.offlineOf('subsonic://acc/9'))!;
    expect(row.state, 'done');
    expect(File('${private.path}/${row.filePath}').existsSync(), isTrue);
    expect(_files(byDefault), isEmpty, reason: 'no .part, no copy left');
    expect(_files(private).where(isPartialName), isEmpty);
  });

  test('in the app, downloads never ask for storage rights', () async {
    await (await keptSongs(n: 1)).moveKept(toApp: true);
    final d = make(); // a new launch: nothing asked yet
    final asked = phone.accessAsks;
    await db.upsertTrack(_t('5', no: 5));
    await d.keep([_t('5', no: 5)]);
    await d.whenIdle();
    expect((await db.offlineOf('subsonic://acc/5'))!.state, 'done');
    expect(phone.accessAsks, asked);
  });

  group('4. a chosen folder', () {
    setUp(() => settings.musicFolder = chosen.path);

    test('songs leave it for the app, and come back to it', () async {
      final d = await keptSongs();
      final before = _files(chosen);
      expect(before, isNotEmpty);
      await d.moveKept(toApp: true);
      expect(_files(chosen), isEmpty);
      expect(settings.musicFolder, chosen.path, reason: 'kept for the return');
      await d.moveKept(toApp: false);
      expect(_files(chosen), before);
      expect(_files(byDefault), isEmpty);
      await expectKeptWhereTheSettingSays();
    });

    test('gone by the return: the default folder is adopted', () async {
      final d = await keptSongs();
      final before = _files(chosen);
      await d.moveKept(toApp: true);
      phone.chosenAnswers = false;
      final r = await d.moveKept(toApp: false);
      expect(r.ok, isTrue);
      expect(settings.musicFolder, isNull);
      expect(_files(byDefault), before);
      await expectKeptWhereTheSettingSays();
    });

    test('gone before going into the app: refused, nothing moves', () async {
      final d = await keptSongs();
      phone.chosenAnswers = false;
      final r = await d.moveKept(toApp: true);
      expect(r.ok, isFalse);
      expect(settings.keepInApp, isFalse);
      phone.chosenAnswers = true;
      await expectKeptWhereTheSettingSays();
    });
  });

  group('5. a file put by hand in the visible folder', () {
    test('never moved, listed in both modes', () async {
      final d = await keptSongs();
      final mine = File('${byDefault.path}/Mine/Track.mp3')
        ..createSync(recursive: true)
        ..writeAsStringSync('abcd');
      final lf = folder(d);
      await lf.rescan();
      Future<List<String>> locals() async => [
        for (final t in await db.localTracks()) t.path,
      ];
      expect(await locals(), [mine.path]);
      await d.moveKept(toApp: true);
      await lf.rescan();
      expect(mine.existsSync(), isTrue);
      expect(await locals(), [mine.path], reason: 'kept songs are not local');
      await d.moveKept(toApp: false);
      await lf.rescan();
      expect(mine.readAsStringSync(), 'abcd');
      expect(await locals(), [mine.path]);
    });

    test('at the path a kept song comes back to: never written over', () async {
      final d = await keptSongs(n: 1);
      await d.moveKept(toApp: true);
      final mine = File('${byDefault.path}/Art/Alb/01 Song 1.mp3')
        ..createSync(recursive: true)
        ..writeAsStringSync('mine');
      await d.moveKept(toApp: false);
      expect(mine.readAsStringSync(), 'mine');
      await expectKeptWhereTheSettingSays();
    });
  });

  test('a rescan in the middle of the move takes no song left behind for a '
      'file put by hand', () async {
    final d = await keptSongs();
    final lf = folder(d);
    await lf.rescan();
    phone.after = () => lf.rescan(); // the originals are still there
    await d.moveKept(toApp: true);
    phone.after = null;
    expect(await db.localTracks(), isEmpty);
    phone.after = () => lf.rescan();
    await d.moveKept(toApp: false);
    expect(await db.localTracks(), isEmpty);
  });

  group('3. the app killed during the move', () {
    /// The first app is stuck (killed) at a point; a new one starts on the same files.
    Future<void> relaunch() async {
      final again = make();
      await again.recoverMove();
      await again.resumeAtLaunch();
      await again.whenIdle();
      await again.whenPlaylistsSettled();
      await folder(again).rescan();
    }

    Future<void> expectSound(List<String> songs) async {
      await expectKeptWhereTheSettingSays();
      final rows = await db.offlineRows();
      expect(rows.where((r) => r.state == 'done'), hasLength(3));
      expect(await db.localTracks(), isEmpty, reason: 'no leftover imported');
      final kept = await phone.keptRoot();
      final other = settings.keepInApp ? byDefault : private;
      expect(_files(kept), songs);
      expect(_files(other), isEmpty);
    }

    for (final toApp in [true, false]) {
      final way = toApp ? 'into the app' : 'back';

      Future<(Downloader, List<String>)> ready() async {
        final d = await keptSongs();
        if (!toApp) await d.moveKept(toApp: true);
        final songs = _files(await phone.keptRoot());
        return (d, songs);
      }

      test('$way: after copying, before the rows: rolled back', () async {
        final (d, songs) = await ready();
        db.holdMove = Completer<void>().future; // never
        unawaited(d.moveKept(toApp: toApp));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        db.holdMove = null;
        await relaunch();
        expect(settings.keepInApp, !toApp);
        await expectSound(songs);
      });

      test('$way: rows written, setting not saved: rolled back', () async {
        final (d, songs) = await ready();
        phone.before = () => Completer<void>().future;
        unawaited(d.moveKept(toApp: toApp));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        phone.before = null;
        await relaunch();
        expect(settings.keepInApp, !toApp);
        await expectSound(songs);
      });

      test('$way: setting saved, originals not yet gone: finished', () async {
        final (d, songs) = await ready();
        phone.after = () => Completer<void>().future;
        unawaited(d.moveKept(toApp: toApp));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        phone.after = null;
        await relaunch();
        expect(settings.keepInApp, toApp);
        await expectSound(songs);
      });
    }

    test('a copy cut short is not kept', () async {
      final (d, songs) = await () async {
        final d = await keptSongs();
        return (d, _files(byDefault));
      }();
      db.holdMove = Completer<void>().future;
      unawaited(d.moveKept(toApp: true));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      db.holdMove = null;
      File('${private.path}/Art/Alb/01 Song 1.mp3').writeAsBytesSync([1]);
      await relaunch();
      expect(settings.keepInApp, isFalse);
      await expectSound(songs);
    });
  });
}
