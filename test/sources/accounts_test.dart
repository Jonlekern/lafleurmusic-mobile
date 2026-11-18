import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lafleurmusic/library/db.dart';
import 'package:lafleurmusic/sources/accounts.dart';
import 'package:lafleurmusic/sources/subsonic.dart';

import 'fake_secret_store.dart';

void main() {
  late LibraryDb db;
  late FakeSecretStore secrets;
  late Accounts accounts;

  setUp(() {
    db = LibraryDb(NativeDatabase.memory());
    secrets = FakeSecretStore();
    accounts = Accounts(db, secrets);
  });
  tearDown(() => db.close());

  Future<Account> addOne(String name, {Map<String, String>? headers}) =>
      accounts.add(
        type: AccountType.subsonic,
        name: name,
        base: Uri.parse('https://music.example.com'),
        user: 'johnny',
        password: 'S3cret-pw',
        headers: headers ?? const {'CF-Access-Client-Secret': 'hdr-value-42'},
      );

  test('add keeps password and headers in the store, never in the database',
      () async {
    final a = await addOne('Home');
    expect(secrets.data['account.${a.id}.password'], 'S3cret-pw');
    expect(jsonDecode(secrets.data['account.${a.id}.headers']!),
        {'CF-Access-Client-Secret': 'hdr-value-42'});
    expect(a.id, matches(RegExp(r'^[0-9a-f]{16}$')));

    final rows = await db.customSelect('SELECT * FROM accounts').get();
    expect(rows, hasLength(1));
    final dump = jsonEncode(rows.single.data);
    expect(dump, contains('johnny'));
    expect(dump, isNot(contains('S3cret-pw')));
    expect(dump, isNot(contains('hdr-value-42')));
    expect(dump, isNot(contains('CF-Access-Client-Secret')));
  });

  test('remove erases the secrets and the row', () async {
    final a = await addOne('Home');
    await accounts.remove(a.id);
    expect(secrets.data, isEmpty);
    expect(await accounts.watch().first, isEmpty);
  });

  test('new accounts go last; reorder changes watch() order', () async {
    final a = await addOne('a');
    final b = await addOne('b');
    expect((await accounts.watch().first).map((x) => x.id), [a.id, b.id]);
    await accounts.reorder([b.id, a.id]);
    final list = await accounts.watch().first;
    expect(list.map((x) => x.id), [b.id, a.id]);
    expect(list.map((x) => x.order), [0, 1]);
  });

  test('update changes password and headers in the store only', () async {
    final a = await addOne('Home');
    await accounts.update(a, password: 'new-pw', headers: {'X-K': 'v'});
    expect(secrets.data['account.${a.id}.password'], 'new-pw');
    expect(jsonDecode(secrets.data['account.${a.id}.headers']!), {'X-K': 'v'});
    final c = Account(
        id: a.id,
        type: a.type,
        name: 'Renamed',
        base: Uri.parse('https://other.example.com'),
        user: 'jo',
        order: a.order);
    await accounts.update(c);
    final got = (await accounts.watch().first).single;
    expect(got.name, 'Renamed');
    expect(got.base, Uri.parse('https://other.example.com'));
    expect(got.user, 'jo');
    expect(secrets.data['account.${a.id}.password'], 'new-pw');
  });

  test('source() builds a Subsonic source sending the saved headers',
      () async {
    final a = await addOne('Home');
    final seen = <http.BaseRequest>[];
    final src = await accounts.source(a.id, client: MockClient((r) async {
      seen.add(r);
      return http.Response(
          '{"subsonic-response":{"status":"ok","version":"1.16.1"}}', 200,
          headers: {'content-type': 'application/json'});
    }));
    expect(src, isA<SubsonicSource>());
    await src.test();
    expect(seen, isNotEmpty);
    expect(seen.first.headers['CF-Access-Client-Secret'], 'hdr-value-42');
    expect(seen.first.url.host, 'music.example.com');
  });

  test('source() for jellyfin/plex is unsupported for now', () async {
    final a = await accounts.add(
        type: AccountType.jellyfin,
        name: 'J',
        base: Uri.parse('https://j.example.com'),
        user: 'u',
        password: 'p');
    expect(() => accounts.source(a.id), throwsUnsupportedError);
  });
}
