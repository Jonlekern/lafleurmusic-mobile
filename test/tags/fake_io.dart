import 'package:flutter_taglib/flutter_taglib.dart' show Picture;
import 'package:lafleurmusic/tags/tag_writer.dart';

/// Faux fichiers : un dictionnaire chemin → tags et images intégrées ; certains chemins refusent l'écriture.
class FakeIO implements TagFileIO {
  final files = <String, TagEdit>{};
  final pictures = <String, List<Picture>>{};
  final readOnly = <String>{};
  var pictureWrites = 0;

  @override
  Future<TagEdit?> snapshot(TagEdit e) async {
    final f = files[e.path];
    if (f == null) return null;
    return TagEdit(
      path: e.path,
      title: e.title == null ? null : f.title ?? '',
      artist: e.artist == null ? null : f.artist ?? '',
      album: e.album == null ? null : f.album ?? '',
      trackNo: e.trackNo == null ? null : f.trackNo ?? 0,
      pictures: e.touchesPictures
          ? List.of(pictures[e.path] ?? const [])
          : null,
    );
  }

  @override
  Future<bool> write(TagEdit e) async {
    if (readOnly.contains(e.path)) return false;
    final old = files[e.path]!;
    files[e.path] = TagEdit(
      path: e.path,
      title: e.title ?? old.title,
      artist: e.artist ?? old.artist,
      album: e.album ?? old.album,
      trackNo: e.trackNo ?? old.trackNo,
    );
    if (e.pictures != null) {
      pictures[e.path] = List.of(e.pictures!);
      pictureWrites++;
    } else if (e.cover != null) {
      pictures[e.path] = e.cover!.isEmpty
          ? []
          : [Picture(bytes: e.cover!, mimeType: 'image/jpeg')];
      pictureWrites++;
    }
    return true;
  }
}
