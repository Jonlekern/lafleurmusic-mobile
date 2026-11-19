import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../library/db.dart';
import '../library/models.dart';
import '../library/play_counter.dart';
import '../library/sync.dart';
import '../offline/device.dart';
import '../offline/paths.dart';
import '../player/media_resolver.dart';
import 'accounts.dart';
import 'jellyfin.dart';
import 'plex.dart';
import 'plex_link.dart';
import 'remote_key.dart';
import 'source.dart';
import 'subsonic.dart';

/// What the account form holds, before it is saved. Never logged.
class AccountDraft {
  const AccountDraft({
    this.type = AccountType.subsonic,
    this.name = '',
    required this.address,
    required this.user,
    this.password = '',
    this.headers = const {},
  });
  final AccountType type;
  final String name, address, user, password;
  final Map<String, String> headers;

  /// `192.168.1.20:4533` → `http://192.168.1.20:4533`; null when there is no host.
  Uri? get base {
    var a = address.trim();
    if (a.isEmpty) return null;
    if (!a.contains('://')) a = 'http://$a';
    final u = Uri.tryParse(a);
    if (u == null || u.host.isEmpty) return null;
    if (u.scheme != 'http' && u.scheme != 'https') return null;
    return u;
  }

  /// The server is on the home network (private IPv4, link-local, `.local`, IPv6 ULA):
  /// iOS asks permission before the app can reach it.
  bool get isLocalNetwork {
    final h = (base?.host ?? '').toLowerCase();
    if (h.isEmpty) return false;
    if (h.endsWith('.local') || h == 'localhost') return true;
    final v4 = RegExp(r'^(\d+)\.(\d+)\.(\d+)\.(\d+)$').firstMatch(h);
    if (v4 != null) {
      final a = int.parse(v4[1]!), b = int.parse(v4[2]!);
      return a == 10 ||
          a == 127 ||
          (a == 172 && b >= 16 && b <= 31) ||
          (a == 192 && b == 168) ||
          (a == 169 && b == 254);
    }
    if (h.contains(':')) {
      return h.startsWith('fe80') ||
          h.startsWith('fc') ||
          h.startsWith('fd') ||
          h == '::1';
    }
    return false;
  }

  /// The name typed, or the server's host.
  String get displayName =>
      name.trim().isNotEmpty ? name.trim() : (base?.host ?? '');

  /// Why the draft can't be tested or saved yet.
  DraftProblem? problem({required bool needsPassword}) {
    if (address.trim().isEmpty ||
        user.trim().isEmpty ||
        (needsPassword && password.isEmpty)) {
      return DraftProblem.missing;
    }
    if (base == null) return DraftProblem.badAddress;
    return null;
  }
}

enum DraftProblem { missing, badAddress }

/// Status dot of an account on the accounts screen. [relink]: its token was revoked (Plex),
/// a new code is needed (« À reconnecter »).
enum AccountState { checking, syncing, connected, absent, relink }

/// Test, save, sync and remove accounts; remembers whether each server answered.
/// One per app: it shares the [Accounts] and the [MediaResolver] built in main.
class AccountService extends ChangeNotifier {
  AccountService(
    this.accounts, {
    required LibraryDb db,
    this.resolver,
    this._draftSource,
    Future<MusicSource> Function(String id)? sourceOf,
    Future<SyncResult> Function(MusicSource source)? sync,
    this.forgetCovers,
    this.device,
    Future<void> Function(Duration)? wait,
    DateTime Function()? clock,
    this._plexLink,
  }) : _clock = clock ?? DateTime.now,
       _wait = wait, // ignore: prefer_initializing_formals
       _db = db,
       _sourceOf = sourceOf ?? resolver?.source ?? accounts.source,
       _sync =
           sync ??
           LibrarySync(
             db,
             copyRoot: device == null ? null : () => _copyRootOf(device),
           ).run;

  final LibraryDb _db;
  final PlexLink Function(String clientId)? _plexLink;

  /// A new plex.tv sign-in (a fake plex.tv in tests), with this install's client identifier.
  /// The caller closes it.
  Future<PlexLink> newPlexLink() async {
    final id = await accounts.plexClientId();
    return _plexLink?.call(id) ?? PlexLink(clientId: id);
  }

