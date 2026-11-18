import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/library/db.dart';
import 'package:lafleurmusic/library/scanner.dart';
import 'package:lafleurmusic/tags/tag_reader.dart';

class FakeReader implements TagReader {
  final calls = <String>[];
  final throwing = <String>{};
  final Map<String, TrackTags?> tags = {};
  @override
  Future<TrackTags?> read(String path) async {
    calls.add(path);
    if (throwing.contains(path)) {
      throw const FileSystemException('lecture impossible');
    }
    return tags.containsKey(path)
        ? tags[path]
        : const TrackTags(
            title: 'T',
            artist: 'A',
            album: 'Alb',
            trackNo: 1,
            durationMs: 3000,
            hasCover: true,
          );
  }
}

void main() {
  late Directory dir;
  late LibraryDb db;
  late FakeReader reader;
  late Scanner scanner;
  late MusicFolder folder;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('lafleur');
    db = LibraryDb(NativeDatabase.memory());
    reader = FakeReader();
    scanner = Scanner(db, reader);
    folder = MusicFolder(id: 1, path: dir.path);
  });
  tearDown(() async {
    await db.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  File touch(String rel) => File('${dir.path}/$rel')
    ..createSync(recursive: true)
    ..writeAsStringSync('x');

  Future<List<String>> paths() async => [
    for (final a in await db.watchAlbums().first)
      ...(await db.watchAlbumTracks(a.name).first).map((t) => t.path),
  ];

  test('seulement les extensions de musique, sans ._ ni .DS_Store', () async {
    for (final n in [
      'a.flac',
      'b.MP3',
      'c.ape',
      'd.wv',
      'e.dsf',
      'f.tak',
      'g.txt',
      'cover.jpg',
      '._a.flac',
      '.DS_Store',
      'sous/h.opus',
    ]) {
      touch(n);
    }
    await scanner.scan(folder).drain<void>();
    final got = (await paths()).map((p) => p.split('/').last).toSet();
    expect(got, {
      'a.flac',
      'b.MP3',
      'c.ape',
      'd.wv',
      'e.dsf',
      'f.tak',
      'h.opus',
    });
  });

  test('second scan sans changement : aucun fichier relu', () async {
    touch('a.flac');
    await scanner.scan(folder).drain<void>();
    reader.calls.clear();
    await scanner.scan(folder).drain<void>();
    expect(reader.calls, isEmpty);
  });

  test('fichier modifié relu, fichier supprimé retiré', () async {
    final a = touch('a.flac');
    final b = touch('b.flac');
    await scanner.scan(folder).drain<void>();
    reader.calls.clear();
    a.writeAsStringSync('plus long');
    b.deleteSync();
    await scanner.scan(folder).drain<void>();
    expect(reader.calls.map((p) => p.split('/').last), ['a.flac']);
    expect((await paths()).map((p) => p.split('/').last), ['a.flac']);
  });

  test('tags vides : titre = nom du fichier, artiste vide', () async {
    final f = touch('01 Ocean Drive.flac');
    reader.tags[f.path] = null;
    await scanner.scan(folder).drain<void>();
    final t = (await db.search('ocean')).single;
    expect(t.title, '01 Ocean Drive');
    expect(t.artist, '');
  });

  test('dossier introuvable : pistes gardées et marquées absentes', () async {
    touch('a.flac');
    await scanner.scan(folder).drain<void>();
    dir.deleteSync(recursive: true);
    await scanner.scan(folder).drain<void>();
    final t = (await db.search('t')).single;
    expect(t.missing, true);
  });

  test('accents et emoji conservés', () async {
    touch('Été 🌸/Ça va.flac');
    await scanner.scan(folder).drain<void>();
    expect((await paths()).single, endsWith('Été 🌸/Ça va.flac'));
  });

  test('la progression arrive avant la fin', () async {
    for (var i = 0; i < 450; i++) {
      touch('m$i.flac');
    }
    final events = await scanner.scan(folder).toList();
    expect(events.first.done, lessThan(events.first.total));
    expect(events.last.done, 450);
  });

  test('un fichier qui plante n’arrête pas le scan', () async {
    final bad = touch('a.flac');
    touch('b.flac');
    reader.throwing.add(bad.path);
    await scanner.scan(folder).drain<void>();
    expect((await paths()).map((p) => p.split('/').last), contains('b.flac'));
  });

  test('un sous-dossier illisible est sauté', () async {
    touch('ok/a.flac');
    touch('prive/b.flac');
    final locked = Directory('${dir.path}/prive');
    Process.runSync('chmod', ['000', locked.path]);
    addTearDown(() => Process.runSync('chmod', ['755', locked.path]));
    await scanner.scan(folder).drain<void>();
    expect((await paths()).map((p) => p.split('/').last), contains('a.flac'));
  });

  test(
    'point de montage vide (NAS remonté ailleurs) : rien n’est effacé',
    () async {
      touch('a.flac');
      touch('b.flac');
      await scanner.scan(folder).drain<void>();
      for (final f in dir.listSync()) {
        f.deleteSync(recursive: true);
      }
      await scanner.scan(folder).drain<void>();
      final all = await db.search('t');
      expect(all.length, 2);
      expect(all.every((t) => t.missing), isTrue);
    },
  );

  test('le NAS revient : morceaux de nouveau jouables', () async {
    touch('a.flac');
    await scanner.scan(folder).drain<void>();
    final moved = Directory('${dir.path}-off');
    dir.renameSync(moved.path);
    await scanner.scan(folder).drain<void>();
    expect((await db.search('t')).single.missing, isTrue);
    moved.renameSync(dir.path);
    await scanner.scan(folder).drain<void>();
    expect((await db.search('t')).single.missing, isFalse);
  });

  test('progression annoncée dès la liste des fichiers faite', () async {
    for (var i = 0; i < 3; i++) {
      touch('m$i.flac');
    }
    int? readsAtFirstEvent;
    ScanProgress? first;
    await for (final e in scanner.scan(folder)) {
      first ??= e;
      readsAtFirstEvent ??= reader.calls.length;
    }
    expect(first!.total, 3);
    expect(first.done, 0);
    expect(readsAtFirstEvent, 0);
  });
}
