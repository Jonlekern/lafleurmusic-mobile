import '../../app_scope.dart';
import '../../settings.dart';
import '../../sources/accounts.dart';

/// Changing what the library shows (one account, all, or the checked ones): saved in the
/// settings, and every list follows at once. It only filters what is listed: playback may
/// still use another account's copy of a song.
extension DisplayChoice on AppScope {
  /// [order]: the accounts in the order of the accounts screen (for the first Perso choice).
  void chooseDisplay(
    DisplayMode mode, {
    String? account,
    List<Account> order = const [],
  }) {
    final s = settings;
    if (s == null) return;
    s.displayMode = mode;
    if (mode == DisplayMode.one && account != null) s.oneAccount = account;
    if (mode == DisplayMode.custom) {
      // never zero accounts: none of the checked ones left (first Perso, or they were
      // removed) = every account present is checked
      final present = {for (final a in order) a.id};
      if (!s.customAccounts.any(present.contains)) {
        s.customAccounts = [for (final a in order) a.id];
      }
    }
    _changed();
  }

  /// Checks or unchecks [id] in Perso. [order]: the accounts present; the last checked
  /// account present stays checked (stale ids of removed accounts do not count).
  void toggleCustom(String id, List<Account> order) {
    final s = settings;
    if (s == null) return;
    final present = {for (final a in order) a.id};
    final l = [
      for (final c in s.customAccounts)
        if (present.contains(c)) c,
    ];
    if (l.contains(id)) {
      if (l.length == 1) return;
      l.remove(id);
    } else {
      l.add(id);
    }
    s.customAccounts = l; // stale ids pruned on the way
    _changed();
  }

  /// An account was removed: it leaves the choices (Perso list, the Un compte pick).
  void forgetAccount(String id) {
    final s = settings;
    if (s == null) return;
    s.customAccounts = [
      for (final c in s.customAccounts)
        if (c != id) c,
    ];
    if (s.oneAccount == id) s.oneAccount = null;
    if (s.displayMode == DisplayMode.custom && s.customAccounts.isEmpty) {
      s.displayMode =
          DisplayMode.all; // Perso with nothing checked would show nothing
    }
    _changed();
  }

  void _changed() {
    saveSettings?.call();
    libraryView?.settingsChanged();
  }
}
