import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/library/models.dart';
import 'package:lafleurmusic/ui/cover_mosaic.dart';

Track tr(String album, String path, {bool cover = true}) => Track(
  path: path,
  folderId: 1,
  title: path,
  artist: 'A',
  album: album,
  durationMs: 1,
  hasCover: cover,
  mtime: 1,
  size: 1,
);

void main() {
  test(
    '4 albums différents : une pochette de chacun, dans l’ordre de la liste',
    () {
      final list = [
        tr('A', '/a1'),
        tr('A', '/a2'),
        tr('B', '/b1'),
        tr('C', '/c1'),
        tr('D', '/d1'),
        tr('E', '/e1'),
      ];
      expect(mosaicPaths(list), ['/a1', '/b1', '/c1', '/d1']);
    },
  );

  test(
    'un morceau sans pochette est sauté au profit d’un autre du même album',
    () {
      final list = [
        tr('A', '/a1', cover: false),
        tr('A', '/a2'),
        tr('B', '/b1'),
        tr('C', '/c1'),
        tr('D', '/d1'),
      ];
      expect(mosaicPaths(list), ['/a2', '/b1', '/c1', '/d1']);
    },
  );

  test('moins de 4 albums avec pochette : une seule pochette', () {
    final list = [tr('A', '/a1'), tr('B', '/b1'), tr('C', '/c1', cover: false)];
    expect(mosaicPaths(list), ['/a1']);
  });

  test('aucune pochette : rien (la fleur)', () {
    expect(mosaicPaths([tr('A', '/a1', cover: false)]), isEmpty);
  });
}
