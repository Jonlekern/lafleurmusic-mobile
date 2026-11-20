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
import 'package:path/path.dart' as p;

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

  /// Moved together when the app's container moves (an iOS update).
  Directory byDefault, private;

  /// Documents, for `docs://` keys (only while [docsKeys], as on an iPhone): the parent of
  /// the default folder.
  String get docs => byDefault.parent.path;
  bool docsKeys = false;
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
      : docsKeys && key.startsWith(docsScheme)
      ? '$docs/${key.substring(docsScheme.length)}'
      : key;

  @override
  Future<String> keyFor(String a) async => a.startsWith('${private.path}/')
      ? '$appScheme${a.substring(private.path.length + 1)}'
      : docsKeys && a.startsWith('$docs/')
      ? '$docsScheme${a.substring(docs.length + 1)}'
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

  /// Completes when a move reaches [holdMove] (the test waits for it, not for a fixed delay).
  Completer<void> held = Completer<void>();
  @override
  Future<void> applyOfflineMove(
    Map<String, String> newRel,
    List<String> lost,
  ) async {
    final h = holdMove;
    if (h != null) {
      if (!held.isCompleted) held.complete();
      await h;
    }
    return super.applyOfflineMove(newRel, lost);
  }
}

/// A hook the app is "killed" at: it never returns. [reached] completes when the move gets
/// there, so a slow machine is waited for instead of a fixed delay racing the move.
Future<void> Function() _killedAt(Completer<void> reached) => () {
  if (!reached.isCompleted) reached.complete();
  return Completer<void>().future;
};

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

  test(
    'one move at a time: a second one is refused, the first one ends well',
    () async {
      final d = await keptSongs();
      final songs = _files(byDefault);
      final hold = Completer<void>();
      db.holdMove = hold.future;
      final first = d.moveKept(toApp: true);
      await db.held.future;
      expect(d.isMoving, isTrue);
      expect(d.movingKeptToApp, isTrue);
      final again = await d.moveKept(toApp: true);
      expect((again.ok, again.busy), (false, true));
      final back = await d.moveKept(toApp: false);
      expect(back.busy, isTrue);
      final root = await d.moveRoot(from: byDefault, to: chosen);
      expect(root.busy, isTrue);
      final adopt = await d.adoptRoot(commit: () async {});
      expect(adopt.busy, isTrue);
      db.holdMove = null;
      hold.complete();
      final r = await first;
      expect(r.ok, isTrue);
      expect(d.isMoving, isFalse);
      expect(d.movingKeptToApp, isNull);
      expect(settings.keepInApp, isTrue);
      expect(_files(private), songs);
      expect(_files(chosen), isEmpty);
      await expectKeptWhereTheSettingSays();
    },
  );

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
        db.held = Completer<void>();
        db.holdMove = Completer<void>().future; // never
        unawaited(d.moveKept(toApp: toApp));
        await db.held.future;
        db.holdMove = null;
        await relaunch();
        expect(settings.keepInApp, !toApp);
        await expectSound(songs);
      });

      test('$way: rows written, setting not saved: rolled back', () async {
        final (d, songs) = await ready();
        final reached = Completer<void>();
        phone.before = _killedAt(reached);
        unawaited(d.moveKept(toApp: toApp));
        await reached.future;
        phone.before = null;
        await relaunch();
        expect(settings.keepInApp, !toApp);
        await expectSound(songs);
      });

      test('$way: setting saved, originals not yet gone: finished', () async {
        final (d, songs) = await ready();
        final reached = Completer<void>();
        phone.after = _killedAt(reached);
        unawaited(d.moveKept(toApp: toApp));
        await reached.future;
        phone.after = null;
        await relaunch();
        expect(settings.keepInApp, toApp);
        await expectSound(songs);
      });
    }

    test('a copy of another size never costs its original', () async {
      final d = await keptSongs();
      final reached = Completer<void>();
      phone.after = _killedAt(reached); // setting saved, then killed
      unawaited(d.moveKept(toApp: true));
      await reached.future;
      phone.after = null;
      File('${private.path}/Art/Alb/01 Song 1.mp3').writeAsBytesSync([1]);
      await make().recoverMove();
      expect(settings.keepInApp, isTrue);
      expect(
        File('${byDefault.path}/Art/Alb/01 Song 1.mp3').existsSync(),
        isTrue,
      );
      expect(
        File('${byDefault.path}/Art/Alb/02 Song 2.mp3').existsSync(),
        isFalse,
      );
    });

    test('the app container moved by an update: still finished', () async {
      phone.docsKeys = true;
      final d = await keptSongs();
      final songs = _files(byDefault);
      final reached = Completer<void>();
      phone.after = _killedAt(reached);
      unawaited(d.moveKept(toApp: true));
      await reached.future;
      phone.after = null;
      // iOS gives the app a new container path: every folder moves with it
      final moved = Directory('${tmp.path}-updated');
      tmp.renameSync(moved.path);
      tmp = moved;
      byDefault = phone.byDefault = Directory(
        '${tmp.path}/Documents/LAFLEURMUSIC',
      );
      private = phone.private = Directory('${tmp.path}/Library/LAFLEURMUSIC');
      await relaunch();
      expect(settings.keepInApp, isTrue);
      await expectSound(songs);
    });

    test('a journal that cannot be erased is never acted on again', () async {
      final d = await keptSongs();
      final reached = Completer<void>();
      phone.after = _killedAt(reached);
      unawaited(d.moveKept(toApp: true));
      await reached.future;
      phone.after = null;
      final journal = File('${private.path}/.move.json');
      expect(journal.existsSync(), isTrue);
      // the private folder refuses deletes: the journal stays, marked done (injected, so it
      // holds as root on Linux CI too, where file rights do not stop a delete)
      final stuck = make()
        ..deleteFile = (f) async {
          if (p.isWithin(private.path, f.path)) {
            throw FileSystemException('refused', f.path);
          }
          await f.delete();
        };
      await stuck.recoverMove();
      expect(journal.existsSync(), isTrue);
      expect(byDefault.existsSync() ? _files(byDefault) : [], isEmpty);
      // later, a file of the same size put by hand where a kept song was
      final byHand = File('${byDefault.path}/Art/Alb/01 Song 1.mp3')
        ..createSync(recursive: true)
        ..writeAsBytesSync([1, 2, 3, 4]);
      await make().recoverMove();
      expect(byHand.existsSync(), isTrue);
      expect(journal.existsSync(), isFalse);
    });

    test('a copy cut short is not kept', () async {
      final (d, songs) = await () async {
        final d = await keptSongs();
        return (d, _files(byDefault));
      }();
      db.held = Completer<void>();
      db.holdMove = Completer<void>().future;
      unawaited(d.moveKept(toApp: true));
      await db.held.future;
      db.holdMove = null;
      File('${private.path}/Art/Alb/01 Song 1.mp3').writeAsBytesSync([1]);
      await relaunch();
      expect(settings.keepInApp, isFalse);
      await expectSound(songs);
    });
  });
  group(
    'songs the server dropped while in the app (local `app://` tracks)',
    () {
      const song3 = 'Art/Alb/03 Song 3.mp3';
      const appKey = '$appScheme$song3';

      /// Kept 1..3, into the app, then song 3 leaves the server: its file stays, as a local
      /// track of the private folder, with a play and a place in a phone playlist.
      Future<Downloader> dropped() async {
        final d = await keptSongs();
        await d.moveKept(toApp: true);
        await db.dropServerTracks([
          'subsonic://acc/3',
        ], root: CopyRoot(private.path, phone.keyFor));
        expect([for (final t in await db.localTracks()) t.path], [appKey]);
        await db.addPlay(appKey, DateTime(2026));
        final pl = await db
            .into(db.phonePlaylists)
            .insert(PhonePlaylistsCompanion.insert(name: 'Mine', createdAt: 1));
        await db
            .into(db.phonePlaylistItems)
            .insert(
              PhonePlaylistItemsCompanion.insert(
                playlistId: pl,
                position: 0,
                trackPath: appKey,
              ),
            );
        return d;
      }

      test('the return takes them to the visible folder: never left to go with '
          'the app', () async {
        final d = await dropped();
        expect(
          await d.bytesToMove(toApp: false),
          12,
          reason: '2 kept + 1 local',
        );
        final r = await d.moveKept(toApp: false);
        expect((r.ok, r.count, r.bytes), (true, 3, 12));
        expect(_files(private), isEmpty);
        final back = File('${byDefault.path}/$song3');
        expect(back.readAsBytesSync(), [1, 2, 3, 4]);
        final key = await phone.keyFor(back.path);
        expect([for (final t in await db.localTracks()) t.path], [key]);
        expect(await phone.absolutePath(key), back.path);
        expect((await db.top(10)).map((e) => e.$1.path), contains(key));
        final items = await db.select(db.phonePlaylistItems).get();
        expect(items.single.trackPath, key);
        // a rescan sees the same file under the same key: one track, not two
        await folder(d).rescan();
        expect([for (final t in await db.localTracks()) t.path], [key]);
        await expectKeptWhereTheSettingSays();
      });

      test('counted in the room asked for', () async {
        final d = await dropped();
        phone.free = 200 * _mb + 10; // usable: 10 bytes; 2 kept + 1 local: 12
        final r = await d.moveKept(toApp: false);
        expect((r.ok, r.neededBytes), (false, 2));
        expect(settings.keepInApp, isTrue);
        expect(File('${private.path}/$song3').existsSync(), isTrue);
        expect([for (final t in await db.localTracks()) t.path], [appKey]);
      });

      test(
        'next to a file put by hand at the same path: never written over',
        () async {
          final d = await dropped();
          final mine = File('${byDefault.path}/$song3')
            ..createSync(recursive: true)
            ..writeAsStringSync('mine');
          final r = await d.moveKept(toApp: false);
          expect(r.ok, isTrue);
          expect(mine.readAsStringSync(), 'mine');
          expect(_files(private), isEmpty);
          final locals = [for (final t in await db.localTracks()) t.path];
          expect(locals, hasLength(1));
          final moved = File(await phone.absolutePath(locals.single));
          expect(moved.path, isNot(mine.path));
          expect(moved.readAsBytesSync(), [1, 2, 3, 4]);
        },
      );

      test('killed after the rows, before the setting: rolled back', () async {
        final d = await dropped();
        final reached = Completer<void>();
        phone.before = _killedAt(reached);
        unawaited(d.moveKept(toApp: false));
        await reached.future;
        phone.before = null;
        final again = make();
        await again.recoverMove();
        await folder(again).rescan();
        expect(settings.keepInApp, isTrue);
        expect([for (final t in await db.localTracks()) t.path], [appKey]);
        expect(File('${private.path}/$song3').existsSync(), isTrue);
        expect(File('${byDefault.path}/$song3').existsSync(), isFalse);
        final items = await db.select(db.phonePlaylistItems).get();
        expect(items.single.trackPath, appKey);
      });

      test('killed after the setting, before the deletes: finished', () async {
        final d = await dropped();
        final reached = Completer<void>();
        phone.after = _killedAt(reached);
        unawaited(d.moveKept(toApp: false));
        await reached.future;
        phone.after = null;
        final again = make();
        await again.recoverMove();
        await folder(again).rescan();
        expect(settings.keepInApp, isFalse);
        final back = File('${byDefault.path}/$song3');
        expect(back.existsSync(), isTrue);
        expect(File('${private.path}/$song3').existsSync(), isFalse);
        expect(
          [for (final t in await db.localTracks()) t.path],
          [await phone.keyFor(back.path)],
        );
      });

      test(
        'in the visible folder, a dropped song stays there on the way into '
        'the app (a local file: never moved, never deleted with the app)',
        () async {
          final d = await keptSongs();
          await db.dropServerTracks([
            'subsonic://acc/3',
          ], root: CopyRoot(byDefault.path, phone.keyFor));
          final file = File('${byDefault.path}/$song3');
          expect(await d.bytesToMove(toApp: true), 8);
          await d.moveKept(toApp: true);
          await folder(d).rescan();
          expect(file.existsSync(), isTrue);
          expect(File('${private.path}/$song3').existsSync(), isFalse);
          expect([for (final t in await db.localTracks()) t.path], [file.path]);
        },
      );
    },
  );

  group(
    'after a restore or on a new phone (private folder not in the backup)',
    () {
      test(
        'in the app, kept songs whose file is gone are downloaded again',
        () async {
          final d = await keptSongs();
          await d.moveKept(toApp: true);
          final songs = _files(private);
          private.deleteSync(
            recursive: true,
          ); // restored: the database is back, not the files
          final again = make();
          await again.recoverMove();
          await again.resumeAtLaunch();
          await again.whenIdle();
          await again.whenPlaylistsSettled();
          expect(
            (await db.offlineRows()).where((r) => r.state == 'done'),
            hasLength(3),
          );
          expect(_files(private), songs);
          await expectKeptWhereTheSettingSays();
        },
      );

      test('a local song of the private folder whose file is gone leaves the '
          'library', () async {
        final d = await keptSongs();
        await d.moveKept(toApp: true);
        await db.dropServerTracks([
          'subsonic://acc/3',
        ], root: CopyRoot(private.path, phone.keyFor));
        private.deleteSync(recursive: true);
        final again = make();
        await again.recoverMove();
        await again.resumeAtLaunch();
        await again.whenIdle();
        expect(await db.localTracks(), isEmpty);
      });

      test('in the visible folder: nothing changes', () async {
        final d = await keptSongs();
        File('${byDefault.path}/Art/Alb/03 Song 3.mp3').deleteSync();
        final again = make();
        await again.recoverMove();
        await again.resumeAtLaunch();
        await again.whenIdle();
        expect(
          File('${byDefault.path}/Art/Alb/03 Song 3.mp3').existsSync(),
          isFalse,
        );
        expect((await db.offlineOf('subsonic://acc/3'))!.state, 'done');
        expect(d.isMoving, isFalse);
      });

      test(
        'a move left half done is recovered first, never re-queued',
        () async {
          final d = await keptSongs();
          final reached = Completer<void>();
          phone.after = _killedAt(reached);
          unawaited(d.moveKept(toApp: true));
          await reached.future;
          phone.after = null;
          final songs = _files(byDefault)..remove('Playlists/Soirée.m3u8');
          var downloads = 0;
          handler = (r) async {
            downloads++;
            return _ok([1, 2, 3, 4]);
          };
          final again = make();
          await again.recoverMove();
          await again.resumeAtLaunch();
          await again.whenIdle();
          expect(_files(private)..remove('Playlists/Soirée.m3u8'), songs);
          expect(downloads, 0, reason: 'every copy was there');
        },
      );
    },
  );

  test('a playlist sync during the move never writes over a .m3u8 of the '
      "user's in the folder the songs go back to", () async {
    final d = await keptSongs();
    d.followPlaylists();
    await d.moveKept(toApp: true);
    await d.whenPlaylistsSettled();
    expect(_files(private), contains('Playlists/Soirée.m3u8'));
    // in the app, the user puts a playlist of their own under the same name
    final mine = File('${byDefault.path}/Playlists/Soirée.m3u8')
      ..createSync(recursive: true)
      ..writeAsStringSync('mine');
    final hold = Completer<void>();
    final reached = Completer<void>();
    phone.after = () {
      if (!reached.isCompleted) reached.complete();
      return hold.future; // setting saved: the songs are on their way
    };
    final back = d.moveKept(toApp: false);
    await reached.future;
    // the server renames a song meanwhile: the playlists table changes
    await db.replacePlaylists('acc', [
      (
        id: 'p',
        name: 'Soirée',
        paths: ['subsonic://acc/2', 'subsonic://acc/1'],
      ),
    ]);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await d.whenPlaylistsSettled();
    expect(mine.readAsStringSync(), 'mine');
    phone.after = null;
    hold.complete();
    expect((await back).ok, isTrue);
    await d.whenPlaylistsSettled();
    expect(mine.readAsStringSync(), 'mine');
    final ours = File('${byDefault.path}/Playlists/Soirée (2).m3u8');
    expect(ours.readAsStringSync(), contains('../Art/Alb/02 Song 2.mp3'));
  });

  test('.nomedia and the journal in the private folder are never songs nor '
      'moved', () async {
    final d = await keptSongs();
    await d.moveKept(toApp: true);
    final nomedia = File('${private.path}/.nomedia')..writeAsStringSync('');
    await folder(d).rescan();
    await d.moveKept(toApp: false);
    await d.moveKept(toApp: true);
    await folder(d).rescan();
    final again = make();
    await again.recoverMove();
    await again.resumeAtLaunch();
    await again.whenIdle();
    expect(nomedia.existsSync(), isTrue);
    expect(File('${byDefault.path}/.nomedia').existsSync(), isFalse);
    expect(await db.localTracks(), isEmpty);
    expect(
      (await db.offlineRows()).where((r) => r.state == 'done'),
      hasLength(3),
    );
  });
}
