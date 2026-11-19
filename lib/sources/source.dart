import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// A home server reached from outside the house never answers: its address
/// (192.168.x.x) hangs instead of failing. Connecting gives up after this.
const connectTimeout = Duration(seconds: 8);

/// A whole request (connection, headers and body) gives up after this.
const requestTimeout = Duration(seconds: 15);

/// HTTP client for a music server: gives up connecting after [connectTimeout].
http.Client newServerClient() =>
    IOClient(HttpClient()..connectionTimeout = connectTimeout);

int _portOf(Uri u) => u.hasPort ? u.port : (u.scheme == 'https' ? 443 : 80);

/// A redirect hop we accept: same host, http or https, never https -> http, and the
/// port unchanged (or the default https port when upgrading).
bool sameHostHop(Uri from, Uri to) {
  if (to.scheme != 'http' && to.scheme != 'https') return false;
  if (to.host.toLowerCase() != from.host.toLowerCase()) return false;
  if (from.scheme == 'https' && to.scheme == 'http') return false;
  final upgrade = from.scheme == 'http' && to.scheme == 'https';
  return _portOf(to) == _portOf(from) || (upgrade && _portOf(to) == 443);
}

/// A music source (Subsonic, Jellyfin, Plex) as seen by sync and playback.
class SourceAlbum {
  const SourceAlbum({
    required this.id,
    required this.name,
    required this.artist,
    this.coverId,
    this.songCount = 0,
  });

  final String id, name, artist;
  final String? coverId;
  final int songCount;
}

class SourceSong {
  const SourceSong({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.albumArtist,
    this.genre = '',
    this.track,
    this.disc,
    this.durationMs = 0,
    this.size = 0,
    this.coverId,
    this.suffix,
    this.replayGainTrack,
    this.replayGainAlbum,
    this.playCount = 0,
  });

  final String id, title, artist, album, albumArtist, genre;
  final int? track, disc;
  final int durationMs, size;
  final String? coverId, suffix;
  final double? replayGainTrack, replayGainAlbum;
  final int playCount;
}

/// A playlist of a server: its songs in the server's order (a song may come back twice).
/// [songIds] null: its songs could not be read this time (the old ones stay).
class SourcePlaylist {
  const SourcePlaylist({
    required this.id,
    required this.name,
    required this.songIds,
  });

  final String id, name;
  final List<String>? songIds;
}

/// A network failure talking to a source (refused, timeout, TLS…).
/// Its text never carries the request URL: the query holds the credentials.
class SourceNetworkException implements Exception {
  SourceNetworkException(Object cause)
    : kind = cause.runtimeType.toString(),
      message = _redact(_describe(cause));

  /// Type of the original error, e.g. `SocketException`, `ClientException`.
  final String kind;
  final String message;

  static String _describe(Object e) {
    // never e.toString(): ClientException's adds the URL
    final m = switch (e) {
      SocketException() => e.osError?.message ?? e.message,
      http.ClientException() => e.message,
      TlsException() => e.message,
      TimeoutException() => e.message ?? 'timed out',
      _ => '',
    };
    return m.isEmpty ? 'network error' : m;
  }

  static String _redact(String s) => s
      .replaceAll(RegExp(r'\w+://\S*'), '<url>')
      .replaceAll(RegExp(r'\?\S*'), '');

  @override
  String toString() => 'SourceNetworkException($kind): $message';
}

enum TestResult {
  ok,
  unreachable,
  wrongPassword,
  headerRefused,
  notSubsonic,

  /// The address answers but is not a Jellyfin server.
  notJellyfin,

  /// https: the server's certificate was refused (self-signed, expired, wrong name).
  certificateRejected,

  /// The token was revoked (Plex: access removed on plex.tv) and can't be renewed by the app:
  /// the account needs a new code (« À reconnecter »).
  tokenRevoked,
}

abstract interface class MusicSource {
  String get accountId;
  Future<TestResult> test();

  /// One page at a time, fetched lazily.
  Stream<List<SourceAlbum>> albums({int pageSize = 500});
  Future<List<SourceSong>> albumSongs(String albumId);

  /// The server's playlists, each with its songs in order.
  Future<List<SourcePlaylist>> playlists();

  /// Full authenticated URL (account headers are separate: [headers]).
  Uri streamUri(String songId);

  /// The original file (offline copies); same auth as [streamUri].
  Uri downloadUri(String songId);
  Uri coverUri(String coverId, int size);
  Map<String, String> get headers;
  Future<void> scrobble(String songId, DateTime at);

  /// Releases the connections (the source is not used afterwards).
  void close();
}

/// A source whose token must be loaded before [MusicSource.headers] and [MusicSource.streamUri]
/// are read (they are synchronous), and that can sign in again when the server refuses it.
abstract interface class AuthRenewable {
  /// Loads the stored token, or signs in when there is none.
  Future<void> prepare();

  /// The server refused the token: signs in again (once per call). Throws when it can't.
  Future<void> renewAuth();
}

/// A source reached over HTTP: its client also fetches the covers (same connection pool, mockable in tests).
abstract interface class HttpSource {
  http.Client get httpClient;
}
