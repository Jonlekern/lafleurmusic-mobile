import 'dart:io';

import 'package:path/path.dart' as p;

import '../library/db.dart';
import '../library/models.dart';
import '../library/scanner.dart';
import '../tags/tag_reader.dart';
import 'device.dart';

/// Les fichiers posés à la main dans LAFLEURMUSIC/ deviennent des morceaux `local`.
/// Lecture seule : un fichier posé n'est jamais écrit, renommé ni effacé.
class LocalFolder {
  LocalFolder({required this.db, required this.device, required this.reader});
  final LibraryDb db;
  final Device device;
  final TagReader reader;

  bool _running = false, _again = false;

  /// Relit le dossier ; un appel pendant une lecture en demande une deuxième à la suite.
  Future<void> rescan() async {
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    try {
      do {
        _again = false;
        await _scan();
      } while (_again);
    } finally {
      _running = false;
    }
  }

  Future<void> _scan() async {
    // refus : on ne lit que nos propres fichiers, sans rien dire
    final access = await device.ensureAccess(readOthers: true);
    final reachable = await device.rootReachable();
    final root = await device.musicRoot();
    if (!await root.exists()) return;

    // nos copies gardées (et leurs téléchargements en cours) ne sont pas des fichiers posés
    final ours = <String>{
      for (final o in await db.offlineRows())
        if (o.filePath != null) p.join(root.path, o.filePath!),
    };
    final known = <String, ({String abs, int mtime, int size})>{};
    for (final t in await db.localTracks()) {
      final abs = await device.absolutePath(t.path);
      if (p.isWithin(root.path, abs)) {
        known[t.path] = (abs: abs, mtime: t.mtime, size: t.size);
      }
    }

    final seen = <String>{};
    final batch = <Track>[];
    for (final f in await Scanner.listMusic(root)) {
      if (f.path.endsWith('.lafleur.part') || ours.contains(f.path)) continue;
      final key = await device.keyFor(f.path);
      seen.add(key);
      try {
        final st = await f.stat();
        final mtime = st.modified.millisecondsSinceEpoch;
        final old = known[key];
        if (old != null && old.mtime == mtime && old.size == st.size) continue;
        TrackTags? tags;
        try {
          tags = await reader.read(f.path);
        } on Object {
          tags = null; // illisible pour TagLib : on le garde avec son nom
        }
        batch.add(Scanner.build(0, key, tags, mtime, st.size));
      } on FileSystemException {
        // disparu pendant la lecture
      }
      if (batch.length >= 200) {
        await db.upsertTracks(List.of(batch));
        batch.clear();
      }
    }
    if (batch.isNotEmpty) await db.upsertTracks(batch);

    // un dossier qui ne répond plus ou des droits refusés ne retirent jamais rien
    if (!reachable || !access) return;
    final gone = [
      for (final e in known.entries)
        if (!seen.contains(e.key) && !File(e.value.abs).existsSync()) e.key,
    ];
    if (gone.isNotEmpty) await db.deletePaths(gone);
  }
}
