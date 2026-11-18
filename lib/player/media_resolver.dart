import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:mpv_audio_kit/mpv_audio_kit.dart' hide Track;

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

/// Turns a library path into what mpv opens: the file itself, or the server
/// stream with the account headers. Never logs the stream URL (it carries the token).
class MediaResolver {
  MediaResolver(this._sourceOf);

  /// Plays local files only (no account known).
  MediaResolver.localOnly()
    : _sourceOf = ((id) async => throw StateError('No account $id'));

  final Future<MusicSource> Function(String accountId) _sourceOf;
  final _sources = <String, Future<MusicSource>>{};

  /// One source per account, kept until [invalidate] (password or headers changed).
  Future<MusicSource> source(String accountId) =>
      _sources.putIfAbsent(accountId, () {
        final f = _sourceOf(accountId);
        // a failure (password missing…) is retried next time
        f.then<void>(
          (_) {},
          onError: (Object _) {
            if (identical(_sources[accountId], f)) _sources.remove(accountId);
          },
        );
        return f;
      });

  void invalidate(String accountId) => _sources.remove(accountId);

  Future<Media> media(String path) async {
    final key = parseRemoteKey(path);
    if (key == null) return Media(path);
    final MusicSource s;
    try {
      s = await source(key.$1);
    } on Object {
      // account gone or unusable: mpv fails on the raw key and the track is skipped like an unreadable file
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
}) async {
  final c = client ?? (s is HttpSource ? (s as HttpSource).httpClient : null);
  final own = c == null;
  final cl = c ?? http.Client();
  try {
    final res = await cl.get(s.coverUri(coverId, size), headers: s.headers);
    final type = res.headers['content-type'] ?? '';
    // Subsonic answers "not found" with a 200 and a JSON/XML error
    if (res.statusCode != 200 ||
        res.bodyBytes.isEmpty ||
        type.contains('json') ||
        type.contains('xml')) {
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
