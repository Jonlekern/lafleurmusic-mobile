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

  /// What the servers answer when tested from the current network.
  bool answers = false;
  int tests = 0;
  @override
  bool get anyConnected => connected;
  @override
  Future<void> checkAccounts() async {
    tests++;
    await Future<void>.delayed(Duration.zero);
    flip(answers);
  }

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
    service.answers = true;
    wifi.set(true); // reaching home: the servers are tested again
    await settle();
    await settle();
    expect(home.atHome, isTrue);
    wifi.set(false); // Wi-Fi lost: not home at once
    await Future<void>.microtask(() {});
    expect(home.atHome, isFalse);
    expect(seen, [true, false]);
    home.dispose();
  });

  test('launched on mobile data, then home Wi-Fi: servers retested', () async {
    final wifi = FakeWifi(false);
    final home = HomeState(wifi: wifi, accounts: service);
    await settle();
    service.connected = false; // the launch test failed on mobile data
    service.answers = true; // from home the server answers
    wifi.set(true);
    await settle();
    await settle();
    expect(service.tests, 1);
    expect(home.atHome, isTrue);
    home.dispose();
  });

  test('another Wi-Fi: a stale ok does not keep us at home', () async {
    final wifi = FakeWifi(true);
    service.answers = true;
    final home = HomeState(wifi: wifi, accounts: service);
    await settle();
    await settle();
    expect(home.atHome, isTrue);
    service.answers = false; // the new network can't reach the server
    wifi.set(true);
    await Future<void>.microtask(() {});
    expect(home.atHome, isFalse, reason: 'unverified until tested');
    await settle();
    await settle();
    expect(home.atHome, isFalse);
    home.dispose();
  });

  test('resume on the same network retests without leaving home', () async {
    service.answers = true;
    final home = HomeState(wifi: FakeWifi(true), accounts: service);
    await settle();
    await settle();
    final before = service.tests;
    final seen = <bool>[];
    home.addListener(() => seen.add(home.atHome));
    await home.recheck();
    await settle();
    expect(service.tests, before + 1);
    expect(home.atHome, isTrue);
    expect(seen, isNot(contains(false)));
    home.dispose();
  });
}
