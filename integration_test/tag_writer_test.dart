// Écriture réelle avec TagLib sur des copies des fichiers d'exemple (plan 3, tâche 1).
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_taglib/flutter_taglib.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:drift/native.dart';
import 'package:lafleurmusic/library/db.dart';
import 'package:lafleurmusic/tags/tag_writer.dart';

const fixtures = String.fromEnvironment('FIXTURES');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final io = TagLibIO();

  for (final name in ['a.flac', 'a.mp3', 'a.m4a', 'a.opus', 'a.wv']) {
    testWidgets('écrit titre, piste et pochette dans $name', (tester) async {
      final dir = Directory.systemTemp.createTempSync('tw');
      final f = File('$fixtures/$name').copySync('${dir.path}/$name');
      final jpg = Uint8List.fromList(
        img.encodeJpg(img.Image(width: 50, height: 50)),
      );
      final ok = await tester.runAsync(
        () => io.write(
          TagEdit(path: f.path, title: 'Ocean Drive é', trackNo: 7, cover: jpg),
        ),
      );
      expect(ok, isTrue);
      final r = TagLibFile.open(f.path)!;
      expect(r.title, 'Ocean Drive é');
      expect(r.track, 7);
      expect(r.hasCover, isTrue);
      r.close();
      dir.deleteSync(recursive: true);
    });
  }

  testWidgets('fichier en lecture seule : refusé', (tester) async {
    final dir = Directory.systemTemp.createTempSync('tw');
    final f = File('$fixtures/a.flac').copySync('${dir.path}/ro.flac');
    Process.runSync('chmod', ['444', f.path]);
    final ok = await tester.runAsync(
      () => io.write(TagEdit(path: f.path, title: 'X')),
    );
    expect(ok, isFalse);
    Process.runSync('chmod', ['644', f.path]);
    dir.deleteSync(recursive: true);
  });

  testWidgets('annuler un titre garde toutes les images (PNG, dos)', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('tw');
    final f = File('$fixtures/a.flac').copySync('${dir.path}/pics.flac');
    final png = Uint8List.fromList(
      img.encodePng(img.Image(width: 20, height: 20)),
    );
    final back = Uint8List.fromList(
      img.encodeJpg(img.Image(width: 30, height: 30)),
    );
    final w0 = TagLibFile.open(f.path)!;
    w0.setPictures([
      Picture(bytes: png, mimeType: 'image/png'),
      Picture(bytes: back, mimeType: 'image/jpeg', pictureType: 'Back Cover'),
    ]);
    w0.save();
    w0.close();
    final db = LibraryDb(NativeDatabase.memory());
    final w = TagWriter(db, io);
    await tester.runAsync(() async {
      await w.apply([TagEdit(path: f.path, title: 'X')]);
      await w.undo();
    });
    final r = TagLibFile.open(f.path)!;
    final pics = r.pictures;
    r.close();
    expect(pics.length, 2);
    expect(pics[0].mimeType, 'image/png');
    expect(pics[1].pictureType, 'Back Cover');
    await tester.runAsync(db.close);
    dir.deleteSync(recursive: true);
  });

  testWidgets('annuler une pochette sur un fichier sans pochette la retire', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('tw');
    final f = File('$fixtures/a.mp3').copySync('${dir.path}/nocover.mp3');
    final w0 = TagLibFile.open(f.path)!;
    w0.setCover(data: null);
    w0.save();
    w0.close();
    final db = LibraryDb(NativeDatabase.memory());
    final w = TagWriter(db, io);
    final jpg = Uint8List.fromList(
      img.encodeJpg(img.Image(width: 50, height: 50)),
    );
    await tester.runAsync(() async {
      await w.apply([TagEdit(path: f.path, cover: jpg)]);
      await w.undo();
    });
    final r = TagLibFile.open(f.path)!;
    expect(r.hasCover, isFalse);
    r.close();
    await tester.runAsync(db.close);
    dir.deleteSync(recursive: true);
  });
}
