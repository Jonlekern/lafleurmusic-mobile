import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/player/media_resolver.dart';
import 'package:lafleurmusic/player/mpv_port.dart';
import 'package:lafleurmusic/sources/source.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

/// Faux mpv : sa liste, avec la sémantique de playlist-move (« to » = le morceau devant lequel on se place).
class _FakeMpv implements Player {
  final list = <String>[];
  @override
  Future<void> openAll(List<Media> medias, {bool? play, int index = 0}) async {
    list
      ..clear()
      ..addAll(medias.map((m) => m.uri));
  }

  @override
  Future<void> add(Media media) async => list.add(media.uri);
  @override
  Future<void> move(int from, int to) async {
    final m = list.removeAt(from);
    list.insert(to > from ? to - 1 : to, m);
  }

  @override
  Future<void> remove(int index) async => list.removeAt(index);
  @override
  Future<void> jump(int index) async {}
  @override
  Future<void> replace(int index, Media media) async => list[index] = media.uri;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Source implements MusicSource {
  _Source(this.accountId);
  @override
  final String accountId;
  @override
  Uri streamUri(String songId) => Uri.parse('https://srv/$songId');
  @override
  Map<String, String> get headers => const {};
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  late _FakeMpv mpv;
  late Completer<void> slow;
  late PlayerPort port;
  setUp(() {
    mpv = _FakeMpv();
    slow = Completer<void>();
    // 1re ouverture d'un compte : base + trousseau, lente
    port = PlayerPort(
      mpv,
      MediaResolver((id) async {
        await slow.future;
        return _Source(id);
      }),
    );
  });

  test('Lire ensuite B (serveur, lent) puis A (local) : mpv dans l’ordre de la file', () async {
    await port.openAll(['/cur.flac'], 0);
    // la file applique les deux tout de suite : cur, A, B
    final b = port.insertAt(1, 'subsonic://acc1/B');
    final a = port.insertAt(1, '/A.flac');
    await Future<void>.delayed(const Duration(milliseconds: 10));
    slow.complete();
    await Future.wait([a, b]);
    expect(mpv.list, ['/cur.flac', '/A.flac', 'https://srv/B']);
  });

  test(
    'openAll (lent) puis insertAt aussitôt : l’ajout n’est pas perdu',
    () async {
      final open = port.openAll(['subsonic://acc1/X', '/Y.flac'], 0);
      final ins = port.insertAt(1, '/Z.flac');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      slow.complete();
      await Future.wait([open, ins]);
      expect(mpv.list, ['https://srv/X', '/Z.flac', '/Y.flac']);
    },
  );

  test('une opération qui échoue ne bloque pas les suivantes', () async {
    slow.complete();
    await port.openAll(['/a.flac'], 0);
    await expectLater(port.remove(5), throwsA(anything));
    await port.insertAt(1, '/b.flac');
    expect(mpv.list, ['/a.flac', '/b.flac']);
  });
}
