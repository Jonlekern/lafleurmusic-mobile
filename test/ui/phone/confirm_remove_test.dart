import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/demo/demo_library.dart';
import 'package:lafleurmusic/library/models.dart';
import 'package:lafleurmusic/settings.dart';

import '../fonts.dart';
import '../keep_fixture.dart';
import 'keep_screen_test.dart' show confirmRemoval, done, longPress, phoneTest;
import 'on_device_screen_test.dart' show pathsOf, pumpOnDevice, scrollTo;

const _title = 'Retirer du téléphone ?';
const _night =
    '« Night Drive » (4 morceaux, 38 Mo) sera effacé de ton iPhone. '
    'Il reste sur ton serveur : tu pourras le garder à nouveau.';

Future<void> _swipeNightDrive(WidgetTester tester) async {
  await tester.drag(find.text('Night Drive'), const Offset(-300, 0));
  await done(tester);
}

void main() {
  setUpAll(loadFonts);

  group('Sur mon iPhone : glisser', () {
    phoneTest(
      'la fenêtre dit le nom, le nombre et la taille',
      TargetPlatform.iOS,
      (tester) async {
        final r = await pumpOnDevice(tester);
        await _swipeNightDrive(tester);
        expect(find.text(_title), findsOneWidget);
        expect(find.text(_night), findsOneWidget);
        expect(find.text('Ne plus me demander'), findsOneWidget);
        expect(find.text('Annuler'), findsOneWidget);
        expect(r.f.downloader.forgotten, isEmpty); // rien avant le oui
      },
    );

    phoneTest('Android : « téléphone »', TargetPlatform.android, (
      tester,
    ) async {
      await pumpOnDevice(tester);
      await _swipeNightDrive(tester);
      expect(
        find.textContaining('sera effacé de ton téléphone.'),
        findsOneWidget,
      );
    });

    phoneTest('Annuler ne retire rien', TargetPlatform.iOS, (tester) async {
      final r = await pumpOnDevice(tester);
      await _swipeNightDrive(tester);
      await tester.tap(find.text('Annuler'));
      await done(tester);
      expect(find.text(_title), findsNothing);
      expect(r.f.downloader.forgotten, isEmpty);
      expect(r.settings.confirmRemove, isTrue);
    });

    phoneTest('Retirer retire, la question reste', TargetPlatform.iOS, (
      tester,
    ) async {
      final r = await pumpOnDevice(tester);
      await _swipeNightDrive(tester);
      await confirmRemoval(tester);
      expect(r.f.downloader.forgotten, [
        [for (var i = 1; i <= 4; i++) 'subsonic://demo/Night Drive/$i'],
      ]);
      expect(r.settings.confirmRemove, isTrue);
    });
  });

  phoneTest('la taille compte les copies des jumeaux', TargetPlatform.iOS, (
    tester,
  ) async {
    // le même morceau chez un autre compte, avec sa propre copie de 10 Mo
    final first = DemoLibrary.remote.firstWhere(
      (t) => t.album == 'Night Drive' && t.trackNo == 1,
    );
    final twin = Track(
      path: 'subsonic://other/nd1',
      accountId: 'other',
      title: first.title,
      artist: first.artist,
      album: first.album,
      trackNo: first.trackNo,
      durationMs: first.durationMs,
      hasCover: false,
      size: 1,
    );
    await pumpOnDevice(
      tester,
      also: (db) async {
        await db.upsertTracks([twin]);
        await db.queueOffline([twin.path], OfflineReason.user);
        await db.markOfflineDone(twin.path, 'kept/nd1b.mp3', 10 * 1024 * 1024);
      },
    );
    await _swipeNightDrive(tester);
    expect(
      find.textContaining('« Night Drive » (4 morceaux, 48 Mo)'),
      findsOneWidget,
    );
  });

  group('Sur mon iPhone : appui long', () {
    phoneTest('la fenêtre s\'ouvre après la feuille', TargetPlatform.iOS, (
      tester,
    ) async {
      final r = await pumpOnDevice(tester);
      await tester.longPress(find.text('Night Drive'));
      await done(tester);
      await tester.tap(find.text('Retirer du téléphone'));
      await done(tester);
      expect(find.text(_title), findsOneWidget);
      expect(r.f.downloader.forgotten, isEmpty);
      await tester.tap(find.text('Annuler'));
      await done(tester);
      expect(r.f.downloader.forgotten, isEmpty);
    });
  });

  group('feuille d\'un album ou d\'un morceau', () {
    phoneTest(
      'la fenêtre s\'ouvre ; Annuler ne retire rien',
      TargetPlatform.iOS,
      (tester) async {
        final f = await pumpKeep(tester);
        await longPress(tester, find.text('Lafleur Surf').first);
        await tester.tap(find.text('Retirer du téléphone'));
        await done(tester);
        expect(find.text(_title), findsOneWidget);
        expect(find.textContaining('« Lafleur Surf » ('), findsOneWidget);
        await tester.tap(find.text('Annuler'));
        await done(tester);
        expect(f.downloader.forgotten, isEmpty);
      },
    );

    phoneTest('Retirer retire', TargetPlatform.iOS, (tester) async {
      final f = await pumpKeep(tester);
      await longPress(tester, find.text('Lafleur Surf').first);
      await tester.tap(find.text('Retirer du téléphone'));
      await done(tester);
      await confirmRemoval(tester);
      expect(f.downloader.forgotten, [pathsOf('Lafleur Surf')]);
    });
  });

  group('« Ne plus me demander »', () {
    phoneTest(
      'case cochée + Retirer : retire, éteint, plus de fenêtre',
      TargetPlatform.iOS,
      (tester) async {
        final r = await pumpOnDevice(tester);
        await _swipeNightDrive(tester);
        await tester.tap(find.text('Ne plus me demander'));
        await tester.pump();
        await confirmRemoval(tester);
        expect(r.f.downloader.forgotten, hasLength(1));
        expect(r.settings.confirmRemove, isFalse);
        expect(r.saves, isNotEmpty); // réglage enregistré
        await tester.drag(find.text('Lafleur Surf'), const Offset(-300, 0));
        await done(tester);
        expect(find.text(_title), findsNothing);
        expect(r.f.downloader.forgotten, hasLength(2)); // retiré sans question
      },
    );

    phoneTest('case cochée + Annuler : rien ne change', TargetPlatform.iOS, (
      tester,
    ) async {
      final r = await pumpOnDevice(tester);
      await _swipeNightDrive(tester);
      await tester.tap(find.text('Ne plus me demander'));
      await tester.pump();
      await tester.tap(find.text('Annuler'));
      await done(tester);
      expect(r.settings.confirmRemove, isTrue);
      expect(r.f.downloader.forgotten, isEmpty);
    });

    phoneTest('l\'interrupteur remet la question', TargetPlatform.iOS, (
      tester,
    ) async {
      final settings = AppSettings(confirmRemove: false);
      final r = await pumpOnDevice(tester, withSettings: settings);
      await scrollTo(tester, find.byKey(const Key('confirmRemoveSwitch')));
      expect(find.text('CONFIRMATIONS'), findsOneWidget);
      expect(
        find.text('Si tu as coché « Ne plus me demander », rallume-le ici.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<Switch>(find.byKey(const Key('confirmRemoveSwitch')))
            .value,
        isFalse,
      );
      await tester.tap(find.byKey(const Key('confirmRemoveSwitch')));
      await done(tester);
      expect(settings.confirmRemove, isTrue);
      expect(r.saves, isNotEmpty);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 3000));
      await done(tester);
      await _swipeNightDrive(tester);
      expect(find.text(_title), findsOneWidget);
    });
  });

  phoneTest(
    'retrait automatique (Top 100) : jamais de fenêtre',
    TargetPlatform.iOS,
    (tester) async {
      final r = await pumpOnDevice(tester);
      await r.f.downloader.forget(
        pathsOf('Night Drive'),
        only: OfflineReason.top100,
      ); // ce que fait TopKeeper : sans byUser
      await done(tester);
      expect(find.text(_title), findsNothing);
      expect(r.f.downloader.forgotten, hasLength(1));
    },
  );
}
