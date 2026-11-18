import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/library/db.dart';
import 'package:lafleurmusic/library/models.dart';
import 'package:lafleurmusic/offline/local_folder.dart';
import 'package:lafleurmusic/tags/tag_reader.dart';

import 'fake_device.dart';

class _Reader implements TagReader {
  final reads = <String>[];
  Future<void> Function()? onRead;
  @override
  Future<TrackTags?> read(String path) async {
    reads.add(path);
    await onRead?.call();
    return TrackTags(
      title: 'T ${path.split('/').last}',
      artist: 'Art',
      album: 'Alb',
      durationMs: 1000,
      hasCover: false,
    );
  }
}

class _Device extends FakeDevice {
  _Device(super.root, {super.docs});
  bool access = true;
  bool? askedOthers;
  int asks = 0;
  bool throws = false;
  @override
  Future<bool> ensureAccess({bool readOthers = false}) async {
    asks++;
    if (throws) throw StateError('busy');
    askedOthers = readOthers;
    return access;
  }
}

void main() {
  late Directory tmp, root;
  late LibraryDb db;
  late _Device device;
  late _Reader reader;
  late LocalFolder folder;

  File put(String rel, [String body = 'abcd']) {
    final f = File('${root.path}/$rel')..createSync(recursive: true);
    f.writeAsStringSync(body);
    return f;
  }

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('lf');
    root = Directory('${tmp.path}/LAFLEURMUSIC')..createSync();
    db = LibraryDb(NativeDatabase.memory());
    device = _Device(root);
    reader = _Reader();
    folder = LocalFolder(db: db, device: device, reader: reader);
  });
  tearDown(() async {
    await db.close();
    tmp.deleteSync(recursive: true);
  });

  test('a hand-placed file becomes a local track with its tags', () async {
    final f = put('Mine/song.flac');
    await folder.rescan();
    final t = await db.trackByPath(f.path);
    expect(t, isNotNull);
    expect(t!.accountId, 'local');
    expect(t.title, 'T song.flac');
    expect(device.askedOthers, isTrue);
  });

  test(
    'unchanged files are not read again; the rest of the folder is ignored',
    () async {
      put('a.mp3');
      put('b.txt');
      put('.lafleur_probe');
      await folder.rescan();
      await folder.rescan();
      expect(reader.reads, hasLength(1));
      expect((await db.localTracks()), hasLength(1));
    },
  );

  test(
    'a kept copy is not duplicated, a partial download is ignored',
    () async {
      final kept = put('A/B/01 x.mp3');
      put('A/B/02 y.mp3.lafleur.part');
      await db.upsertTrack(
        Track(
          path: 'subsonic://acc/1',
          accountId: 'acc',
          remoteId: '1',
          title: 'x',
          artist: 'A',
          album: 'B',
          durationMs: 1,
          hasCover: false,
          size: 4,
        ),
      );
      await db.queueOffline(['subsonic://acc/1'], OfflineReason.user);
      await db.markOfflineDone('subsonic://acc/1', 'A/B/01 x.mp3', 4);
      await folder.rescan();
      expect(await db.trackByPath(kept.path), isNull);
      expect(await db.localTracks(), isEmpty);
    },
  );

  test(
    'an orphan copy (already local) keeps its plays and is not re-read',
    () async {
      final f = put('A/B/01 x.mp3');
      await db.upsertTrack(
        Track(
          path: f.path,
          title: 'Kept title',
          artist: 'A',
          album: 'B',
          durationMs: 5,
          hasCover: false,
          size: 4,
          mtime: f.statSync().modified.millisecondsSinceEpoch,
        ),
      );
      await db.addPlay(f.path, DateTime(2026));
      await folder.rescan();
      expect(reader.reads, isEmpty);
      expect((await db.localTracks()).single.title, 'Kept title');
      expect((await db.select(db.playCounts).get()).single.count, 1);
    },
  );

  test(
    'iPhone: Documents files get docs:// keys and match existing ones',
    () async {
      final docs = Directory('${tmp.path}/Documents')..createSync();
      root = Directory('${docs.path}/LAFLEURMUSIC')..createSync();
      device = _Device(root, docs: docs);
      folder = LocalFolder(db: db, device: device, reader: reader);
      put('x.flac');
      await folder.rescan();
      await folder.rescan();
      expect(
        (await db.localTracks()).single.path,
        'docs://LAFLEURMUSIC/x.flac',
      );
      expect(reader.reads, hasLength(1));
    },
  );

  test(
    'a removed file is removed with its plays, but only if the folder answers',
    () async {
      final f = put('gone.mp3');
      await folder.rescan();
      await db.addPlay(f.path, DateTime(2026));
      f.deleteSync();
      device.reachable = false;
      await folder.rescan();
      expect(await db.localTracks(), hasLength(1));
      device.reachable = true;
      device.access = false;
      folder = LocalFolder(db: db, device: device, reader: reader); // new launch
      await folder.rescan(); // no permission: can't tell
      expect(await db.localTracks(), hasLength(1));
      device.access = true;
      folder = LocalFolder(db: db, device: device, reader: reader); // next launch
      await folder.rescan();
      expect(await db.localTracks(), isEmpty);
      expect(await db.select(db.playCounts).get(), isEmpty);
    },
  );

  test('hand-placed files are never touched', () async {
    final f = put('keep.mp3', 'zzzz');
    final before = f.statSync();
    await folder.rescan();
    expect(f.readAsStringSync(), 'zzzz');
    expect(f.statSync().modified, before.modified);
  });

  Track kept(String id) => Track(
    path: 'subsonic://acc/$id',
    accountId: 'acc',
    remoteId: id,
    title: 'x',
    artist: 'A',
    album: 'B',
    durationMs: 1,
    hasCover: false,
    size: 4,
  );

  test('a copy stored by the downloader during the scan is not taken as hand-placed', () async {
    final f = put('A/B/01 x.mp3');
    await db.upsertTrack(kept('1'));
    await db.queueOffline(['subsonic://acc/1'], OfflineReason.user);
    reader.onRead = () async {
      await db.markOfflineDone('subsonic://acc/1', 'A/B/01 x.mp3', 4);
    };
    await folder.rescan();
    expect(await db.trackByPath(f.path), isNull);
  });

  test('a file the downloader is writing right now is left alone', () async {
    final f = put('A/B/01 x.mp3');
    folder = LocalFolder(
      db: db,
      device: device,
      reader: reader,
      inFlight: () => f.path,
    );
    await folder.rescan();
    expect(await db.localTracks(), isEmpty);
  });

  test('an existing duplicate of a finished copy is healed, plays go to the server track', () async {
    final f = put('A/B/01 x.mp3');
    await db.upsertTrack(kept('1'));
    await db.queueOffline(['subsonic://acc/1'], OfflineReason.user);
    await db.markOfflineDone('subsonic://acc/1', 'A/B/01 x.mp3', 4);
    await db.upsertTrack(
      Track(path: f.path, title: 'dup', artist: '', album: '', durationMs: 1, hasCover: false, size: 4),
    );
    await db.addPlay(f.path, DateTime(2026));
    await db.addPlay('subsonic://acc/1', DateTime(2026));
    await folder.rescan();
    expect(await db.localTracks(), isEmpty);
    final plays = (await db.select(db.playCounts).get()).single;
    expect(plays.path, 'subsonic://acc/1');
    expect(plays.count, 2); // summed, not overwritten
    expect(f.existsSync(), isTrue); // the file is never touched
  });

  test('a throwing permission request does not escape and counts as refused', () async {
    put('a.mp3');
    device.throws = true;
    await folder.rescan();
    expect(await db.localTracks(), hasLength(1)); // our own folder is still read
  });

  test('the permission is asked once per launch, not at every resume', () async {
    put('a.mp3');
    await folder.rescan();
    await folder.rescan();
    await folder.rescan();
    expect(device.asks, 1);
  });
}
