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
    _sub = wifi.changes.listen((w) {
      _onWifi = w;
      _update();
    });
    unawaited(
      wifi.isWifi().then((w) {
        _onWifi = w;
        _update();
      }, onError: (_) {}), // inconnu : pas à la maison
    );
  }

  final WifiProbe wifi;
  final AccountService accounts;
  late final StreamSubscription<bool> _sub;
  bool _onWifi = false;
  bool _atHome = false;
  bool _disposed = false;

  bool get atHome => _atHome;

  /// Relit le réseau (retour au premier plan).
  Future<void> recheck() async {
    try {
      _onWifi = await wifi.isWifi();
    } on Object {
      _onWifi = false;
    }
    _update();
  }

  void _update() {
    final now = _onWifi && accounts.anyConnected;
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
