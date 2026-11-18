import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lafleurmusic/library/covers.dart';

Uint8List png(int r) => Uint8List.fromList(
  img.encodePng(
    img.Image(width: 800, height: 800)..clear(img.ColorRgb8(r, 0, 0)),
  ),
);

void main() {
  late Directory dir;
  late int embeddedCalls;
  late Map<String, Uint8List?> embedded;
  late Covers covers;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('covers');
    Directory('${dir.path}/music').createSync();
    embeddedCalls = 0;
    embedded = {};
    covers = Covers(
      cacheDir: Directory('${dir.path}/cache'),
      embedded: (p) async {
        embeddedCalls++;
        return embedded[p];
      },
    );
  });
  tearDown(() => dir.deleteSync(recursive: true));

  int red(File f) =>
      img.decodeJpg(f.readAsBytesSync())!.getPixel(10, 10).r.toInt();

  test(
    'image intégrée prioritaire sur cover.jpg, réduite à la taille demandée',
    () async {
      final track = '${dir.path}/music/a.flac';
      embedded[track] = png(250);
      File('${dir.path}/music/cover.jpg')
          .writeAsBytesSync(img.encodeJpg(img.Image(width: 10, height: 10)));
      final f = await covers.get(track, 300);
      expect(img.decodeJpg(f!.readAsBytesSync())!.width, 300);
      expect(red(f), greaterThan(200));
    },
  );

  test('sans image intégrée : folder.jpg du dossier', () async {
    File('${dir.path}/music/folder.jpg').writeAsBytesSync(
      img.encodeJpg(
        img.Image(width: 900, height: 900)..clear(img.ColorRgb8(0, 0, 0)),
      ),
    );
    final f = await covers.get('${dir.path}/music/b.flac', 64);
    expect(f, isNotNull);
    expect(red(f!), lessThan(30));
  });

  test('rien : null', () async {
    expect(await covers.get('${dir.path}/music/c.flac', 64), isNull);
  });

  test('deuxième appel servi par le cache', () async {
    final track = '${dir.path}/music/a.flac';
    embedded[track] = png(250);
    await covers.get(track, 300);
    await covers.get(track, 300);
    expect(embeddedCalls, 1);
  });

  test(
    'sans pochette : le résultat est retenu (pas de relecture à chaque image)',
    () async {
      final track = '${dir.path}/music/c.flac';
      await covers.get(track, 64);
      await covers.get(track, 64);
      await Future.wait([covers.get(track, 64), covers.get(track, 64)]);
      expect(embeddedCalls, 1);
    },
  );

  test('forget : la pochette est relue (après une modification)', () async {
    final track = '${dir.path}/music/a.flac';
    await covers.get(track, 64);
    covers.forget(track);
    embedded[track] = png(250);
    expect(await covers.get(track, 64), isNotNull);
  });

  testWidgets('forget retire aussi l’image affichée du cache de Flutter', (
    tester,
  ) async {
    embedded['/m/a.flac'] = png(200);
    final f = (await tester.runAsync(() => covers.get('/m/a.flac', 64)))!;
    final key = FileImage(f);
    final stream = key.resolve(ImageConfiguration.empty);
    stream.addListener(ImageStreamListener((_, _) {}));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    expect(PaintingBinding.instance.imageCache.containsKey(key), isTrue);
    covers.forget('/m/a.flac');
    expect(PaintingBinding.instance.imageCache.containsKey(key), isFalse);
  });
}
