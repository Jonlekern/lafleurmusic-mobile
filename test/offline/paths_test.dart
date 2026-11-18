import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/offline/paths.dart';

void main() {
  group('safeName', () {
    test('forbidden characters become _', () {
      expect(safeName('AC/DC'), 'AC_DC');
      expect(safeName(r'a\b:c*d"e<f>g|h'), 'a_b_c_d_e_f_g_h');
      expect(safeName('Who?'), 'Who_');
    });
    test('trailing dots and spaces are removed', () {
      expect(safeName('Album.'), 'Album');
      expect(safeName('Album . . '), 'Album');
    });
    test('empty, dots only or control characters', () {
      expect(safeName(''), '_');
      expect(safeName('...'), '___');
      expect(safeName('..'), '__');
      expect(safeName('a\u0000b\n'), 'a_b_');
    });
    test('emoji kept', () {
      expect(safeName('Love 😀 Song'), 'Love 😀 Song');
    });
    test('300 characters: 120 bytes max, no split character', () {
      final long = safeName('é' * 300);
      expect(utf8.encode(long).length, lessThanOrEqualTo(120));
      expect(long, 'é' * 60);
      final emoji = safeName('😀' * 100);
      expect(utf8.encode(emoji).length, lessThanOrEqualTo(120));
      expect(emoji, '😀' * 30);
      expect(safeName('a' * 300).length, 120);
    });
    test('path traversal stays inside one segment', () {
      final s = safeName('../../etc');
      expect(s.contains('/'), false);
      expect(s, '___.._etc'); // leading dots would hide the folder
    });
  });

  group('keptPath', () {
    test('artist/album/NN title.ext', () {
      expect(
        keptPath(
          albumArtist: 'AC/DC',
          album: 'Back in Black',
          track: 3,
          title: 'Hells Bells',
          ext: 'mp3',
        ),
        'AC_DC/Back in Black/03 Hells Bells.mp3',
      );
    });
    test('disc above 1 gives D-NN; disc 1 or unknown does not', () {
      String p(int? disc) => keptPath(
        albumArtist: 'A',
        album: 'B',
        disc: disc,
        track: 7,
        title: 'T',
        ext: 'flac',
      );
      expect(p(2), 'A/B/2-07 T.flac');
      expect(p(1), 'A/B/07 T.flac');
      expect(p(null), 'A/B/07 T.flac');
    });
    test('unknown number: title alone', () {
      expect(
        keptPath(albumArtist: 'A', album: 'B', title: 'T', ext: 'mp3'),
        'A/B/T.mp3',
      );
    });
    test('empty artist uses the given placeholder', () {
      expect(
        keptPath(
          albumArtist: '',
          album: 'B',
          title: 'T',
          ext: 'mp3',
          unknownArtist: 'Artiste inconnu',
        ),
        'Artiste inconnu/B/T.mp3',
      );
      expect(
        keptPath(albumArtist: ' ', album: 'B', title: 'T', ext: 'mp3'),
        startsWith('Unknown artist/'),
      );
    });
    test('hostile names never leave the root', () {
      final p = keptPath(
        albumArtist: '../../etc',
        album: '..',
        title: '../passwd',
        ext: 'mp3',
      );
      expect(p.split('/').length, 3);
      expect(p.split('/').any((s) => s == '..' || s == '.'), false);
    });
    test('extension is sanitised and the whole name stays short', () {
      final p = keptPath(
        albumArtist: 'A',
        album: 'B',
        track: 1,
        title: 'x' * 300,
        ext: '.MP3/',
      );
      final file = p.split('/').last;
      expect(file.endsWith('.MP3_'), true);
      expect(utf8.encode(file).length, lessThanOrEqualTo(255));
    });
  });

  group('uniquePath', () {
    test('free path unchanged', () {
      expect(uniquePath('A/B/T.mp3', (_) => false), 'A/B/T.mp3');
    });
    test('duplicates get (2), (3)', () {
      final taken = {'A/B/T.mp3', 'A/B/T (2).mp3'};
      expect(uniquePath('A/B/T.mp3', taken.contains), 'A/B/T (3).mp3');
    });
    test('name without extension', () {
      expect(uniquePath('A/T', {'A/T'}.contains), 'A/T (2)');
    });
  });
}
