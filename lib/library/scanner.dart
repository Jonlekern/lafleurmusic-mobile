import 'dart:io';

import 'package:path/path.dart' as p;

import '../tags/tag_reader.dart';
import 'db.dart';
import 'models.dart';

/// Un dossier de musique à scanner.
class MusicFolder {
  const MusicFolder({required this.id, required this.path});
  final int id;
  final String path;
}

const musicExtensions = {
  'flac',
  'mp3',
  'm4a',
  'aac',
  'alac',
  'opus',
  'ogg',
  'oga',
  'wav',
  'aiff',
  'aif',
  'ape',
  'wv',
  'tta',
  'tak',
  'mpc',
  'dsf',
};

class ScanProgress {
  const ScanProgress(this.done, this.total);
  final int done;
  final int total;
}

/// Scan incrémental : seuls les fichiers nouveaux ou modifiés (date ou taille) sont relus.
class Scanner {
  Scanner(this.db, this.reader, {this.batchSize = 200});
  final LibraryDb db;
  final TagReader reader;
  final int batchSize;

  static bool isMusic(String path) {
    final name = p.basename(path);
    if (name.startsWith('.')) return false;
    final ext = p.extension(name).toLowerCase().replaceFirst('.', '');
    return musicExtensions.contains(ext);
  }

  /// Liste récursive qui saute les sous-dossiers illisibles au lieu de tout arrêter.
  static Future<List<File>> listMusic(Directory dir) async {
    final out = <File>[];
    final pending = [dir];
    while (pending.isNotEmpty) {
      final d = pending.removeLast();
      try {
        await for (final e in d.list(followLinks: false)) {
          if (e is Directory) {
            pending.add(e);
          } else if (e is File && isMusic(e.path)) {
            out.add(e);
          }
        }
      } on FileSystemException {
        // dossier protégé (#recycle, droits…) : on continue avec les autres
      }
    }
    return out;
  }

  Stream<ScanProgress> scan(MusicFolder folder) async* {
    final dir = Directory(folder.path);
    final known = {for (final t in await db.folderTracks(folder.id)) t.path: t};
    final files = await dir.exists() ? await listMusic(dir) : <File>[];
    // Dossier absent, ou vide alors qu'on y connaissait des morceaux (NAS démonté, point de montage resté vide) :
    // on garde tout, grisé, plutôt que d'effacer la bibliothèque.
    if (files.isEmpty && (known.isNotEmpty || !await dir.exists())) {
      await db.markMissing(folder.id, true);
      yield const ScanProgress(0, 0);
      return;
    }
    yield ScanProgress(0, files.length);
    final seen = <String>{};
    final batch = <Track>[];
    var done = 0;
    for (final f in files) {
      seen.add(f.path);
      try {
        final st = await f.stat();
        final mtime = st.modified.millisecondsSinceEpoch;
        final old = known[f.path];
        if (old != null && old.mtime == mtime && old.size == st.size) {
          if (old.missing) batch.add(_copy(old, missing: false));
        } else {
          TrackTags? tags;
          try {
            tags = await reader.read(f.path);
          } on Object {
            tags = null; // fichier illisible pour TagLib : on le garde avec son nom
          }
          batch.add(build(folder.id, f.path, tags, mtime, st.size));
        }
      } on FileSystemException {
        // fichier disparu pendant le scan
      }
      done++;
      if (done % batchSize == 0) {
        await db.upsertTracks(List.of(batch));
        batch.clear();
        yield ScanProgress(done, files.length);
      }
    }
    if (batch.isNotEmpty) await db.upsertTracks(batch);
    final gone = known.keys.where((k) => !seen.contains(k)).toList();
    if (gone.isNotEmpty) await db.deletePaths(gone);
    yield ScanProgress(files.length, files.length);
  }

  /// Une ligne de bibliothèque à partir des tags lus (null : le nom du fichier sert de titre).
  static Track build(
    int folderId,
    String path,
    TrackTags? t,
    int mtime,
    int size,
  ) {
    final title = (t?.title.trim().isNotEmpty ?? false)
        ? t!.title.trim()
        : p.basenameWithoutExtension(path);
    return Track(
      path: path,
      folderId: folderId,
      title: title,
      artist: t?.artist.trim() ?? '',
      album: t?.album.trim() ?? '',
      genre: t?.genre.trim() ?? '',
      trackNo: t?.trackNo,
      durationMs: t?.durationMs ?? 0,
      hasCover: t?.hasCover ?? false,
      mtime: mtime,
      size: size,
    );
  }

  static Track _copy(Track t, {required bool missing}) => Track(
    path: t.path,
    folderId: t.folderId,
    title: t.title,
    artist: t.artist,
    album: t.album,
    trackNo: t.trackNo,
    durationMs: t.durationMs,
    hasCover: t.hasCover,
    mtime: t.mtime,
    size: t.size,
    missing: missing,
  );
}
