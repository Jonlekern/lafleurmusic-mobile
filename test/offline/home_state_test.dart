import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/library/db.dart';
import 'package:lafleurmusic/offline/home_state.dart';
import 'package:lafleurmusic/sources/account_service.dart';

import '../sources/fake_secret_store.dart';

import 'package:lafleurmusic/sources/accounts.dart';

class FakeWifi implements WifiProbe {
  FakeWifi(this.wifi);
  bool wifi;
  final _c = StreamController<bool>.broadcast();
  @override
  Future<bool> isWifi() async => wifi;
  @override
  Stream<bool> get changes => _c.stream;
  void set(bool v) {
    wifi = v;
    _c.add(v);
  }
}

class _Service extends AccountService {
  _Service(super.accounts, {required super.db});
  bool connected = false;
  @override
  bool get anyConnected => connected;
  void flip(bool v) {
    connected = v;
    notifyListeners();
  }
}

void main() {
  late LibraryDb db;
  late _Service service;
  setUp(() {
    db = LibraryDb(NativeDatabase.memory());
    service = _Service(Accounts(db, FakeSecretStore()), db: db);
  });
  tearDown(() => db.close());

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('at home only on Wi-Fi with a connected account', () async {
    final wifi = FakeWifi(false);
    final home = HomeState(wifi: wifi, accounts: service);
    final seen = <bool>[];
    home.addListener(() => seen.add(home.atHome));
    await settle();
    expect(home.atHome, isFalse);
    service.flip(true); // server answers, but on mobile data
    expect(home.atHome, isFalse);
    wifi.set(true);
    await settle();
    expect(home.atHome, isTrue);
    service.flip(false); // server lost
    expect(home.atHome, isFalse);
    service.flip(true);
    wifi.set(false);
    await settle();
    expect(home.atHome, isFalse);
    expect(seen, [true, false, true, false]);
    home.dispose();
  });

  test('starting on Wi-Fi with a connected account is home', () async {
    service.connected = true;
    final home = HomeState(wifi: FakeWifi(true), accounts: service);
    await settle();
    expect(home.atHome, isTrue);
    home.dispose();
  });
}
