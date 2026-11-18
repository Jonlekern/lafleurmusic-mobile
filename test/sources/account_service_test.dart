import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/library/db.dart';
import 'package:lafleurmusic/sources/account_service.dart';
import 'package:lafleurmusic/sources/accounts.dart';

import 'fake_secret_store.dart';

void main() {
  group('AccountDraft', () {
    AccountDraft d(String address, {String name = '', String pw = 'x'}) =>
        AccountDraft(address: address, user: 'u', name: name, password: pw);

    test('address without scheme gets http://', () {
      expect(
        d('192.168.1.20:4533').base,
        Uri.parse('http://192.168.1.20:4533'),
      );
      expect(
        d(' https://m.example/sub ').base,
        Uri.parse('https://m.example/sub'),
      );
    });

    test('unusable addresses', () {
      expect(d('ftp://m.example').base, isNull);
      expect(d('http://').base, isNull);
      expect(
        d('http://').problem(needsPassword: true),
        DraftProblem.badAddress,
      );
      expect(d('').problem(needsPassword: true), DraftProblem.missing);
    });

    test('password needed only for a new account', () {
      expect(
        d('m.example', pw: '').problem(needsPassword: true),
        DraftProblem.missing,
      );
      expect(d('m.example', pw: '').problem(needsPassword: false), isNull);
    });

    test('empty name falls back to the host', () {
      expect(d('http://192.168.1.20:4533').displayName, '192.168.1.20');
      expect(d('m.example', name: ' Maison ').displayName, 'Maison');
    });
  });

  test('Accounts.password and headers read the stored secrets', () async {
    final db = LibraryDb(NativeDatabase.memory());
    addTearDown(db.close);
    final accounts = Accounts(db, FakeSecretStore());
    final a = await accounts.add(
      type: AccountType.subsonic,
      name: 'N',
      base: Uri.parse('http://h'),
      user: 'u',
      password: 'pw',
      headers: {'X-A': '1'},
    );
    expect(await accounts.password(a.id), 'pw');
    expect(await accounts.headers(a.id), {'X-A': '1'});
    expect(await accounts.headers('nope'), isEmpty);
  });
}
