// Le son embarqué dans l'essai sur téléphone (integration_test/fixture_bytes.dart) est bien a.flac.
// S'il change, refaire le fichier :
//   base64 -i test/fixtures/a.flac | fold -w 76 | sed "s/.*/    '&'/"
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../integration_test/fixture_bytes.dart';

void main() {
  test('le son embarqué est identique à test/fixtures/a.flac', () {
    expect(
      base64Decode(aFlacBase64),
      File('test/fixtures/a.flac').readAsBytesSync(),
    );
  });
}
