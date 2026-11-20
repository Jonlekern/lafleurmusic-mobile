import 'dart:io';

import 'package:lafleurmusic/offline/device.dart';

/// [Device] for tests: the visible folder ([root]), whether it answers, a Documents folder for
/// `docs://` keys, and the app's private folder ([private], `app://` keys) used for kept songs
/// when [keepInApp].
class FakeDevice implements Device {
  FakeDevice(this.root, {this.docs, this.private});
  Directory root;
  Directory? docs, private;
  bool reachable = true, keepInApp = false;
  int rootReads = 0;
  @override
  Future<Directory> visibleRoot() async {
    rootReads++;
    return root;
  }
  @override
  Future<Directory> keptRoot() async =>
      keepInApp ? await privateRoot() : await visibleRoot();
  @override
  Future<Directory> privateRoot({bool create = true}) async {
    rootReads++;
    return private!;
  }
  @override
  Future<void> setKeepInApp(bool value, {bool forgetFolder = false}) async =>
      keepInApp = value;
  @override
  Future<bool> rootReachable() async => keepInApp || reachable;
  @override
  Future<bool> visibleReachable() async => reachable;
  @override
  Future<String> absolutePath(String key) async {
    if (key.startsWith(docsScheme) && docs != null) {
      return '${docs!.path}/${key.substring(docsScheme.length)}';
    }
    if (key.startsWith(appScheme) && private != null) {
      return '${private!.path}/${key.substring(appScheme.length)}';
    }
    return key;
  }
  @override
  Future<String> keyFor(String a) async {
    final d = docs, pr = private;
    if (pr != null && a.startsWith('${pr.path}/')) {
      return '$appScheme${a.substring(pr.path.length + 1)}';
    }
    return d != null && a.startsWith('${d.path}/')
        ? '$docsScheme${a.substring(d.path.length + 1)}'
        : a;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}