  /// Pause between the quick syncs after a save (a fake clock in tests).
  final Future<void> Function(Duration)? _wait;
  final DateTime Function() _clock;

  /// A check that finds the server answering restarts a sync no sooner than this after the
  /// last sync began.
  static const checkSyncFloor = Duration(minutes: 10);

  // accounts whose last sync was incomplete while the server did NOT answer (network down,
  // iOS local-network prompt…): the next check that finds it answering syncs again
  final _retryOnOk = <String>{};
  final _lastStart = <String, DateTime>{};
  final _timers = <String, Set<Timer>>{};

  void _stopTimers(String id) {
    for (final t in _timers.remove(id) ?? const <Timer>{}) {
      t.cancel();
    }
  }

  Future<void> _pause(String id, Duration d) {
    final w = _wait;
    if (w != null) return w(d);
    final c = Completer<void>();
    late final Timer t;
    t = Timer(d, () {
      _timers[id]?.remove(t);
      c.complete();
    });
    (_timers[id] ??= {}).add(t);
    return c.future;
  }

  /// Gap between the syncs that follow a save.
  static const followUpDelay = Duration(seconds: 30);

  /// Syncs started by one save, the first included: the 2nd always runs, the 3rd only if
  /// the 2nd wasn't complete.
  static const quickSyncs = 3;

  /// The phone: where the kept copies live. Without it, finished copies are left alone
  /// when a track leaves the server or an account is removed.
  final Device? device;

  /// The copies' folder, or null when it can't be reached (card removed…): then a missing
  /// file proves nothing and no kept copy may be dropped.
  static Future<CopyRoot?> _copyRootOf(Device d) async {
    try {
      if (!await d.rootReachable()) return null;
      return CopyRoot((await d.musicRoot()).path, d.keyFor);
    } on Object {
      return null;
    }
  }

  final Accounts accounts;
  final MediaResolver? resolver;
  final MusicSource Function(AccountDraft, String)? _draftSource;
  final Future<MusicSource> Function(String id) _sourceOf;
  final Future<SyncResult> Function(MusicSource) _sync;

  /// Erases the account's cached covers (main: [Covers.forgetAccount]).
  final Future<void> Function(String accountId)? forgetCovers;

  /// A server that doesn't answer within this is "unreachable".
  static const testTimeout = Duration(seconds: 10);

  final _results = <String, TestResult>{};
  final _checking = <String>{};
  final _syncing = <String, Future<void>>{};
  // settings changed while a sync ran: one more run once it ends
  final _rerun = <String>{};
  // bumped on every edit or removal: an older test or sync must not record its result
  final _gen = <String, int>{};
  final _removed = <String>{};
  // newest save per account: an older chain of follow-up syncs stops when it sees another
  final _chain = <String, int>{};
  // did the last finished sync of the account store everything?
  final _lastComplete = <String, bool>{};
  final _cancel = <String, _CancelFlag>{};

  int _genOf(String id) => _gen[id] ?? 0;
  void _bump(String id) => _gen[id] = _genOf(id) + 1;

  /// Records [r] unless the account was edited or removed since [gen].
  void _record(String id, int gen, TestResult r) {
    if (_removed.contains(id) || _genOf(id) != gen) return;
    _results[id] = r;
  }

  AccountState? stateOf(String id) {
    if (_syncing.containsKey(id)) return AccountState.syncing;
    if (_checking.contains(id)) return AccountState.checking;
    final r = _results[id];
    if (r == null) return null;
    return switch (r) {
      TestResult.ok => AccountState.connected,
      TestResult.tokenRevoked => AccountState.relink,
      _ => AccountState.absent,
    };
  }

  /// May the account's server answer now? Not when found unreachable, nor when its token
  /// was revoked. Unknown (never tested yet) counts as yes.
  bool mayAnswer(String id) {
    final st = stateOf(id);
    return st != AccountState.absent && st != AccountState.relink;
  }

  Map<String, OfflineRow> _kept = const {};
  String? _root, _docs;
  CopyRoot?
  _copyRoot; // the reachable copies' folder, as of the last [refreshRoot]
  StreamSubscription<Map<String, OfflineRow>>? _keptSub;
  // songs on several rows: merge key → (path, account), local files then the accounts' order
  Map<String, List<(String, String)>> _twins = const {};
  // the same, by path of each row (playableNow runs for every row of a list)
  Map<String, List<(String, String)>> _twinsOf = const {};
  StreamSubscription<Map<String, List<(String, String)>>>? _twinsSub;

