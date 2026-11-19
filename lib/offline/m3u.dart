import 'dart:io';

import 'package:path/path.dart' as p;

import '../library/db.dart';
import 'device.dart';
import 'keep_origin.dart';
import 'paths.dart';

/// Une ligne d'un `.m3u8` : durée, artiste, titre, chemin relatif au fichier.
class M3uEntry {
  const M3uEntry({
    required this.seconds,
    required this.artist,
    required this.title,
    required this.path,
  });
  final int seconds;
  final String artist, title, path;
}

/// Un saut de ligne dans un titre couperait la ligne en deux.
String _oneLine(String s) => s.replaceAll(RegExp(r'[\r\n]+'), ' ');

/// `#EXTM3U`, puis `#EXTINF:<secondes>,<artiste> - <titre>` et le chemin de chaque morceau.
String buildM3u8(List<M3uEntry> entries) {
  final b = StringBuffer('#EXTM3U\n');
  for (final e in entries) {
    b
      ..write('#EXTINF:${e.seconds},')
      ..write(_oneLine('${e.artist} - ${e.title}'))
      ..write('\n')
      ..write(_oneLine(e.path))
      ..write('\n');
  }
  return b.toString();
}

/// Les `.m3u8` des playlists gardées, sous `<racine>/Playlists/` (règle Q3) : l'appli n'écrit
/// et n'efface que les fichiers notés dans `KeptPlaylists`. Un fichier donne l'ordre de la
/// playlist avec les seuls morceaux qui ont une copie finie (la leur ou celle d'un jumeau).
class PlaylistFiles {
  PlaylistFiles(this.db, this.device);
  final LibraryDb db;
  final Device device;

  static const folder = 'Playlists';

  Future<void> _lock = Future.value();

  /// Un à la fois (une copie qui arrive pendant un « Retirer »).
  Future<T> _serial<T>(Future<T> Function() f) {
    final run = _lock.then((_) => f());
    _lock = run.then((_) {}, onError: (Object _) {});
    return run;
  }

  /// Réécrit chaque fichier dont le contenu a changé ; retire le fichier (et la playlist
  /// gardée) quand plus aucun de ses morceaux n'a de ligne hors ligne (même en échec), ou
  /// quand le serveur ne l'a plus (règle Q10). Dossier injoignable : rien.
  Future<void> refresh() => _serial(_refresh);

