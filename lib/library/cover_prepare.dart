import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Image glissée → pochette carrée JPEG de 1000 px au plus (recadrée au centre), null si ce n'est pas une image.
Future<Uint8List?> prepareCover(Uint8List bytes) => Isolate.run(() {
  final image = img.decodeImage(bytes);
  if (image == null) return null;
  final side = image.width < image.height ? image.width : image.height;
  final size = side > 1000 ? 1000 : side;
  return Uint8List.fromList(
    img.encodeJpg(img.copyResizeCropSquare(image, size: size), quality: 90),
  );
});