  /// Follows the offline rows so [playableNow] can answer at once. The folder is read on
  /// [refreshRoot] only (a folder change calls it); an emit of the same rows notifies nobody.
  Future<void> watchOffline() async {
    await refreshRoot();
    await _twinsSub?.cancel();
    _twinsSub = _db.watchTwins().listen((m) {
      // a sync writes often: the same twins notify nobody
      final same =
          m.length == _twins.length &&
          m.entries.every((e) => listEquals(e.value, _twins[e.key]));
      _twins = m;
      _twinsOf = {
        for (final rows in m.values)
          for (final r in rows) r.$1: rows,
      };
      if (!same && !_disposed) notifyListeners();
    });
    await _keptSub?.cancel();
    _keptSub = _db.watchOffline().listen((m) async {
      if (mapEquals(m, _kept)) return;
      _kept = m;
      final root = _copyRoot;
      try {
        // one query, nothing to do most of the time
        if (root != null) await _db.adoptOrphans(root);
      } on Object {
        // the next change tries again
      }
      if (!_disposed) notifyListeners();
    });
  }

  /// Reads the copies' folder and the Documents folder again (after a folder change).
  /// A reachable folder also settles the tracks of accounts removed while it was unreachable.
  Future<void> refreshRoot() async {
    final d = device;
    if (d != null) {
      try {
        _root = (await d.musicRoot()).path;
        _docs = await d.absolutePath(docsScheme);
        final root = _copyRoot = await _copyRootOf(d);
        if (root != null) await _db.adoptOrphans(root);
      } on Object {
        // keep what we knew
      }
    }
    if (!_disposed) notifyListeners(); // an emit can land after dispose
  }

  bool _disposed = false;

  String _absolute(String path) => path.startsWith(docsScheme) && _docs != null
      ? p.join(_docs!, path.substring(docsScheme.length))
      : path;

  /// Can this track start now? A local file: it exists. A server track: one of its rows
  /// (the same song on other accounts, a file on the phone: [MediaResolver.media]) can — a
  /// finished copy that exists, a file that exists, or an account not found unreachable.
  /// The track playing is never asked: it finishes if it is in memory; only the NEXT
  /// choice uses this.
  bool playableNow(Track t) {
    // a file iCloud put aside (`.name.icloud`) counts: iOS fetches it on open (online)
    if (parseRemoteKey(t.path) == null) {
      return fileOrPlaceholderExists(_absolute(t.path));
    }
    final rows = [
      (t.path, t.accountId),
      // the same song elsewhere (another row of its own account is another song)
      for (final r in _twinsOf[t.path] ?? const <(String, String)>[])
        if (r.$2 != t.accountId) r,
    ];
    if (rows.any((r) => r.$2 != 'local' && _keptCopyExists(r.$1))) return true;
    if (rows.any(
      (r) => r.$2 == 'local' && fileOrPlaceholderExists(_absolute(r.$1)),
    )) {
      return true;
    }
    return rows.any((r) => r.$2 != 'local' && mayAnswer(r.$2));
  }

  bool _keptCopyExists(String path) {
    final row = _kept[path];
    final rel = row?.filePath;
    final root = _root;
    return row != null &&
        row.state == OfflineState.done.name &&
        rel != null &&
        root != null &&
        fileOrPlaceholderExists(p.join(root, rel));
  }

  @override
  void dispose() {
    _disposed = true;
    for (final id in _timers.keys.toList()) {
      _stopTimers(id);
    }
    _keptSub?.cancel();
    _twinsSub?.cancel();
    super.dispose();
  }

  /// Every account tried so far failed to answer at all.
  bool get offline =>
      _results.isNotEmpty &&
      _results.values.every((r) => r == TestResult.unreachable);

  /// At least one server answered the last test.
  bool get anyConnected => _results.values.any((r) => r == TestResult.ok);

  /// The accounts whose last test failed ([AccountState.absent] when not busy).
  Set<String> get absentIds => {
    for (final e in _results.entries)
      if (e.value != TestResult.ok) e.key,
  };

