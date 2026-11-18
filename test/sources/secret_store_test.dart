import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/sources/secret_store.dart';

void main() {
  test('iOS keychain: readable after the first unlock (locked-screen playback)', () {
    expect(
      SecureSecretStore.iosOptions.params['accessibility'],
      KeychainAccessibility.first_unlock.name,
    );
  });
}
