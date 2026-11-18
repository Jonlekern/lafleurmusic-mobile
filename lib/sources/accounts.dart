import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:http/http.dart' as http;

import '../library/db.dart';
import 'secret_store.dart';
import 'source.dart';
import 'subsonic.dart';

enum AccountType { subsonic, jellyfin, plex }

class Account {
  const Account({
    required this.id,
    required this.type,
    required this.name,
    required this.base,
    required this.user,
    required this.order,
  });
  final String id;
  final AccountType type;
  final String name;
  final Uri base;
  final String user;
  final int order;
}

/// Server accounts. Rows hold no secret; password and headers live in [SecretStore].
class Accounts {
  Accounts(this._db, this._secrets);
  final LibraryDb _db;
  final SecretStore _secrets;

  static String _pwKey(String id) => 'account.$id.password';
  static String _hdrKey(String id) => 'account.$id.headers';

  static Account _from(AccountRow r) => Account(
    id: r.id,
    type: AccountType.values.byName(r.type),
    name: r.name,
    base: Uri.parse(r.base),
    user: r.user,
    order: r.position,
  );

  static String _newId() {
    final rnd = Random.secure();
    return List.generate(16, (_) => rnd.nextInt(16).toRadixString(16)).join();
  }

  Stream<List<Account>> watch() {
    final q = _db.select(_db.accountRows)
      ..orderBy([(t) => OrderingTerm.asc(t.position)]);
    return q.watch().map((rows) => rows.map(_from).toList());
  }

  Future<Account> add({
    required AccountType type,
    required String name,
    required Uri base,
    required String user,
    required String password,
    Map<String, String> headers = const {},
  }) async {
    final id = _newId();
    final order = await _nextPosition();
    try {
      await _secrets.write(_pwKey(id), password);
      await _secrets.write(_hdrKey(id), jsonEncode(headers));
      await _db
          .into(_db.accountRows)
          .insert(
            AccountRowsCompanion.insert(
              id: id,
              type: type.name,
              name: name,
              base: base.toString(),
              user: user,
              position: order,
            ),
          );
    } catch (_) {
      await _deleteSecrets(id); // no orphan secret left in the keychain
      rethrow;
    }
    return Account(
      id: id,
      type: type,
      name: name,
      base: base,
      user: user,
      order: order,
    );
  }

  Future<int> _nextPosition() async {
    final m = _db.accountRows.position.max();
    final r = await (_db.selectOnly(
      _db.accountRows,
    )..addColumns([m])).getSingle();
    final v = r.read(m);
    return v == null ? 0 : v + 1;
  }

  Future<void> _deleteSecrets(String id) async {
    // each delete is tried even if the other fails; errors are swallowed on cleanup
    for (final k in [_pwKey(id), _hdrKey(id)]) {
      try {
        await _secrets.delete(k);
      } catch (_) {}
    }
  }

  /// Updates the row fields from [a]; password/headers are rewritten only when given.
  Future<void> update(
    Account a, {
    String? password,
    Map<String, String>? headers,
  }) async {
    final exists = await (_db.select(
      _db.accountRows,
    )..where((t) => t.id.equals(a.id))).getSingleOrNull();
    if (exists == null) throw StateError('Unknown account ${a.id}');
    if (password != null) await _secrets.write(_pwKey(a.id), password);
    if (headers != null) {
      await _secrets.write(_hdrKey(a.id), jsonEncode(headers));
    }
    await (_db.update(_db.accountRows)..where((t) => t.id.equals(a.id))).write(
      AccountRowsCompanion(
        type: Value(a.type.name),
        name: Value(a.name),
        base: Value(a.base.toString()),
        user: Value(a.user),
      ),
    );
  }

  /// Erases the account row, its tracks and its secrets. [root]: see [LibraryDb.dropServerTracks]
  /// (kept copies stay as local tracks).
  Future<void> remove(String id, {required CopyRoot? root}) async {
    // row first: a leftover secret is invisible, a row without secrets is a broken account
    await _db.transaction(() async {
      await (_db.delete(_db.accountRows)..where((t) => t.id.equals(id))).go();
      await _db.deleteAccountTracks(id, root: root);
      await (_db.delete(
        _db.pendingScrobbles,
      )..where((p) => p.accountId.equals(id))).go();
    });
    await _secrets.delete(_pwKey(id));
    await _secrets.delete(_hdrKey(id));
  }

  /// Listed accounts first (unknown and duplicate ids ignored), the others after, in their old order.
  Future<void> reorder(List<String> ids) => _db.transaction(() async {
    final current = await (_db.select(
      _db.accountRows,
    )..orderBy([(t) => OrderingTerm.asc(t.position)])).get();
    final known = current.map((r) => r.id).toSet();
    final seen = <String>{};
    final order = [
      for (final id in ids)
        if (known.contains(id) && seen.add(id)) id,
      for (final r in current)
        if (seen.add(r.id)) r.id,
    ];
    for (var i = 0; i < order.length; i++) {
      await (_db.update(_db.accountRows)..where((t) => t.id.equals(order[i])))
          .write(AccountRowsCompanion(position: Value(i)));
    }
  });

  /// Stored password (the edit form tests with it when its password field is left empty).
  Future<String?> password(String id) => _secrets.read(_pwKey(id));

  /// Stored HTTP headers (prefilled in the edit form).
  Future<Map<String, String>> headers(String id) async {
    final hdr = await _secrets.read(_hdrKey(id));
    return hdr == null
        ? const {}
        : (jsonDecode(hdr) as Map).cast<String, String>();
  }

  /// [client] is for tests.
  Future<MusicSource> source(String id, {http.Client? client}) async {
    final r = await (_db.select(
      _db.accountRows,
    )..where((t) => t.id.equals(id))).getSingle();
    final a = _from(r);
    switch (a.type) {
      case AccountType.subsonic:
        final pw = await _secrets.read(_pwKey(id));
        if (pw == null) throw StateError('Missing password for account $id');
        return SubsonicSource(
          accountId: id,
          base: a.base,
          user: a.user,
          password: pw,
          headers: await headers(id),
          client: client,
        );
      case AccountType.jellyfin:
      case AccountType.plex:
        throw UnsupportedError('${a.type.name} is not supported yet');
    }
  }
}
