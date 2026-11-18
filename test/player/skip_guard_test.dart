import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/library/models.dart';
import 'package:lafleurmusic/player/mpv_port.dart';
import 'package:lafleurmusic/player/queue.dart';
import 'package:lafleurmusic/player/skip_guard.dart';

/// Faux mpv qui joue sa liste : un morceau de [gone] échoue à l'ouverture (stream 404), mpv passe au suivant.
class _MpvSim implements MpvPort {
  _MpvSim(this.gone);
  final Set<String> gone;
  var list = <String>[];
  var index = 0;

  /// Fin du morceau en cours ; mpv avance d'une place.
  FileEnd playCurrent() {
    final how = gone.contains(list[index]) ? FileEnd.error : FileEnd.eof;
    index++;
    return how;
  }

  @override
  Future<void> openAll(List<String> paths, int index) async {
    list = List.of(paths);
    this.index = index;
  }

  @override
  Future<void> insertAt(int at, String path) async => list.insert(at, path);
  @override
  Future<void> move(int from, int to) async =>
      list.insert(to, list.removeAt(from));
  @override
  Future<void> remove(int i) async => list.removeAt(i);
  @override
  Future<void> jump(int i) async => index = i;
  @override
  Future<void> replace(int i, String path) async => list[i] = path;
}

Track _song(String id, String title) => Track(
  path: 'subsonic://acc1/$id',
  accountId: 'acc1',
  remoteId: id,
  title: title,
  artist: 'Lafleur Surf',
  album: 'Summer Mix',
  durationMs: 1000,
  hasCover: false,
  size: 1,
);

void main() {
  test('un avertissement, puis silence pendant 3 s', () {
    var now = DateTime(2026);
    final g = SkipGuard(clock: () => now);
    expect(g.onError(), SkipAction.warn);
    now = now.add(const Duration(seconds: 1));
    expect(g.onError(), SkipAction.quiet);
    g.onPlayed();
    now = now.add(const Duration(seconds: 3));
    expect(g.onError(), SkipAction.warn);
  });
  test('5 fichiers illisibles d’affilée : on arrête (NAS tombé)', () {
    final g = SkipGuard();
    final actions = [for (var i = 0; i < 5; i++) g.onError()];
    expect(actions.last, SkipAction.stop);
    g.onPlayed();
    expect(g.onError(), isNot(SkipAction.stop));
  });

  test('morceau disparu du serveur (404) dans une file de 3 : signalé, on passe au 3e', () async {
    final port = _MpvSim({'subsonic://acc1/s2'});
    final sync = QueueSync<Track>(port, (t) => t.path);
    final q = PlayQueue<Track>([
      _song('s1', 'Summer'),
      _song('s2', 'Night Swim'),
      _song('s3', 'Low Tide'),
    ]);
    await sync.open(q);
    final ends = EndFiles<Track>();
    final skipped = <String>[];
    var stop = false;
    Future<void> step() async {
      final r = ends.ended(q, port.playCurrent());
      if (r.skipped case final t?) skipped.add(t.title);
      stop = stop || r.stop;
      expect(ends.mpvIndex, port.index); // on suit mpv
      await sync.advanced(q, port.index);
    }

    await step(); // Summer jusqu'au bout
    expect(q.current!.title, 'Night Swim');
    expect(skipped, isEmpty);
    await step(); // Night Swim : 404
    expect(skipped, ['Night Swim']);
    expect(q.current!.title, 'Low Tide');
    expect(stop, isFalse);
  });
}
