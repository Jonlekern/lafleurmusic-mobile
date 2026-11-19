import '../library/merge.dart' show albumKeyOf;
import '../library/models.dart';

/// Pourquoi l'utilisateur garde un morceau (table `KeepOrigins`, règle Q13).
abstract final class KeepOrigin {
  /// Gardé pour lui-même (feuille d'un morceau, liste Morceaux, artiste…).
  static const song = 'song';
  static String songOf(Track _) => song;

  /// Gardé par l'utilisateur avant la v4 (0.2.0) : un album ou le morceau, on ne sait pas.
  /// Seul, il n'empêche pas de retirer un album ou une playlist ; le retrait d'un morceau
  /// l'emporte comme les autres.
  static const legacy = 'legacy';

  /// Gardé avec son album (⬇ de l'album, « Sélectionner », feuille d'un album).
  static String albumOf(Track t) => 'album:${albumKeyOf(t)}';
  static String album(String albumKey) => 'album:$albumKey';
  static String playlist(String accountId, String playlistId) =>
      'playlist:$accountId/$playlistId';
}
