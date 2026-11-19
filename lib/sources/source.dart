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
    this.editable = true,
  });

  final String id, name;
  final List<String>? songIds;

  /// False when the server says this account may not change it (Subsonic: another user's
  /// playlist, or OpenSubsonic `readonly`). True when the server does not say.
  final bool editable;
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

/// A source that must look a song's file address up on the server before [MusicSource.streamUri]
/// and [MusicSource.downloadUri] (both synchronous) can answer (Plex: the file's `Part` key).
/// Callers wait for it after [AuthRenewable.prepare].
abstract interface class SongResolving {
  /// Looks the file of [songId] up. Throws when the server doesn't have it (Plex: a
  /// `PlexException` with status 404: this song only is refused). [batch]: a run over many
  /// songs (offline copies): the rest of the song's album may be read at once.
  Future<void> resolveSong(String songId, {bool batch = false});

  /// The server refused the file found for [songId] (404: it was rescanned): forgets that
  /// address, and the album's, so the next [resolveSong] asks the server again.
  Future<void> forgetSong(String songId);
}

/// A source reached over HTTP: its client also fetches the covers (same connection pool, mockable in tests).
abstract interface class HttpSource {
  http.Client get httpClient;
}

/// A source that can change its server's playlists (plan 9). Positions are 0-based, in the
/// server's order (a song may be there twice). Each call changes the server only: the caller
/// reads the playlist again ([readPlaylist]) and stores what the server says. A server that
/// won't let this account write throws a [PlaylistWriteRefused]; a network failure, a
/// [SourceNetworkException]. A source that can never write does not implement this.
abstract interface class PlaylistWriter {
  /// A new playlist named [name] holding [songIds] (empty: an empty playlist); returns its
  /// id on the server.
  Future<String> createPlaylist(String name, {List<String> songIds = const []});

  /// Adds [songIds] (this server's ids) at the end, in their order.
  Future<void> addToPlaylist(String id, List<String> songIds);

  /// Takes the rows at [positions] out; the others keep their order. [expected]: the song
  /// id the caller sees at each position (same order); when the server has another one
  /// there, a [PlaylistChanged] and nothing sent.
  Future<void> removeFromPlaylist(
    String id,
    List<int> positions, {
    List<String>? expected,
  });

  /// Moves the row at [from] so it ends at [to] (list-move semantics; out of range on the
  /// server: a [PlaylistChanged], nothing sent). [expected]: the song id the caller sees at
  /// [from]; another one there on the server is a [PlaylistChanged] too.
  Future<void> movePlaylistItem(
    String id,
    int from,
    int to, {
    String? expected,
  });

  Future<void> renamePlaylist(String id, String name);
  Future<void> deletePlaylist(String id);

  /// The playlist as the server has it now (its songs never null: a failure throws).
  Future<SourcePlaylist> readPlaylist(String id);
}

/// The server refused to change its playlists for this account (no rights, a server too
/// old). Nothing was changed. Never carries a token or an address.
class PlaylistWriteRefused implements Exception {
  PlaylistWriteRefused(this.message);
  final String message;
  @override
  String toString() => 'PlaylistWriteRefused: $message';
}

/// The playlist on the server is not the one the caller saw (changed elsewhere meanwhile):
/// nothing was sent. Read it again and let the user try again.
class PlaylistChanged implements Exception {
  @override
  String toString() => 'PlaylistChanged';
}

/// Checks that [rows] (a fresh read) has [expected] at each of [positions] (same order;
/// null: nothing to check). A position out of [rows] or another song there: [PlaylistChanged].
void checkPlaylistRows(
  List<String> rows,
  List<int> positions,
  List<String>? expected,
) {
  for (final (i, p) in positions.indexed) {
    if (p < 0 || p >= rows.length) throw PlaylistChanged();
    if (expected != null && i < expected.length && rows[p] != expected[i]) {
      throw PlaylistChanged();
    }
  }
}

/// The list is too long for this server to take in one request, and it can't be sent in
/// parts without risking a half-written playlist (Subsonic without form POST). Nothing sent.
class PlaylistTooLong implements Exception {
  PlaylistTooLong(this.count);
  final int count;
  @override
  String toString() => 'PlaylistTooLong($count songs)';
}