  /// A sync is running for at least one account.
  bool get syncing => _syncing.isNotEmpty;

  /// Set by the last [testDraft]: the https address the server redirected to, or null.
  Uri? draftRedirect;

  /// "Tester": a throw-away source built from the form, nothing saved.
  /// [id]: the account being edited (its stored password is used when the field is empty).
  Future<TestResult> testDraft(AccountDraft d, {String? id}) async {
    var password = d.password;
    if (password.isEmpty && id != null) {
      password = await accounts.password(id) ?? '';
    }
    draftRedirect = null;
    final custom = _draftSource;
    if (custom != null) return _timed(custom(d, password));
    final client = newServerClient();
    try {
      switch (d.type) {
        case AccountType.jellyfin:
          // nothing stored: a test is not a sign-in the account keeps
          final source = JellyfinSource(
            accountId: id ?? 'draft',
            base: d.base!,
            user: d.user.trim(),
            password: password,
            headers: d.headers,
            client: client,
          );
          final r = await _timed(source);
          draftRedirect = source.redirectedBase;
          return r;
        case AccountType.plex:
          return TestResult
              .unreachable; // signed in by a code, never from the form
        case AccountType.subsonic:
          final source = SubsonicSource(
            accountId: id ?? 'draft',
            base: d.base!,
            user: d.user.trim(),
            password: password,
            headers: d.headers,
            client: client,
          );
          final r = await _timed(source);
          draftRedirect = source.redirectedBase;
          return r;
      }
    } finally {
      client.close();
    }
  }

  Future<TestResult> _timed(MusicSource s) async {
    try {
      return await s.test().timeout(
        testTimeout,
        onTimeout: () => TestResult.unreachable,
      );
    } catch (_) {
      return TestResult
          .unreachable; // any failure: the server didn't answer usefully
    }
  }

  /// "Enregistrer": adds (or updates [editing]), then syncs in the background.
  /// An empty password on an edit keeps the stored one; [keepHeaders] keeps the stored headers
  /// (the form never loaded them).
  Future<Account> save(
    AccountDraft d, {
    Account? editing,
    bool keepHeaders = false,
  }) async {
    final base = d.base!;
    final Account a;
    if (editing == null) {
      a = await accounts.add(
        type: d.type,
        name: d.displayName,
        base: base,
        user: d.user.trim(),
        password: d.password,
        headers: d.headers,
      );
    } else {
      a = Account(
        id: editing.id,
        type: editing.type, // never changed by an edit: its keys and secrets belong to it
        name: d.displayName,
        base: base,
        user: d.user.trim(),
        order: editing.order,
      );
      await accounts.update(
        a,
        password: d.password.isEmpty ? null : d.password,
        headers: keepHeaders ? null : d.headers,
      );
      resolver?.invalidate(a.id); // new address, password or headers
      _bump(a.id);
      _results.remove(a.id);
      notifyListeners();
    }
    unawaited(_syncAfterSave(a.id));
    return a;
  }

  /// A Plex account found by a code (see [PlexLink]), then synced like a saved one.
  Future<Account> addPlex({
    required String name,
    required PlexServer server,
    required String token,
    required Uri base,
    String? accountToken,
    String? plexUser,
  }) async {
    final a = await accounts.addPlex(
      name: name,
      server: server,
      token: token,
      base: base,
      accountToken: accountToken,
      plexUser: plexUser,
    );
    unawaited(_syncAfterSave(a.id));
    return a;
  }

  /// « Nouveau code » on an account « À reconnecter »: the token is replaced in place (same
  /// id, tracks and kept copies), the old source dropped, then a sync.
  Future<void> relinkPlex(
    String id, {
    required PlexServer server,
    required String token,
    required Uri base,
    String? accountToken,
    String? plexUser,
  }) async {
    await accounts.relinkPlex(
      id,
      server: server,
      token: token,
      base: base,
      accountToken: accountToken,
      plexUser: plexUser,
    );
    resolver?.invalidate(id);
    _bump(id);
    _results.remove(id);
    notifyListeners();
    unawaited(_syncAfterSave(id));
  }

