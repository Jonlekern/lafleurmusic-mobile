import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../sources/account_service.dart';

/// Le réseau, vu de loin : de quoi brancher un faux dans les tests.
abstract class WifiProbe {
  Future<bool> isWifi();
  Stream<bool> get changes;
}

/// Wi-Fi ou câble (`connectivity_plus`) ; les données mobiles ne comptent pas.
class ConnectivityWifi implements WifiProbe {
  ConnectivityWifi([Connectivity? c]) : _c = c ?? Connectivity();
  final Connectivity _c;

  static bool _home(List<ConnectivityResult> r) =>
      r.contains(ConnectivityResult.wifi) ||
      r.contains(ConnectivityResult.ethernet);

  @override
  Future<bool> isWifi() async => _home(await _c.checkConnectivity());

  @override
  Stream<bool> get changes => _c.onConnectivityChanged.map(_home);
}

/// « À la maison » : en Wi-Fi et au moins un serveur répond.
/// Les copies du Top 100 ne se font que dans ce cas.
class HomeState extends ChangeNotifier {
  HomeState({required this.wifi, required this.accounts}) {
    accounts.addListener(_update);
    _sub = wifi.changes.listen(_onNetwork);
    unawaited(recheck());
  }

  final WifiProbe wifi;
  final AccountService accounts;
  late final StreamSubscription<bool> _sub;
  bool _onWifi = false;
  bool _verified = false; // les serveurs ont été testés depuis le dernier changement de réseau
  bool _atHome = false;
  bool _disposed = false;
  int _epoch = 0; // un par changement de réseau

  bool get atHome => _atHome;

  /// Relit le réseau et reteste les serveurs (retour au premier plan).
  Future<void> recheck() async {
    bool w;
    try {
      w = await wifi.isWifi();
    } on Object {
      w = false;
    }
    if (w != _onWifi || !_verified) {
      await _onNetwork(w);
    } else {
      await _testServers(); // même réseau : on vérifie sans lâcher « à la maison »
    }
  }

  /// Nouveau réseau : pas « à la maison » tant que les serveurs n'ont pas répondu d'ici.
  Future<void> _onNetwork(bool w) async {
    _onWifi = w;
    _verified = false;
    _epoch++;
    _update();
    if (w) await _testServers();
  }

  Future<void> _testServers() async {
    final epoch = _epoch;
    try {
      await accounts.checkAccounts();
    } on Object {
      // un serveur muet reste « absent »
    }
    if (_disposed || epoch != _epoch) return; // le réseau a encore changé
    _verified = true;
    _update();
  }

  void _update() {
    final now = _onWifi && _verified && accounts.anyConnected;
    if (now == _atHome || _disposed) return;
    _atHome = now;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    accounts.removeListener(_update);
    _sub.cancel();
    super.dispose();
  }
}
