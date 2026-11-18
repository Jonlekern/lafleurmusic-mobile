import 'package:lafleurmusic/sources/secret_store.dart';

/// In-memory SecretStore for tests.
class FakeSecretStore implements SecretStore {
  final Map<String, String> data = {};

  @override
  Future<String?> read(String key) async => data[key];

  @override
  Future<void> write(String key, String value) async => data[key] = value;

  @override
  Future<void> delete(String key) async => data.remove(key);
}
