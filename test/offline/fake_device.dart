import 'dart:io';

import 'package:lafleurmusic/offline/device.dart';

/// [Device] for tests: a folder, whether it answers, and a Documents folder for `docs://` keys.
class FakeDevice implements Device {
  FakeDevice(this.root, {this.docs});
  Directory root;
  Directory? docs;
  bool reachable = true;
  int rootReads = 0;
  @override
  Future<Directory> musicRoot() async {
    rootReads++;
    return root;
  }
  @override
  Future<bool> rootReachable() async => reachable;
  @override
  Future<String> absolutePath(String key) async => key.startsWith(docsScheme) && docs != null
      ? '${docs!.path}/${key.substring(docsScheme.length)}'
      : key;
  @override
  Future<String> keyFor(String a) async {
    final d = docs;
    return d != null && a.startsWith('${d.path}/')
        ? '$docsScheme${a.substring(d.path.length + 1)}'
        : a;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}