  Future<void> _refresh() async {
    final kept = await db.keptPlaylistRows();
    if (kept.isEmpty) return;
    if (!await device.rootReachable()) return;
    final root = await device.musicRoot();
    final dir = Directory(p.join(root.path, folder));
    // les noms déjà pris par nos fichiers (minuscules : iOS et Android ignorent la casse)
    final ours = {
      for (final k in kept)
        if (k.fileName.isNotEmpty) k.fileName.toLowerCase(),
    };
    for (final k in kept) {
      final name = await db.playlistName(k.accountId, k.playlistId);
      if (name == null) {
        // plus sur le serveur, ou compte retiré : notre fichier part, ses morceaux restent (Q10)
        await _delete(root, k.fileName);
        ours.remove(k.fileName.toLowerCase());
        await db.dropKeptPlaylist(k.accountId, k.playlistId);
        // ses morceaux restent gardés, pour eux-mêmes (règle Q15)
        await db.renameOrigin(
          KeepOrigin.playlist(k.accountId, k.playlistId),
          KeepOrigin.song,
        );
        continue;
      }
      final paths = await db.playlistPaths(k.accountId, k.playlistId);
      if (!await db.anyKept(paths)) {
        await _delete(root, k.fileName);
        await db.dropKeptPlaylist(k.accountId, k.playlistId);
        // plus gardée : sa raison ne retient plus rien (un album retiré plus tard)
        await db.dropOrigin(KeepOrigin.playlist(k.accountId, k.playlistId));
        continue;
      }
      final copies = await db.doneCopies(paths);
      final entries = <M3uEntry>[];
      for (final path in paths) {
        final c = copies[path];
        final rel = c?.filePath;
        if (rel == null) continue;
        if (!fileOrPlaceholderExists(p.join(root.path, rel))) continue;
        final t = await db.trackByPath(path);
        if (t == null) continue;
        entries.add(
          M3uEntry(
            seconds: (t.durationMs / 1000).round(),
            artist: t.artist,
            title: t.title,
            path: '../$rel',
          ),
        );
      }
      if (entries.isEmpty) {
        // en attente des copies : pas de fichier, la playlist reste gardée
        if (k.fileName.isNotEmpty) {
          await _delete(root, k.fileName);
          ours.remove(k.fileName.toLowerCase());
          await db.setKeptPlaylist(k.accountId, k.playlistId, '');
        }
        continue;
      }
      var fileName = k.fileName;
      if (fileName.isEmpty) {
        fileName = uniquePath(
          '${safeName(name)}.m3u8',
          (c) =>
              ours.contains(c.toLowerCase()) ||
              fileOrPlaceholderExists(p.join(dir.path, c)) ||
              File(partialPath(p.join(dir.path, c))).existsSync(),
        );
        ours.add(fileName.toLowerCase());
      }
      final file = File(p.join(dir.path, fileName));
      final text = buildM3u8(entries);
      final same = file.existsSync() && await file.readAsString() == text;
      if (!same) {
        // écrit à côté puis renommé : jamais un fichier à moitié écrit
        await dir.create(recursive: true);
        final part = File(partialPath(file.path));
        try {
          await part.writeAsString(text, flush: true);
          await part.rename(file.path);
        } catch (_) {
          try {
            if (part.existsSync()) part.deleteSync();
          } catch (_) {}
          rethrow;
        }
        await _announce(file.path);
      }
      if (fileName != k.fileName) {
        await db.setKeptPlaylist(k.accountId, k.playlistId, fileName);
      }
    }
  }

  /// La playlist n'est plus gardée : son fichier (le nôtre) et sa note partent.
  Future<void> remove(String accountId, String playlistId) => _serial(() async {
    final k = [
      for (final r in await db.keptPlaylistRows())
        if (r.accountId == accountId && r.playlistId == playlistId) r,
    ];
    if (k.isEmpty) return;
    if (await device.rootReachable()) {
      await _delete(await device.musicRoot(), k.single.fileName);
    }
    await db.dropKeptPlaylist(accountId, playlistId);
  });

  /// Les copies quittent [from] (changement de dossier) : nos fichiers y sont effacés et
  /// seront réécrits dans le nouveau dossier au prochain [refresh].
  Future<void> leave(Directory from) => _serial(() async {
    for (final k in await db.keptPlaylistRows()) {
      if (k.fileName.isEmpty) continue;
      await _delete(from, k.fileName);
      await db.setKeptPlaylist(k.accountId, k.playlistId, '');
    }
  });

  /// L'ancien dossier ne répond plus : ses fichiers restent où ils sont, plus à nous.
  Future<void> forgetFiles() => _serial(() async {
    for (final k in await db.keptPlaylistRows()) {
      if (k.fileName.isNotEmpty) {
        await db.setKeptPlaylist(k.accountId, k.playlistId, '');
      }
    }
  });

  /// Efface `<root>/Playlists/<fileName>` (le nôtre), jamais ailleurs ; le dossier s'il est vide.
  Future<void> _delete(Directory root, String fileName) async {
    if (fileName.isEmpty) return;
    final dir = p.normalize(p.join(root.path, folder));
    final full = p.normalize(p.join(dir, fileName));
    if (!p.isWithin(dir, full) || p.extension(full).toLowerCase() != '.m3u8') {
      return;
    }
    try {
      final f = File(full);
      if (await f.exists()) {
        await f.delete();
        await _announce(full);
      }
      final d = Directory(dir);
      if (d.existsSync() && d.listSync().isEmpty) d.deleteSync();
    } catch (_) {} // un fichier qui ne part pas n'arrête rien
  }

  Future<void> _announce(String path) async {
    try {
      await device.announce(path);
    } catch (_) {} // la médiathèque du système n'est pas vitale
  }
}
