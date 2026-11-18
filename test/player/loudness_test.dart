import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/library/db.dart';
import 'package:lafleurmusic/library/models.dart';
import 'package:lafleurmusic/player/loudness.dart';
import 'package:lafleurmusic/player/player.dart';
import 'package:lafleurmusic/player/queue.dart';

import '../ui/fake_player.dart';

Track t(String p, {int mtime = 1}) => Track(
  path: p,
  folderId: 1,
  title: p,
  artist: '',
  album: 'A',
  durationMs: 1000,
  hasCover: false,
  mtime: mtime,
  size: 1,
);

void main() {
  test('gain : −18 LUFS visés, borné à ±12 dB', () {
    expect(gainFor(-8), -10);
    expect(gainFor(-40), 12);
    expect(gainFor(-18), 0);
    expect(gainFor(null), 0);
  });

  late LibraryDb db;
  late FakePlayer player;
  late List<String> measured;
  late Map<String, double?> values;
  late LoudnessService svc;

  setUp(() {
    db = LibraryDb(NativeDatabase.memory());
    player = FakePlayer();
    measured = [];
    values = {'/a': -8, '/b': -24, '/c': null};
    svc = LoudnessService(
      db,
      player,
      measure: (p) async {
        measured.add(p);
        return values[p];
      },
    );
  });
  tearDown(() async {
    svc.dispose();
    await db.close();
  });

  Future<void> idle() => Future<void>.delayed(const Duration(milliseconds: 20));

  test('allumé : mesuré une fois, gain appliqué au début du morceau suivant (jamais en plein morceau)', () async {
    svc.enabled = true;
    player.show(PlayerState(track: t('/a')));
    await idle();
    expect(measured, ['/a']);
    expect(
      player.trackGain,
      0,
    ); // /a joue sans correction : mesure finie en cours de route
    expect(await db.loudnessOf('/a', 1), -8);
    player.show(PlayerState(track: t('/b')));
    await idle();
    expect(player.trackGain, 0);
    player.show(PlayerState(track: t('/a')));
    await idle();
    expect(measured, ['/a', '/b']); // /a pas remesuré
    expect(player.trackGain, -10);
  });

  Track server(String song, double? rg) => Track(
    path: 'subsonic://acc1/$song',
    accountId: 'acc1',
    remoteId: song,
    title: song,
    artist: '',
    album: 'A',
    durationMs: 1000,
    hasCover: false,
    replayGain: rg,
    size: 1,
  );

  test('morceau du serveur : ReplayGain du serveur, jamais sondé', () async {
    svc.enabled = true;
    player.show(PlayerState(track: server('s1', -6.5)));
    await idle();
    expect(measured, isEmpty);
    expect(player.trackGain, -6.5);
    player.show(PlayerState(track: server('s2', null)));
    await idle();
    expect(player.trackGain, 0); // pas de ReplayGain : pas de correction
    player.show(PlayerState(track: server('s3', 20)));
    await idle();
    expect(player.trackGain, 12); // borné
    expect(measured, isEmpty);
    expect(await svc.gainOf(server('s1', -6.5)), -6.5);
    svc.enabled = false;
    expect(await svc.gainOf(server('s1', -6.5)), 0);
  });

  test('file d’attente : les morceaux du serveur ne sont pas sondés', () async {
    svc.enabled = true;
    player.queue = PlayQueue([t('/a'), server('s1', -3), t('/b')], index: 0);
    player.show(PlayerState(track: t('/a')));
    await idle();
    expect(measured, ['/a', '/b']);
  });

  test('gainOf : gain connu d’un morceau (pour le fondu)', () async {
    svc.enabled = true;
    await db.setLoudness('/b', -24, 1);
    expect(await svc.gainOf(t('/b')), 6);
    expect(await svc.gainOf(t('/a')), 0);
    svc.enabled = false;
    expect(await svc.gainOf(t('/b')), 0);
  });

  test('fichier modifié (mtime) → remesuré', () async {
    svc.enabled = true;
    player.show(PlayerState(track: t('/a')));
    await idle();
    player.show(PlayerState(track: t('/a', mtime: 2)));
    await idle();
    expect(measured, ['/a', '/a']);
  });

  test('non mesurable : noté, plus retenté, sans correction', () async {
    svc.enabled = true;
    player.show(PlayerState(track: t('/c')));
    await idle();
    player.show(PlayerState(track: t('/b')));
    await idle();
    player.show(PlayerState(track: t('/c')));
    await idle();
    expect(measured.where((p) => p == '/c').length, 1);
    expect(player.trackGain, 0);
    expect(await db.hasLoudness('/c', 1), isTrue);
  });

  test('les prochains de la file sont mesurés d’avance', () async {
    player.queue = PlayQueue([t('/a'), t('/b'), t('/c')]);
    player.current = PlayerState(track: t('/a'));
    svc.enabled = true;
    await idle();
    await idle();
    expect(measured, ['/a', '/b', '/c']);
  });

  test('éteint : plus de correction, plus de mesure', () async {
    svc.enabled = true;
    player.show(PlayerState(track: t('/a')));
    await idle();
    svc.enabled = false;
    expect(player.trackGain, 0);
    player.show(PlayerState(track: t('/b')));
    await idle();
    expect(measured, ['/a']);
  });

  test('morceau du serveur avec copie : mesuré (EBU R128) sur le fichier, clé = chemin du fichier', () async {
    svc = LoudnessService(
      db,
      player,
      measure: (p) async {
        measured.add(p);
        return -8;
      },
      copyOf: (p) async => p == 'subsonic://acc1/s1' ? '/root/A/s1.mp3' : null,
    );
    svc.enabled = true;
    player.show(PlayerState(track: server('s1', -3)));
    await idle();
    expect(measured, ['/root/A/s1.mp3']);
    expect(await db.loudnessOf('/root/A/s1.mp3', 0), -8);
    player.show(PlayerState(track: server('s2', -6.5))); // pas de copie : flux
    await idle();
    expect(measured, ['/root/A/s1.mp3']);
    expect(player.trackGain, -6.5);
    player.show(PlayerState(track: server('s1', -3)));
    await idle();
    expect(player.trackGain, -10); // mesure gardée : gain de la copie, pas le ReplayGain
    svc.dispose();
  });
}
