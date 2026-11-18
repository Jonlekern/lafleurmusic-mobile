import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_taglib/flutter_taglib.dart';
import 'package:path/path.dart' as p;

import '../library/db.dart';
import '../library/models.dart';

/// Une modification d'un fichier ; null = champ inchangé.
class TagEdit {
  const TagEdit({
    required this.path,
    this.title,
    this.artist,
    this.album,
    this.trackNo,
    this.cover,
    this.pictures,
  });
  final String path;
  final String? title, artist, album;
  final int? trackNo;
  final Uint8List? cover; // nouvelle pochette (vide = retirer)
  final List<Picture>?
  pictures; // toutes les images d'avant, telles quelles (annulation)
  bool get touchesPictures => cover != null || pictures != null;
}

class WriteResult {
  const WriteResult(this.ok, [this.failedPath]);
  final bool ok;
  final String? failedPath;
}

/// Accès aux fichiers (TagLib en vrai, faux dans les tests).
abstract interface class TagFileIO {
  /// État actuel du fichier (tous les champs remplis), null s'il ne s'ouvre pas.
  Future<TagEdit?> snapshot(TagEdit edit);
  Future<bool> write(TagEdit edit);
}

class TagLibIO implements TagFileIO {
  @override
  Future<TagEdit?> snapshot(TagEdit edit) => Isolate.run(() {
    final f = TagLibFile.open(edit.path);
    if (f == null) return null;
    try {
      // seulement ce que l'écriture va toucher : annuler un titre ne réécrit pas les images
      return TagEdit(
        path: edit.path,
        title: edit.title == null ? null : f.title,
        artist: edit.artist == null ? null : f.artist,
        album: edit.album == null ? null : f.album,
        trackNo: edit.trackNo == null ? null : f.track,
        pictures: edit.touchesPictures ? f.pictures : null,
      );
    } finally {
      f.close();
    }
  });

  @override
  Future<bool> write(TagEdit e) => Isolate.run(() {
    final f = TagLibFile.open(e.path);
    if (f == null) return false;
    try {
      if (e.title != null) f.title = e.title!;
      if (e.artist != null) f.artist = e.artist!;
      if (e.album != null) f.album = e.album!;
      if (e.trackNo != null) f.track = e.trackNo!;
      if (e.pictures != null) {
        if (!f.setPictures(e.pictures!)) return false;
      } else if (e.cover != null && !f.setCover(data: e.cover)) {
        return false;
      }
      return f.save();
    } finally {
      f.close();
    }
  });
}

/// La seule pièce qui écrit dans les fichiers : écrit, met la bibliothèque à jour, garde de quoi annuler.
/// Si un fichier refuse, ceux déjà écrits dans ce lot sont remis comme avant.
class TagWriter {
  TagWriter(this.db, [TagFileIO? io, this.onCoverChanged])
    : io = io ?? TagLibIO();
  final void Function(String path)? onCoverChanged;
  final LibraryDb db;
  final TagFileIO io;
  final _undo = <List<TagEdit>>[];
  static const undoLimit = 20;

  Future<WriteResult> apply(List<TagEdit> edits, {bool record = true}) async {
    final before = <TagEdit>[];
    for (final e in edits) {
      final snap = await io.snapshot(e);
      if (snap == null || !await io.write(e)) {
        for (final b in before.reversed) {
          await io.write(b);
        }
        return WriteResult(false, e.path);
      }
      before.add(snap);
    }
    for (final e in edits) {
      // avant la mise à jour de la base, qui redessine
      if (e.touchesPictures) onCoverChanged?.call(e.path);
      await _refresh(e);
    }
    if (record && before.isNotEmpty) {
      _undo.add(before);
      if (_undo.length > undoLimit) _undo.removeAt(0);
    }
    return const WriteResult(true);
  }

  /// Annule le dernier lot (Cmd / Ctrl + Z) ; false s'il n'y a rien à annuler.
  Future<bool> undo() async {
    if (_undo.isEmpty) return false;
    final last = _undo.removeLast();
    return (await apply(last, record: false)).ok;
  }

  Future<void> _refresh(TagEdit e) async {
    final old = await db.trackByPath(e.path);
    if (old == null) return;
    var mtime = old.mtime, size = old.size;
    final f = File(e.path);
    if (f.existsSync()) {
      final st = f.statSync();
      mtime = st.modified.millisecondsSinceEpoch;
      size = st.size;
    }
    await db.upsertTrack(
      Track(
        path: old.path,
        folderId: old.folderId,
        // comme le scan : titre vide = nom du fichier, numéro 0 = pas de numéro
        title: e.title == null
            ? old.title
            : (e.title!.trim().isEmpty
                  ? p.basenameWithoutExtension(e.path)
                  : e.title!.trim()),
        artist: e.artist ?? old.artist,
        album: e.album ?? old.album,
        genre: old.genre,
        trackNo: e.trackNo == null
            ? old.trackNo
            : (e.trackNo! > 0 ? e.trackNo : null),
        durationMs: old.durationMs,
        hasCover: e.pictures != null
            ? e.pictures!.isNotEmpty
            : (e.cover != null ? e.cover!.isNotEmpty : old.hasCover),
        mtime: mtime,
        size: size,
      ),
    );
  }
}
