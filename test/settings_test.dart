import 'dart:io';

import 'package:flutter/painting.dart' show Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/player/equalizer.dart';
import 'package:lafleurmusic/settings.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('set'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('réglages retrouvés après relance', () async {
    final f = File('${dir.path}/settings.json');
    await AppSettings(
      equalizer: Equalizer.named('bass').copyWith(enabled: true),
    ).save(f);
    final back = await AppSettings.load(f);
    expect(back.equalizer.enabled, true);
    expect(back.equalizer.preset, 'bass');
  });
  test('accounts display: defaults to all, saved and read back', () async {
    final f = File('${dir.path}/settings.json');
    final d = AppSettings();
    expect(d.displayMode, DisplayMode.all);
    expect(d.oneAccount, isNull);
    expect(d.customAccounts, isEmpty);
    await (AppSettings()
          ..displayMode = DisplayMode.custom
          ..oneAccount = 'a1'
          ..customAccounts = ['a1', 'a2'])
        .save(f);
    final back = await AppSettings.load(f);
    expect(back.displayMode, DisplayMode.custom);
    expect(back.oneAccount, 'a1');
    expect(back.customAccounts, ['a1', 'a2']);
  });

  test(
    'accounts display: unreadable values fall back to the defaults',
    () async {
      final f = File('${dir.path}/bad.json')
        ..writeAsStringSync(
          '{"displayMode":"nope","oneAccount":3,"customAccounts":["a",1,"b"]}',
        );
      final s = await AppSettings.load(f);
      expect(s.displayMode, DisplayMode.all);
      expect(s.oneAccount, isNull);
      expect(s.customAccounts, ['a', 'b']);
    },
  );

  test('confirmRemove: on by default, saved and read back', () async {
    final f = File('${dir.path}/confirm.json');
    expect(AppSettings().confirmRemove, isTrue);
    await (AppSettings()..confirmRemove = false).save(f);
    expect((await AppSettings.load(f)).confirmRemove, isFalse);
    f.writeAsStringSync('{"confirmRemove":"x"}');
    expect((await AppSettings.load(f)).confirmRemove, isTrue);
  });

  test('fichier absent ou cassé : réglages par défaut', () async {
    expect(
      (await AppSettings.load(File('${dir.path}/rien.json'))).equalizer.enabled,
      false,
    );
    final f = File('${dir.path}/c.json')..writeAsStringSync('{oups');
    expect((await AppSettings.load(f)).equalizer.preset, 'flat');
  });

  test('enregistrements en rafale (curseur glissé) : aucune erreur, la dernière valeur gagne', () async {
    final dir = Directory.systemTemp.createTempSync('set');
    final f = File('${dir.path}/settings.json');
    final s = AppSettings();
    final saves = <Future<void>>[];
    for (var i = 0; i <= 40; i++) {
      s.equalizer = Equalizer.named('flat').withGain(0, i / 4);
      saves.add(s.save(f));
    }
    await Future.wait(saves);
    expect((await AppSettings.load(f)).equalizer.gains[0], 10);
    dir.deleteSync(recursive: true);
  });

  test('Latest : pendant un travail en cours, seul le dernier demandé est fait ensuite', () async {
    final done = <int>[];
    final l = Latest();
    final futures = [
      for (var i = 0; i < 10; i++)
        l.run(() async {
          await Future<void>.delayed(const Duration(milliseconds: 5));
          done.add(i);
        }),
    ];
    await Future.wait(futures);
    expect(done, [0, 9]);
  });

  test('vue Artistes (grille ou liste) retrouvée après relance ; grille par défaut', () async {
    final f = File('${dir.path}/s2.json');
    expect((await AppSettings.load(f)).artistGrid, isTrue);
    await (AppSettings()..artistGrid = false).save(f);
    expect((await AppSettings.load(f)).artistGrid, isFalse);
  });

  test(
    'réglages Winamp : valeurs par défaut, puis retrouvés après relance',
    () async {
      final f = File('${dir.path}/w.json');
      final d = await AppSettings.load(f);
      expect(
        [
          d.skin,
          d.winampDouble,
          d.winampEq,
          d.winampPl,
          d.visMode,
          d.winampMode,
          d.lafleurSize,
        ],
        [null, true, true, true, 0, false, null],
      );
      await (AppSettings()
            ..skin = 'Trinity.wsz'
            ..winampDouble = false
            ..winampEq = false
            ..winampPl = false
            ..visMode = 2
            ..winampMode = true
            ..lafleurSize = const Size(920, 690))
          .save(f);
      final b = await AppSettings.load(f);
      expect(
        [
          b.skin,
          b.winampDouble,
          b.winampEq,
          b.winampPl,
          b.visMode,
          b.winampMode,
          b.lafleurSize,
        ],
        ['Trinity.wsz', false, false, false, 2, true, const Size(920, 690)],
      );
    },
  );

  test(
    'carte Lecture : volume égal et fondu retrouvés, éteints par défaut',
    () async {
      final f = File('${dir.path}/settings.json');
      final d = AppSettings();
      expect(
        (d.equalVolume, d.crossfade, d.crossfadeSeconds),
        (false, false, 5),
      );
      await (AppSettings()
            ..equalVolume = true
            ..crossfade = true
            ..crossfadeSeconds = 8)
          .save(f);
      final back = await AppSettings.load(f);
      expect(
        (back.equalVolume, back.crossfade, back.crossfadeSeconds),
        (true, true, 8),
      );
      final old = File('${dir.path}/old.json')
        ..writeAsStringSync('{"artistGrid": false}');
      final o = await AppSettings.load(old);
      expect(
        (o.equalVolume, o.crossfade, o.crossfadeSeconds),
        (false, false, 5),
      );
      final bad = File('${dir.path}/bad.json')
        ..writeAsStringSync('{"crossfadeSeconds": 99}');
      expect((await AppSettings.load(bad)).crossfadeSeconds, 10);
    },
  );

  test(
    'album sort: Nom by default, saved and read back, junk falls back',
    () async {
      final f = File('${dir.path}/settings.json');
      expect(AppSettings().albumSort, AlbumSort.name);
      await (AppSettings()..albumSort = AlbumSort.mostPlayed).save(f);
      expect((await AppSettings.load(f)).albumSort, AlbumSort.mostPlayed);
      await f.writeAsString('{"albumSort": "nope"}');
      expect((await AppSettings.load(f)).albumSort, AlbumSort.name);
    },
  );
}
