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
  LocalFolder({
    required this.db,
    required this.device,
    required this.reader,
    this.inFlight,
  });
  final LibraryDb db;
  final Device device;
  final TagReader reader;

  /// Le fichier que le téléchargeur est en train de ranger (Downloader.targetPath).
  final String? Function()? inFlight;

  Future<bool>? _access; // la permission n'est demandée qu'une fois par lancement

  Future<bool> _ensureAccess() async {
    try {
      return await (_access ??= device.ensureAccess(readOthers: true));
    } on Object {
      _access = null; // demande déjà en cours, plugin absent… : refusé cette fois
      return false;
    }
  }

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
        try {
          await _scan();
        } on Object {
          // dossier illisible, base fermée… : la prochaine relecture réessaie
        }
      } while (_again);
    } finally {
      _running = false;
    }
  }

  Future<void> _scan() async {
    // refus : on ne lit que nos propres fichiers, sans rien dire
    final access = await _ensureAccess();
    final reachable = await device.rootReachable();
    final root = await device.musicRoot();
    if (!await root.exists()) return;

    // nos copies gardées (et leurs téléchargements en cours) ne sont pas des fichiers posés
    Future<Set<String>> oursNow() async => {
      for (final o in await db.offlineRows())
        if (o.filePath != null) p.join(root.path, o.filePath!),
      ?inFlight?.call(),
    };
    var ours = await oursNow();
    final known = <String, ({String abs, int mtime, int size})>{};
    for (final t in await db.localTracks()) {
      final abs = await device.absolutePath(t.path);
      if (p.isWithin(root.path, abs)) {
        known[t.path] = (abs: abs, mtime: t.mtime, size: t.size);
      }
    }

    final seen = <String>{};
    final batch = <(Track, String)>[]; // morceau, chemin absolu
    Future<void> flush() async {
      // un fichier rangé par le téléchargeur pendant la lecture n'est pas posé à la main
      ours = await oursNow();
      final keep = [
        for (final (t, abs) in batch)
          if (!ours.contains(abs)) t,
      ];
      batch.clear();
      if (keep.isNotEmpty) await db.upsertTracks(keep);
    }

    for (final f in await Scanner.listMusic(root)) {
      if (ours.contains(f.path)) continue;
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
        batch.add((Scanner.build(0, key, tags, mtime, st.size), f.path));
      } on FileSystemException {
        // disparu pendant la lecture
      }
      if (batch.length >= 200) await flush();
    }
    if (batch.isNotEmpty) await flush();

    // un doublon déjà là (copie rangée pendant une lecture d'avant) : il rend ses écoutes au morceau du serveur
    final done = {
      for (final o in await db.offlineRows())
        if (o.state == OfflineState.done.name && o.filePath != null)
          p.join(root.path, o.filePath!): o.trackPath,
    };
    // (relu : un doublon d'un lot précédent de ce même tour compte aussi)
    final dupeTo = <String, String>{}; // clé du doublon → morceau du serveur
    for (final t in await db.localTracks()) {
      final server = done[await device.absolutePath(t.path)];
      if (server != null) dupeTo[t.path] = server;
    }
    final dupes = dupeTo.keys.toList();
    for (final e in dupeTo.entries) {
      await db.movePlays(e.key, e.value);
    }
    if (dupes.isNotEmpty) await db.deletePaths(dupes);
    known.removeWhere((k, _) => dupes.contains(k));

    // un dossier qui ne répond plus ou des droits refusés ne retirent jamais rien
    if (!reachable || !access) return;
    final gone = [
      for (final e in known.entries)
        if (!seen.contains(e.key) && !File(e.value.abs).existsSync()) e.key,
    ];
    if (gone.isNotEmpty) await db.deletePaths(gone);
  }
}
