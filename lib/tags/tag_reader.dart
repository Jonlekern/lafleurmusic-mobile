import 'dart:isolate';

import 'package:flutter_taglib/flutter_taglib.dart';

/// Les infos d'un fichier utiles à la bibliothèque.
class TrackTags {
  const TrackTags({
    required this.title,
    required this.artist,
    required this.album,
    this.genre = '',
    this.trackNo,
    required this.durationMs,
    required this.hasCover,
  });
  final String title;
  final String artist;
  final String album;
  final String genre;
  final int? trackNo;
  final int durationMs;
  final bool hasCover;
}

abstract interface class TagReader {
  /// null si le fichier n'a pas pu être ouvert.
  Future<TrackTags?> read(String path);
}

/// Lecture avec TagLib, dans un isolate pour ne pas bloquer l'interface.
class TagLibReader implements TagReader {
  @override
  Future<TrackTags?> read(String path) => Isolate.run(() => _read(path));

  static TrackTags? _read(String path) {
    final f = TagLibFile.open(path);
    if (f == null) return null;
    try {
      return TrackTags(
        title: f.title,
        artist: f.artist,
        album: f.album,
        genre: f.genre,
        trackNo: f.track > 0 ? f.track : null,
        durationMs: f.duration.inMilliseconds,
        hasCover: f.hasCover,
      );
    } finally {
      f.close();
    }
  }
}
