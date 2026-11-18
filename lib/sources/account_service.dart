import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../library/db.dart';
import '../library/sync.dart';
import '../player/media_resolver.dart';
import 'accounts.dart';
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

/// Status dot of an account on the accounts screen.
enum AccountState { checking, syncing, connected, absent }

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
  }) : _sourceOf = sourceOf ?? resolver?.source ?? accounts.source,
       _sync = sync ?? LibrarySync(db).run;

  final Accounts accounts;
  final MediaResolver? resolver;
  final MusicSource Function(AccountDraft, String)? _draftSource;
  final Future<MusicSource> Function(String id) _sourceOf;
  final Future<SyncResult> Function(MusicSource) _sync;

  /// A server that doesn't answer within this is "unreachable".
  static const testTimeout = Duration(seconds: 10);

  final _results = <String, TestResult>{};
  final _checking = <String>{};
  final _syncing = <String, Future<void>>{};

  AccountState? stateOf(String id) {
    if (_syncing.containsKey(id)) return AccountState.syncing;
    if (_checking.contains(id)) return AccountState.checking;
    final r = _results[id];
    if (r == null) return null;
    return r == TestResult.ok ? AccountState.connected : AccountState.absent;
  }

  /// Every account tried so far failed to answer at all.
  bool get offline =>
      _results.isNotEmpty &&
      _results.values.every((r) => r == TestResult.unreachable);

  /// A sync is running for at least one account.
  bool get syncing => _syncing.isNotEmpty;

  /// "Tester": a throw-away source built from the form, nothing saved.
  /// [id]: the account being edited (its stored password is used when the field is empty).
  Future<TestResult> testDraft(AccountDraft d, {String? id}) async {
    var password = d.password;
    if (password.isEmpty && id != null) {
      password = await accounts.password(id) ?? '';
    }
    final custom = _draftSource;
    if (custom != null) return _timed(custom(d, password));
    final client = http.Client();
    try {
      return await _timed(
        SubsonicSource(
          accountId: id ?? 'draft',
          base: d.base!,
          user: d.user.trim(),
          password: password,
          headers: d.headers,
          client: client,
        ),
      );
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
    } on Exception {
      return TestResult.unreachable;
    }
  }

  /// "Enregistrer": adds (or updates [editing]), then syncs in the background.
  /// An empty password on an edit keeps the stored one.
  Future<Account> save(AccountDraft d, {Account? editing}) async {
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
        type: d.type,
        name: d.displayName,
        base: base,
        user: d.user.trim(),
        order: editing.order,
      );
      await accounts.update(
        a,
        password: d.password.isEmpty ? null : d.password,
        headers: d.headers,
      );
      resolver?.invalidate(a.id); // new address, password or headers
      _results.remove(a.id);
    }
    unawaited(sync(a.id));
    return a;
  }

  /// Removes the account and its tracks from this phone (nothing on the server).
  Future<void> remove(String id) async {
    await accounts.remove(id);
    resolver?.invalidate(id);
    _results.remove(id);
    _checking.remove(id);
    notifyListeners();
  }

  /// Light test() of each account (accounts screen opening); syncing ones are skipped.
  Future<void> checkAll(Iterable<String> ids) => Future.wait([
    for (final id in ids)
      if (!_syncing.containsKey(id) && _checking.add(id)) _check(id),
  ]).then((_) {});

  Future<void> _check(String id) async {
    notifyListeners();
    TestResult r;
    try {
      r = await _timed(await _sourceOf(id));
    } catch (_) {
      r = TestResult.unreachable; // unsupported type, missing password…
    }
    _checking.remove(id);
    _results[id] = r;
    notifyListeners();
  }

  /// Copies the server library to the phone; an interrupted sync asks the server why.
  Future<void> sync(String id) =>
      _syncing[id] ??= _runSync(id).whenComplete(() {
        _syncing.remove(id);
        notifyListeners();
      });

  Future<void> _runSync(String id) async {
    notifyListeners();
    TestResult r;
    try {
      final s = await _sourceOf(id);
      final done = await _sync(s);
      r = done.complete ? TestResult.ok : await _timed(s);
    } catch (_) {
      r = TestResult.unreachable;
    }
    _results[id] = r;
  }

  /// Launch and pull-to-refresh.
  Future<void> syncAll() async {
    final list = await accounts.watch().first;
    await Future.wait([for (final a in list) sync(a.id)]);
  }
}
