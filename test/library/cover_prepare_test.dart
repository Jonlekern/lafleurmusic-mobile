import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lafleurmusic/library/cover_prepare.dart';

void main() {
  test('image géante réduite à 1000 px, en JPEG', () async {
    final big = Uint8List.fromList(
      img.encodePng(img.Image(width: 4000, height: 3000)),
    );
    final out = await prepareCover(big);
    final dec = img.decodeJpg(out!)!;
    expect(dec.width, 1000);
    expect(dec.height, 1000);
  });
  test('petite image PNG convertie en JPEG sans agrandir', () async {
    final small = Uint8List.fromList(
      img.encodePng(img.Image(width: 400, height: 400)),
    );
    final dec = img.decodeJpg((await prepareCover(small))!)!;
    expect(dec.width, 400);
  });
  test('pas une image : null', () async {
    expect(await prepareCover(Uint8List.fromList([1, 2, 3])), isNull);
  });
}
