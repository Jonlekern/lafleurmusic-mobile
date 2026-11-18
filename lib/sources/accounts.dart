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
    final count = await _db.accountRows.count().getSingle();
    await _secrets.write(_pwKey(id), password);
    await _secrets.write(_hdrKey(id), jsonEncode(headers));
    await _db.into(_db.accountRows).insert(AccountRowsCompanion.insert(
          id: id,
          type: type.name,
          name: name,
          base: base.toString(),
          user: user,
          position: count,
        ));
    return Account(
        id: id, type: type, name: name, base: base, user: user, order: count);
  }

  /// Updates the row fields from [a]; password/headers are rewritten only when given.
  Future<void> update(
    Account a, {
    String? password,
    Map<String, String>? headers,
  }) async {
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

  /// Erases the account row and its secrets. Deleting its tracks is wired in task 6
  /// (the tracks table has no account column yet).
  Future<void> remove(String id) async {
    await _secrets.delete(_pwKey(id));
    await _secrets.delete(_hdrKey(id));
    await (_db.delete(_db.accountRows)..where((t) => t.id.equals(id))).go();
  }

  Future<void> reorder(List<String> ids) => _db.transaction(() async {
        for (var i = 0; i < ids.length; i++) {
          await (_db.update(_db.accountRows)..where((t) => t.id.equals(ids[i])))
              .write(AccountRowsCompanion(position: Value(i)));
        }
      });

  /// [client] is for tests.
  Future<MusicSource> source(String id, {http.Client? client}) async {
    final r = await (_db.select(_db.accountRows)
          ..where((t) => t.id.equals(id)))
        .getSingle();
    final a = _from(r);
    switch (a.type) {
      case AccountType.subsonic:
        final hdr = await _secrets.read(_hdrKey(id));
        return SubsonicSource(
          accountId: id,
          base: a.base,
          user: a.user,
          password: await _secrets.read(_pwKey(id)) ?? '',
          headers: hdr == null
              ? const {}
              : (jsonDecode(hdr) as Map).cast<String, String>(),
          client: client,
        );
      case AccountType.jellyfin:
      case AccountType.plex:
        throw UnsupportedError('${a.type.name} is not supported yet');
    }
  }
}
