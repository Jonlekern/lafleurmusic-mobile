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

  group('pochettes du serveur (subsonic://)', () {
    late int downloads;
    late Covers server;
    late Uint8List? served;
    setUp(() {
      downloads = 0;
      served = png(250);
      server = Covers(
        cacheDir: Directory('${dir.path}/cache'),
        embedded: (p) async {
          embeddedCalls++;
          return null;
        },
        remote: (path, size) async {
          downloads++;
          await Future<void>.delayed(const Duration(milliseconds: 5));
          return served;
        },
      );
    });

    test('deux appels → un seul téléchargement, fichier en cache', () async {
      final both = await Future.wait([
        server.get('subsonic://acc1/s9', 300),
        server.get('subsonic://acc1/s9', 300),
      ]);
      expect(downloads, 1);
      expect(embeddedCalls, 0); // jamais TagLib sur une clé de serveur
      final f = both.first!;
      expect(f.existsSync(), isTrue);
      expect(f.parent.path, '${dir.path}/cache');
      expect(img.decodeJpg(f.readAsBytesSync())!.width, 300);
      expect(red(f), greaterThan(200));
      // relancement de l'appli : servi par le disque, sans réseau
      final again = Covers(
        cacheDir: Directory('${dir.path}/cache'),
        remote: (_, _) async => fail('downloaded again'),
      );
      expect((await again.get('subsonic://acc1/s9', 300))!.path, f.path);
    });

    test('pas de pochette sur le serveur → null', () async {
      served = null;
      expect(await server.get('subsonic://acc1/s9', 64), isNull);
    });

    test('réseau coupé → null pendant 1 min (pas un essai par image), puis redemandé', () async {
      var fail = true, fetches = 0;
      var now = DateTime(2026);
      final flaky = Covers(
        cacheDir: Directory('${dir.path}/cache'),
        clock: () => now,
        remote: (_, _) async {
          fetches++;
          if (fail) throw Exception('offline');
          return png(10);
        },
      );
      expect(await flaky.get('subsonic://acc1/s9', 64), isNull);
      fail = false;
      now = now.add(const Duration(seconds: 30));
      expect(await flaky.get('subsonic://acc1/s9', 64), isNull);
      expect(fetches, 1);
      now = now.add(const Duration(seconds: 31));
      expect(await flaky.get('subsonic://acc1/s9', 64), isNotNull);
      expect(fetches, 2);
    });

    test('pochettes par album (remoteKey) : un seul téléchargement pour tout l’album', () async {
      var fetches = 0;
      Covers make() => Covers(
        cacheDir: Directory('${dir.path}/cache'),
        remoteKey: (path) async => path.endsWith('x') ? null : 'acc1/al-1',
        remote: (_, _) async {
          fetches++;
          await Future<void>.delayed(const Duration(milliseconds: 5));
          return png(250);
        },
      );
      final album = make();
      final files = await Future.wait([
        for (final s in ['s1', 's2', 's3'])
          album.get('subsonic://acc1/$s', 300),
      ]);
      expect(fetches, 1);
      expect(files.map((f) => f!.path).toSet(), hasLength(1));
      // plus tard, un autre morceau du même album : déjà sur le disque
      expect(await album.get('subsonic://acc1/s4', 300), isNotNull);
      expect(await make().get('subsonic://acc1/s5', 300), isNotNull);
      expect(fetches, 1);
      // pas de pochette sur le serveur : rien téléchargé
      expect(await album.get('subsonic://acc1/x', 300), isNull);
      expect(fetches, 1);
    });

    test('sans fonction remote : pas de pochette', () async {
      expect(await covers.get('subsonic://acc1/s9', 64), isNull);
      expect(embeddedCalls, 0);
    });
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
