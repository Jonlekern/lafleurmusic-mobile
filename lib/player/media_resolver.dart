import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:mpv_audio_kit/mpv_audio_kit.dart' hide Track;
import 'package:path/path.dart' as p;

import '../library/db.dart';
import '../library/models.dart';
import '../sources/source.dart';

const _scheme = 'subsonic://';

/// `subsonic://acc/song` → (acc, song) ; null for a local file.
(String, String)? parseRemoteKey(String path) {
  if (!path.startsWith(_scheme)) return null;
  final rest = path.substring(_scheme.length);
  final slash = rest.indexOf('/');
  if (slash <= 0 || slash == rest.length - 1) return null;
  return (rest.substring(0, slash), rest.substring(slash + 1));
}

/// Absolute path of the finished copy of server track [trackPath], if its file is still there
/// (deleted by hand: null, the stream is used).
Future<String?> Function(String trackPath) keptFile(
  LibraryDb db,
  Future<Directory> Function() musicRoot,
) => (trackPath) async {
  final row = await db.offlineOf(trackPath);
  final rel = row?.filePath;
  if (row == null || rel == null || row.state != OfflineState.done.name) {
    return null;
  }
  final file = p.join((await musicRoot()).path, rel);
  return await File(file).exists() ? file : null;
};

/// Turns a library path into what mpv opens: the file itself, or the server
/// stream with the account headers. Never logs the stream URL (it carries the token).
class MediaResolver {
  MediaResolver(
    this._sourceOf, {
    DateTime Function()? clock,
    this.sourceTimeout = const Duration(seconds: 10),
    this.localCopy,
  }) : _clock = clock ?? DateTime.now;

  /// The kept copy of a server track (see [keptFile]); null: play the stream.
  final Future<String?> Function(String trackPath)? localCopy;

  /// Plays local files only (no account known).
  MediaResolver.localOnly()
    : _sourceOf = ((id) async => throw StateError('No account $id')),
      _clock = DateTime.now,
      sourceTimeout = const Duration(seconds: 10),
      localCopy = null;

  /// A failed account (password missing, database error…) is not asked again before this.
  static const retryAfter = Duration(minutes: 1);

  /// [media] doesn't wait longer than this for an account (a stuck keychain or database).
  final Duration sourceTimeout;

  final Future<MusicSource> Function(String accountId) _sourceOf;
  final DateTime Function() _clock;
  final _sources = <String, Future<MusicSource>>{};
  final _failedAt = <String, DateTime>{};

  /// One source per account, kept until [invalidate] (password or headers changed).
  Future<MusicSource> source(String accountId) {
    final failed = _failedAt[accountId];
    if (failed != null && !_clock().isBefore(failed.add(retryAfter))) {
      invalidate(accountId);
    }
    return _sources.putIfAbsent(accountId, () {
      final f = _sourceOf(accountId);
      f.then<void>(
        (_) {},
        onError: (Object _) {
          if (identical(_sources[accountId], f)) {
            _failedAt[accountId] = _clock();
          }
        },
      );
      return f;
    });
  }

  /// Forgets the account's source and closes its connections.
  void invalidate(String accountId) {
    final old = _sources.remove(accountId);
    _failedAt.remove(accountId);
    old?.then<void>((s) {
      try {
        s.close();
      } catch (_) {} // closing never matters more than forgetting
    }, onError: (Object _) {});
  }

  Future<Media> media(String path) async {
    final key = parseRemoteKey(path);
    if (key == null) return Media(path);
    try {
      final copy = await localCopy?.call(path);
      if (copy != null) return Media(copy); // the file itself: no network, no headers
    } on Object {
      // database or folder unreadable: the stream still works
    }
    final MusicSource s;
    try {
      s = await source(key.$1).timeout(sourceTimeout);
    } on Object {
      // account gone, unusable or too slow: mpv fails on the raw key and the track is skipped like an unreadable file
      return Media(path);
    }
    return Media(
      s.streamUri(key.$2).toString(),
      httpHeaders: s.headers.isEmpty ? null : s.headers,
    );
  }
}

/// Server cover bytes (GET coverUri with the account headers); null if the server has none.
Future<Uint8List?> remoteCover(
  MusicSource s,
  String coverId,
  int size, {
  http.Client? client,
  Duration timeout = requestTimeout,
}) async {
  final c = client ?? (s is HttpSource ? (s as HttpSource).httpClient : null);
  final own = c == null;
  final cl = c ?? newServerClient();
  try {
    final res = await cl
        .get(s.coverUri(coverId, size), headers: s.headers)
        .timeout(timeout);
    final type = (res.headers['content-type'] ?? '').toLowerCase();
    // Subsonic answers "not found" with a 200 and a JSON/XML error (an SVG cover is image/svg+xml: kept)
    if (res.statusCode != 200 ||
        res.bodyBytes.isEmpty ||
        type.contains('json') ||
        type.startsWith('text/xml') ||
        type.startsWith('application/xml')) {
      return null;
    }
    return res.bodyBytes;
  } on Exception catch (e) {
    throw SourceNetworkException(e); // without the URL
  } finally {
    if (own) cl.close();
  }
}

/// `Covers.remote` for library tracks: the cover id comes from the database.
Future<Uint8List?> Function(String trackPath, int size) remoteCovers(
  MediaResolver resolver,
  Future<Track?> Function(String path) trackOf,
) => (path, size) async {
  final t = await trackOf(path);
  final coverId = t?.coverId;
  if (t == null || coverId == null || coverId.isEmpty) return null;
  return remoteCover(await resolver.source(t.accountId), coverId, size);
};

/// `Covers.remoteKey` for library tracks: account + cover id, shared by a whole album
/// (one download, one cache file); null when the server has no cover.
Future<String?> Function(String trackPath) remoteCoverKey(
  Future<Track?> Function(String path) trackOf,
) => (path) async {
  final t = await trackOf(path);
  final coverId = t?.coverId;
  if (t == null || coverId == null || coverId.isEmpty) return null;
  return '${t.accountId}/$coverId';
};

/// Lock screen: a server stream has no reliable tags nor embedded picture, so the
/// library tags and the cover **bytes** are given (never a URL: the OS cannot send headers).
MediaSession sessionFor(Track t, Uint8List? artwork) {
  if (parseRemoteKey(t.path) == null) return const MediaSession();
  return MediaSession(
    title: t.title,
    artist: t.artist,
    album: t.album,
    artwork: artwork == null
        ? MediaSessionArtwork.none
        : MediaSessionArtwork.custom(
            CoverArt(bytes: artwork, mimeType: 'image/jpeg'),
          ),
  );
}
