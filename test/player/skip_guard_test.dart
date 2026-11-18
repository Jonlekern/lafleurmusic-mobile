import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/player/skip_guard.dart';

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
}
