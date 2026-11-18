import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_taglib/flutter_taglib.dart' show Picture;
import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/library/db.dart';
import 'package:lafleurmusic/library/models.dart';
import 'package:lafleurmusic/tags/tag_writer.dart';

import 'fake_io.dart';

Track t(String path, String title, int no) => Track(
  path: path,
  folderId: 1,
  title: title,
  artist: 'A',
  album: 'Alb',
  trackNo: no,
  durationMs: 1,
  hasCover: false,
  mtime: 1,
  size: 1,
);

void main() {
  late LibraryDb db;
  late FakeIO io;
  late TagWriter w;
  late List<String> forgotten;
  setUp(() async {
    db = LibraryDb(NativeDatabase.memory());
    io = FakeIO();
    forgotten = [];
    for (var i = 1; i <= 5; i++) {
      io.files['/m/$i.flac'] = TagEdit(
        path: '/m/$i.flac',
        title: 'T$i',
        artist: 'A',
        album: 'Alb',
        trackNo: i,
      );
      await db.upsertTrack(t('/m/$i.flac', 'T$i', i));
    }
    w = TagWriter(db, io, forgotten.add);
  });
  tearDown(() => db.close());

  test('titre modifié : fichier et bibliothèque à jour', () async {
    final r = await w.apply([
      const TagEdit(path: '/m/1.flac', title: 'Ocean Drive'),
    ]);
    expect(r.ok, isTrue);
    expect(io.files['/m/1.flac']!.title, 'Ocean Drive');
    expect((await db.search('ocean')).single.path, '/m/1.flac');
  });

  test('pochette écrite : la piste a désormais une pochette', () async {
    await w.apply([
      TagEdit(path: '/m/2.flac', cover: Uint8List.fromList([1, 2, 3])),
    ]);
    expect(io.pictures['/m/2.flac']!.single.bytes, [1, 2, 3]);
    expect((await db.watchAlbumTracks('Alb').first)[1].hasCover, isTrue);
  });

  test('fichier en lecture seule : échec propre, rien de changé', () async {
    io.readOnly.add('/m/1.flac');
    final r = await w.apply([const TagEdit(path: '/m/1.flac', title: 'X')]);
    expect(r.ok, isFalse);
    expect(r.failedPath, '/m/1.flac');
    expect(io.files['/m/1.flac']!.title, 'T1');
    expect((await db.search('x')), isEmpty);
  });

  test('échec au 3e de 5 : les 2 premiers remis comme avant', () async {
    io.readOnly.add('/m/3.flac');
    final r = await w.apply([
      for (var i = 1; i <= 5; i++) TagEdit(path: '/m/$i.flac', trackNo: 6 - i),
    ]);
    expect(r.ok, isFalse);
    expect(
      [for (var i = 1; i <= 5; i++) io.files['/m/$i.flac']!.trackNo],
      [1, 2, 3, 4, 5],
    );
  });

  test('annuler remet l’état d’avant', () async {
    await w.apply([
      const TagEdit(path: '/m/1.flac', album: 'Night Drive'),
      const TagEdit(path: '/m/2.flac', album: 'Night Drive'),
    ]);
    expect(await w.undo(), isTrue);
    expect(io.files['/m/1.flac']!.album, 'Alb');
    expect((await db.watchAlbumTracks('Alb').first).length, 5);
    expect(await w.undo(), isFalse);
  });

  test('annuler un titre ne touche pas aux images du fichier', () async {
    final png = Picture(bytes: Uint8List.fromList([9]), mimeType: 'image/png');
    final back = Picture(
      bytes: Uint8List.fromList([8]),
      mimeType: 'image/jpeg',
      pictureType: 'Back Cover',
    );
    io.pictures['/m/1.flac'] = [png, back];
    await w.apply([const TagEdit(path: '/m/1.flac', title: 'X')]);
    await w.undo();
    expect(io.pictureWrites, 0);
    expect(io.pictures['/m/1.flac'], [png, back]);
  });

  test(
    'annuler une pochette sur un fichier qui n’en avait pas la retire',
    () async {
      await w.apply([
        TagEdit(path: '/m/1.flac', cover: Uint8List.fromList([1])),
      ]);
      forgotten.clear();
      await w.undo();
      expect(io.pictures['/m/1.flac'], isEmpty);
      expect((await db.trackByPath('/m/1.flac'))!.hasCover, isFalse);
      expect(forgotten, ['/m/1.flac']);
    },
  );

  test(
    'annuler remet toutes les images d’avant (type et format compris)',
    () async {
      final png = Picture(
        bytes: Uint8List.fromList([9]),
        mimeType: 'image/png',
      );
      final back = Picture(
        bytes: Uint8List.fromList([8]),
        mimeType: 'image/jpeg',
        pictureType: 'Back Cover',
      );
      io.pictures['/m/1.flac'] = [png, back];
      await w.apply([
        TagEdit(path: '/m/1.flac', cover: Uint8List.fromList([1])),
      ]);
      await w.undo();
      expect(io.pictures['/m/1.flac'], [png, back]);
    },
  );

  test('titre vide dans le fichier : après annulation, la bibliothèque garde le nom du fichier', () async {
    io.files['/m/1.flac'] = const TagEdit(
      path: '/m/1.flac',
      title: '',
      trackNo: 0,
    );
    await db.upsertTrack(
      Track(
        path: '/m/1.flac',
        folderId: 1,
        title: '1',
        artist: 'A',
        album: 'Alb',
        durationMs: 1,
        hasCover: false,
        mtime: 1,
        size: 1,
      ),
    );
    await w.apply([
      const TagEdit(path: '/m/1.flac', title: 'Nouveau', trackNo: 4),
    ]);
    await w.undo();
    final t1 = (await db.trackByPath('/m/1.flac'))!;
    expect(t1.title, '1');
    expect(t1.trackNo, isNull);
  });

  test('l’historique d’annulation garde les 20 dernières écritures', () async {
    for (var i = 0; i < 25; i++) {
      await w.apply([TagEdit(path: '/m/1.flac', title: 'v$i')]);
    }
    var n = 0;
    while (await w.undo()) {
      n++;
    }
    expect(n, 20);
  });

  test('pochette écrite : le cache de pochettes est prévenu', () async {
    await w.apply([
      TagEdit(path: '/m/2.flac', cover: Uint8List.fromList([1])),
    ]);
    expect(forgotten, ['/m/2.flac']);
  });
}