  /// Now, 30 s later, and once more 30 s after that while the last one wasn't complete
  /// (the server or the phone's network may not be ready right after the form: iOS asks
  /// for the local network on the first request). One at a time per account.
  Future<void> _syncAfterSave(String id) async {
    final mine = _chain[id] = (_chain[id] ?? 0) + 1;
    _stopTimers(id); // the older chain's pending pause
    bool stale() => _disposed || _removed.contains(id) || _chain[id] != mine;
    try {
      for (var n = 1; n <= quickSyncs; n++) {
        if (n == 3 && _lastComplete[id] == true) return;
        if (n > 1) {
          await _pause(id, followUpDelay);
          if (stale()) return;
        }
        await sync(id, fresh: true);
        if (stale()) return;
      }
    } on Object {
      // a sync never throws; a failed wait just ends the chain
    }
  }

  /// Removes the account and its tracks from this phone (nothing on the server).
  /// A running sync is stopped (between albums) and awaited first, so it can't store tracks afterwards.
  Future<void> remove(String id) async {
    _removed.add(id);
    _bump(id);
    _rerun.remove(id);
    _retryOnOk.remove(id);
    _chain[id] = (_chain[id] ?? 0) + 1; // no follow-up sync after the removal
    _stopTimers(id);
    _cancel[id]?.cancelled = true;
    final running = _syncing[id];
    if (running != null) await running.catchError((Object _) {});
    PlexSource.forgetAccount(id); // a Plex address refresh still running writes nothing
    final d = device;
    await accounts.remove(id, root: d == null ? null : await _copyRootOf(d));
    resolver?.invalidate(id);
    try {
      await forgetCovers?.call(id);
    } catch (_) {} // a leftover cover file is harmless
    _results.remove(id);
    _checking.remove(id);
    notifyListeners();
  }

  /// Light test() of each account (accounts screen opening); a syncing one is checked when
  /// its sync ends.
  Future<void> checkAll(Iterable<String> ids) => Future.wait([
    for (final id in ids)
      if (_syncing.containsKey(id))
        _checkAfterSync(id)
      else if (_checking.add(id))
        _check(id),
  ]).then((_) {});

  /// Accounts asked to be checked while they synced: checked once the sync ends. A sync that
  /// already read everything says "ok" even if the network changed while it stored it (the
  /// server cut, the phone out of the house).
  final _recheck = <String>{};

  Future<void> _checkAfterSync(String id) {
    _recheck.add(id);
    return Future.value();
  }

  /// [checkAll] on every account (the network changed: who answers from here?).
  Future<void> checkAccounts() async {
    // home / away: Plex may read its server addresses from plex.tv again at once
    PlexSource.resetRefreshCooldowns();
    return checkAll([for (final a in await accounts.watch().first) a.id]);
  }

  Future<void> _check(String id) async {
    notifyListeners();
    final gen = _genOf(id);
    TestResult r;
    try {
      r = await _timed(await _sourceOf(id));
    } catch (_) {
      r = TestResult.unreachable; // unsupported type, missing password…
    }
    _checking.remove(id);
    _record(id, gen, r);
    notifyListeners();
    if (r == TestResult.ok) {
      await _flushPending(id);
      // The server answers now but the last sync did not finish (the iOS local-network prompt was
      // answered late, say): drop the source built meanwhile and sync.
      final last = _lastStart[id];
      if (_retryOnOk.contains(id) &&
          !_removed.contains(id) &&
          !_syncing.containsKey(id) &&
          (last == null || _clock().difference(last) >= checkSyncFloor)) {
        _retryOnOk.remove(id);
        resolver?.invalidate(id);
        unawaited(sync(id));
      }
    }
  }

  final _flushing = <String>{};

  /// Listens older than this are dropped instead of sent.
  static const pendingMaxAge = Duration(days: 30);

  /// The server answered: sends the account's pending listens one at a time, oldest first,
  /// each with its original date (those older than [pendingMaxAge] are dropped first). A sent one is erased at once; the first failure stops the
  /// run (the rest waits for the next return); a song the server doesn't know is dropped.
  /// Never two runs for one account.
  Future<void> _flushPending(String id) async {
    if (_removed.contains(id) || !_flushing.add(id)) return;
    try {
      await _db.dropPendingBefore(id, DateTime.now().subtract(pendingMaxAge));
      final todo = await _db.pending(id)
        ..sort(
          (a, b) => a.at != b.at ? a.at.compareTo(b.at) : a.id.compareTo(b.id),
        );
      if (todo.isEmpty) return;
      final source = await _sourceOf(id);
      for (final q in todo) {
        if (_removed.contains(id)) return;
        try {
          await source.scrobble(
            q.remoteId,
            DateTime.fromMillisecondsSinceEpoch(q.at),
          );
        } on Object catch (e) {
          if (!scrobbleRefused(e)) return;
        }
        await _db.deletePending([q.id]);
      }
    } on Object {
      // nothing sent is lost: it stays pending
    } finally {
      _flushing.remove(id);
    }
  }

