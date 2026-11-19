import 'accounts.dart';

/// The key of a server track in the library is a path-like string: `<scheme>://account/song`.
/// This file owns the schemes; nothing else spells them out.
const subsonicScheme = 'subsonic://';
const jellyfinScheme = 'jellyfin://';

/// Every scheme a server track can have (rows written before Jellyfin keep `subsonic://`).
const remoteSchemes = [subsonicScheme, jellyfinScheme];

/// Scheme of the keys of [type]'s tracks.
String schemeOf(AccountType type) => switch (type) {
  AccountType.subsonic => subsonicScheme,
  AccountType.jellyfin => jellyfinScheme,
  AccountType.plex => throw UnsupportedError('plex is not supported yet'),
};

/// Library key of song [id] of account [acc].
String remoteKey(AccountType type, String acc, String id) =>
    '${schemeOf(type)}$acc/$id';

/// The scheme [path] starts with, or null for a local file.
String? remoteSchemeOf(String path) {
  for (final s in remoteSchemes) {
    if (path.startsWith(s)) return s;
  }
  return null;
}

/// A server track's key (not a file on the phone).
bool isRemotePath(String path) => remoteSchemeOf(path) != null;

/// `<scheme>://acc/song` → (acc, song); null for a local file or a malformed key.
(String, String)? parseRemoteKey(String path) {
  final scheme = remoteSchemeOf(path);
  if (scheme == null) return null;
  final rest = path.substring(scheme.length);
  final slash = rest.indexOf('/');
  if (slash <= 0 || slash == rest.length - 1) return null;
  return (rest.substring(0, slash), rest.substring(slash + 1));
}

/// SQL `LIKE` condition (no bound value) true for a server track path in column [col].
String sqlIsRemote(String col) =>
    '(${[for (final s in remoteSchemes) "$col LIKE '$s%'"].join(' OR ')})';

/// A source that says which scheme its keys use. Sources that don't (test doubles) are Subsonic.
abstract interface class TypedSource {
  AccountType get accountType;
}
