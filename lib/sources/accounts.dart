import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:http/http.dart' as http;

import '../library/db.dart';
import 'secret_store.dart';
import 'source.dart';
import 'jellyfin.dart';
import 'plex.dart';
import 'plex_link.dart';
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
  // Jellyfin's token and user id: gone with the account, and when a sign-in detail changes
  static List<String> _tokenKeys(String id) => [
    JellyfinSource.tokenKey(id),
    JellyfinSource.userIdKey(id),
  ];
  // Plex's token and server: replaced only by a new code (an edit can't change them), gone
  // with the account
  static List<String> _plexKeys(String id) => [
    PlexSource.tokenKey(id),
    PlexSource.serverKey(id),
    PlexSource.accountTokenKey(id),
    PlexSource.userKey(id),
  ];

  /// `X-Plex-Client-Identifier`: one per install, kept when accounts go.
  static const plexClientIdKey = 'plex.clientIdentifier';

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
    Map<String, String> Function(String id)? moreSecrets,
  }) async {
    final id = _newId();
    final order = await _nextPosition();
    try {
      await _secrets.write(_pwKey(id), password);
      await _secrets.write(_hdrKey(id), jsonEncode(headers));
      for (final e in (moreSecrets?.call(id) ?? const {}).entries) {
        await _secrets.write(e.key, e.value);
      }
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

  /// A Plex account found by a code: [token] and [server] (its addresses) in the store; the
  /// row's address is [base], the best one when it was added (shown in the list).
  /// [accountToken]: the plex.tv token (reads the addresses again when they go stale);
  /// [plexUser]: who the account is on plex.tv (a later new code must be the same).
  Future<Account> addPlex({
    required String name,
    required PlexServer server,
    required String token,
    required Uri base,
    String? accountToken,
    String? plexUser,
  }) => add(
    type: AccountType.plex,
    name: name,
    base: base,
    user: '',
    password: '',
    moreSecrets: (id) => {
      PlexSource.tokenKey(id): token,
      PlexSource.serverKey(id): jsonEncode(server.toJson()),
      PlexSource.accountTokenKey(id): ?accountToken,
      PlexSource.userKey(id): ?plexUser,
    },
  );

  /// « Nouveau code »: the same account (id, tracks, keys) with a new token and fresh addresses.
  Future<void> relinkPlex(
    String id, {
    required PlexServer server,
    required String token,
    required Uri base,
    String? accountToken,
    String? plexUser,
  }) async {
    final row = await (_db.select(
      _db.accountRows,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null || row.type != AccountType.plex.name) {
      throw StateError('Unknown Plex account $id');
    }
    await _secrets.write(PlexSource.tokenKey(id), token);
    await _secrets.write(PlexSource.serverKey(id), jsonEncode(server.toJson()));
    if (accountToken != null) {
      await _secrets.write(PlexSource.accountTokenKey(id), accountToken);
    }
    if (plexUser != null) {
      await _secrets.write(PlexSource.userKey(id), plexUser);
    }
    await (_db.update(_db.accountRows)..where((t) => t.id.equals(id))).write(
      AccountRowsCompanion(base: Value(base.toString())),
    );
  }

  /// The Plex server of account [id] (its id and addresses), or null.
  Future<PlexServer?> plexServer(String id) async {
    final j = await _secrets.read(PlexSource.serverKey(id));
    return j == null ? null : PlexServer.fromJson(jsonDecode(j));
  }

  /// Who account [id] is on plex.tv (its `uuid`), or null when not known.
  Future<String?> plexUser(String id) => _secrets.read(PlexSource.userKey(id));

  /// This install's `X-Plex-Client-Identifier`, made on first use.
  Future<String> plexClientId() async {
    final known = await _secrets.read(plexClientIdKey);
    if (known != null && known.isNotEmpty) return known;
    final rnd = Random.secure();
    final id = List.generate(
      32,
      (_) => rnd.nextInt(16).toRadixString(16),
    ).join();
    await _secrets.write(plexClientIdKey, id);
    return id;
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
    for (final k in [
      _pwKey(id),
      _hdrKey(id),
      ..._tokenKeys(id),
      ..._plexKeys(id),
    ]) {
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
    // new address, name or password: the old token proves nothing, sign in again
    if (password != null ||
        a.base.toString() != exists.base ||
        a.user != exists.user) {
      for (final k in _tokenKeys(a.id)) {
        try {
          await _secrets.delete(k);
        } catch (
          _
        ) {} // a leftover token is refused and replaced at the next sign-in
      }
    }
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
      await _db.deleteAccountPlaylists(id);
      await (_db.delete(
        _db.pendingScrobbles,
      )..where((p) => p.accountId.equals(id))).go();
    });
    await _secrets.delete(_pwKey(id));
    await _secrets.delete(_hdrKey(id));
    for (final k in [..._tokenKeys(id), ..._plexKeys(id)]) {
      await _secrets.delete(k);
    }
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
        // the account's own password entry: signing in again after a revoked token needs it
        final pw = await _secrets.read(_pwKey(id));
        if (pw == null) throw StateError('Missing password for account $id');
        return JellyfinSource(
          accountId: id,
          base: a.base,
          user: a.user,
          password: pw,
          headers: await headers(id),
          client: client,
          secrets: _secrets,
        );
      case AccountType.plex:
        final server = await plexServer(id);
        if (server == null) throw StateError('Missing server for account $id');
        return PlexSource(
          accountId: id,
          server: server,
          clientId: await plexClientId(),
          headers: await headers(id),
          client: client,
          secrets: _secrets,
        );
    }
  }
}