  /// Copies the server library to the phone; an interrupted sync asks the server why.
  /// [fresh]: the settings just changed; if a sync is running, one more follows it.
  Future<void> sync(String id, {bool fresh = false}) {
    if (_removed.contains(id)) return Future.value();
    final running = _syncing[id];
    if (running != null) {
      if (fresh) _rerun.add(id);
      return running;
    }
    return _syncing[id] = _syncLoop(id).whenComplete(() {
      _syncing.remove(id);
      _cancel.remove(id);
      notifyListeners();
      if (_recheck.remove(id) && !_removed.contains(id)) {
        unawaited(checkAll([id]));
      }
    });
  }

  Future<void> _syncLoop(String id) async {
    notifyListeners();
    do {
      _rerun.remove(id);
      await _syncOnce(id);
    } while (_rerun.contains(id) && !_removed.contains(id));
  }

  Future<void> _syncOnce(String id) async {
    final gen = _genOf(id);
    final flag = _cancel[id] = _CancelFlag();
    _lastStart[id] = _clock();
    TestResult r;
    try {
      final s = _CancellableSource(await _sourceOf(id), flag);
      final done = await _sync(s);
      if (flag.cancelled) return;
      _lastComplete[id] = done.complete;
      r = done.complete ? TestResult.ok : await _timed(s);
      if (done.complete || r == TestResult.ok) {
        _retryOnOk.remove(id);
      }
      if (!done.complete && r != TestResult.ok) _retryOnOk.add(id);
    } catch (_) {
      _lastComplete[id] = false;
      _retryOnOk.add(id);
      r = TestResult.unreachable;
    }
    _record(id, gen, r);
    if (r == TestResult.ok && !flag.cancelled) await _flushPending(id);
  }

  /// Launch and pull-to-refresh.
  Future<void> syncAll() async {
    final list = await accounts.watch().first;
    await Future.wait([for (final a in list) sync(a.id)]);
  }
}

class _CancelFlag {
  bool cancelled = false;
}

/// Stops a sync between albums once its account is removed: songs answered after that are dropped.
class _CancellableSource implements MusicSource, TypedSource {
  _CancellableSource(this._inner, this._flag);
  final MusicSource _inner;
  final _CancelFlag _flag;

  void _check() {
    if (_flag.cancelled) throw const _Cancelled();
  }

  @override
  String get accountId => _inner.accountId;

  @override
  AccountType get accountType {
    final i = _inner;
    return i is TypedSource
        ? (i as TypedSource).accountType
        : AccountType.subsonic;
  }

  @override
  Future<TestResult> test() => _inner.test();

  @override
  Stream<List<SourceAlbum>> albums({int pageSize = 500}) async* {
    await for (final page in _inner.albums(pageSize: pageSize)) {
      _check();
      yield page;
    }
  }

  @override
  Future<List<SourceSong>> albumSongs(String albumId) async {
    _check();
    final songs = await _inner.albumSongs(albumId);
    _check();
    return songs;
  }

  @override
  Future<List<SourcePlaylist>> playlists() async {
    _check();
    final lists = await _inner.playlists();
    _check();
    return lists;
  }

  @override
  Uri streamUri(String songId) => _inner.streamUri(songId);

  @override
  Uri downloadUri(String songId) => _inner.downloadUri(songId);

  @override
  Uri coverUri(String coverId, int size) => _inner.coverUri(coverId, size);

  @override
  Map<String, String> get headers => _inner.headers;

  @override
  Future<void> scrobble(String songId, DateTime at) =>
      _inner.scrobble(songId, at);

  @override
  void close() {} // the inner source is shared (resolver): not ours to close
}

class _Cancelled implements Exception {
  const _Cancelled();
}
