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
  @override
  Future<TrackTags?> read(String path) async {
    reads.add(path);
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
  @override
  Future<bool> ensureAccess({bool readOthers = false}) async {
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
      await folder.rescan(); // no permission: can't tell
      expect(await db.localTracks(), hasLength(1));
      device.access = true;
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
}
