import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/demo/demo_library.dart';
import 'package:lafleurmusic/demo/demo_offline.dart';
import 'package:lafleurmusic/library/models.dart';
import 'package:lafleurmusic/offline/device.dart';
import 'package:lafleurmusic/offline/downloader.dart';
import 'package:lafleurmusic/offline/local_folder.dart';
import 'package:lafleurmusic/settings.dart';
import 'package:lafleurmusic/ui/phone/on_device_screen.dart';

import '../fonts.dart';
import '../keep_fixture.dart';
import 'keep_screen_test.dart' show done, phoneTest;

const gib = 1024 * 1024 * 1024;

List<String> pathsOf(String album) => [
  for (final t in DemoLibrary.remote)
    if (t.album == album) t.path,
];

class _FolderSpy implements LocalFolder {
  int rescans = 0;
  @override
  Future<void> rescan() async => rescans++;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _CountingService extends DemoAccountService {
  _CountingService(super.accounts, {required super.db});
  int refreshes = 0;
  @override
  Future<void> refreshRoot() async => refreshes++;
}

/// L'écran seul, sur les données de la démo (maquette 4).
Future<
  ({
    KeepFixture f,
    DemoDevice device,
    AppSettings settings,
    _FolderSpy folder,
    List<_CountingService> services,
    List<int> saves,
  })
>
pumpOnDevice(
  WidgetTester tester, {
  DemoDownloader? downloader,
  Future<void> Function(dynamic)? seed,
  bool images = false,
}) async {
  final settings = AppSettings();
  final device = DemoDevice(settings: settings);
  final folder = _FolderSpy();
  final services = <_CountingService>[];
  final saves = <int>[];
  final f = await pumpKeep(
    tester,
    images: images,
    seed: seedOnDeviceDemo,
    home: const OnDeviceScreen(),
    device: device,
    localFolder: folder,
    settings: settings,
    saveSettings: () => saves.add(settings.storageLimitBytes),
    downloader:
        downloader ??
        (DemoDownloader()
          ..current = 'subsonic://demo/Summer Mix/5'
          ..progress = 12.4 / 19.6),
    makeService: (accounts, db) {
      final s = _CountingService(accounts, db: db);
      services.add(s);
      return s;
    },
  );
  await done(tester);
  return (
    f: f,
    device: device,
    settings: settings,
    folder: folder,
    services: services,
    saves: saves,
  );
}

Future<void> scrollTo(WidgetTester tester, Finder f) async {
  await tester.scrollUntilVisible(
    f,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pump();
}

void main() {
  setUpAll(loadFonts);

  group('les sections', () {
    phoneTest(
      'le téléchargement en cours, les gardés, les échecs',
      TargetPlatform.iOS,
      (tester) async {
        await pumpOnDevice(tester);
        expect(find.text('EN COURS · 3 EN ATTENTE'), findsOneWidget);
        expect(find.text('Golden Hour'), findsOneWidget);
        expect(find.text('Summer Mix · 12,4 sur 19,6 Mo'), findsOneWidget);
        expect(find.text('GARDÉS'), findsOneWidget);
        expect(find.text('Lafleur Surf'), findsOneWidget);
        expect(find.text('Studio Lafleur'), findsOneWidget);
        expect(find.text('36 min · 310 Mo'), findsOneWidget);
        expect(find.text('420 Mo'), findsNothing); // durée d'abord
        expect(find.text('8 min · 420 Mo'), findsOneWidget);
        // Night Drive : seulement le Top 100
        expect(find.text('Night Drive'), findsOneWidget);
        expect(find.text('TOP 100'), findsOneWidget);
        expect(find.text('1 titre · 38 Mo'), findsOneWidget);
        expect(find.text('À RÉESSAYER'), findsOneWidget);
        expect(find.text('Ports'), findsOneWidget);
        expect(find.text('Introuvable sur le serveur'), findsOneWidget);
        expect(find.text('Réessayer'), findsOneWidget);
      },
    );

    phoneTest(
      'rien en file : pas de section « En cours »',
      TargetPlatform.iOS,
      (tester) async {
        final r = await pumpOnDevice(tester);
        await tester.runAsync(() async {
          await r.f.db.removeOffline([
            for (final t in DemoLibrary.remote)
              if (t.album == 'Summer Mix' || t.album == 'Ports') t.path,
            'subsonic://demo/Summer Mix/5', // Golden Hour
          ]);
        });
        await done(tester);
        expect(find.textContaining('EN COURS'), findsNothing);
        expect(find.text('À RÉESSAYER'), findsNothing);
        expect(find.text('GARDÉS'), findsOneWidget);
      },
    );

    phoneTest('Pause puis reprise', TargetPlatform.iOS, (tester) async {
      final r = await pumpOnDevice(tester);
      expect(find.byKey(const Key('resume')), findsNothing);
      await tester.tap(find.byKey(const Key('pause')));
      await done(tester);
      expect(r.f.downloader.pauses, 1);
      expect(find.byKey(const Key('pause')), findsNothing);
      await tester.tap(find.byKey(const Key('resume')));
      await done(tester);
      expect(r.f.downloader.starts, 1);
    });

    phoneTest(
      'accès refusé (Android) : le message de la partie A',
      TargetPlatform.android,
      (tester) async {
        final d = DemoDownloader()..accessDenied = true;
        await pumpOnDevice(tester, downloader: d);
        expect(
          find.text(
            "L'appli n'a pas le droit d'écrire dans Musique. Autorise-la dans les réglages du téléphone.",
          ),
          findsOneWidget,
        );
      },
    );
  });

  group('retirer', () {
    phoneTest(
      'balayer vers la gauche oublie les copies de l\'album',
      TargetPlatform.iOS,
      (tester) async {
        final r = await pumpOnDevice(tester);
        await tester.drag(find.text('Lafleur Surf'), const Offset(-300, 0));
        await done(tester);
        expect(r.f.downloader.forgotten, [pathsOf('Lafleur Surf')]);
      },
    );

    phoneTest('appui long → « Retirer du téléphone »', TargetPlatform.iOS, (
      tester,
    ) async {
      final r = await pumpOnDevice(tester);
      await tester.longPress(find.text('Studio Lafleur'));
      await done(tester);
      await tester.tap(find.text('Retirer du téléphone'));
      await done(tester);
      expect(r.f.downloader.forgotten, [pathsOf('Studio Lafleur')]);
    });

    phoneTest('Top 100 : la copie part aussi', TargetPlatform.iOS, (
      tester,
    ) async {
      final r = await pumpOnDevice(tester);
      await tester.longPress(find.text('Night Drive'));
      await done(tester);
      await tester.tap(find.text('Retirer du téléphone'));
      await done(tester);
      expect(r.f.downloader.forgotten, [
        ['subsonic://demo/Night Drive/1'],
      ]);
    });
  });

  phoneTest('Réessayer remet l\'album en file et relance', TargetPlatform.iOS, (
    tester,
  ) async {
    final r = await pumpOnDevice(tester);
    final harbour = 'subsonic://demo/Ports/1';
    expect(
      (await tester.runAsync(() => r.f.db.offlineOf(harbour)))!.state,
      OfflineState.failed.name,
    );
    await tester.tap(find.text('Réessayer'));
    await done(tester);
    final row = (await tester.runAsync(() => r.f.db.offlineOf(harbour)))!;
    expect(row.state, OfflineState.queued.name);
    expect(row.failures, 0);
    expect(r.f.downloader.starts, 1);
    expect(find.text('À RÉESSAYER'), findsNothing);
  });

  group('limite', () {
    phoneTest('la place utilisée et la limite', TargetPlatform.iOS, (
      tester,
    ) async {
      await pumpOnDevice(tester);
      await scrollTo(tester, find.byKey(const Key('limit')));
      expect(find.text("PLACE SUR L'IPHONE"), findsOneWidget);
      expect(find.text('4,2 Go utilisés sur 10 Go'), findsOneWidget);
      expect(find.text('10 Go'), findsWidgets);
      expect(find.text('1 Go'), findsOneWidget);
      expect(find.text('toute la place libre · 54 Go'), findsOneWidget);
    });

    phoneTest('le curseur enregistre la limite, par Go', TargetPlatform.iOS, (
      tester,
    ) async {
      final r = await pumpOnDevice(tester);
      await scrollTo(tester, find.byKey(const Key('limitSlider')));
      final slider = find.byKey(const Key('limitSlider'));
      await tester.drag(slider, const Offset(-2000, 0)); // tout à gauche
      await done(tester);
      expect(r.settings.storageLimitBytes, 1 * gib);
      expect(r.saves, [1 * gib]);
      expect(find.byKey(const Key('limit')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('limit'))).data, '1 Go');
      await tester.drag(slider, const Offset(2000, 0)); // tout à droite
      await done(tester);
      expect(r.settings.storageLimitBytes, 54 * gib); // la place libre
      expect(r.saves, [1 * gib, 54 * gib]);
      await tester.drag(slider, const Offset(-200, 0));
      await done(tester);
      expect(r.settings.storageLimitBytes % gib, 0);
      expect(r.settings.storageLimitBytes, inInclusiveRange(1 * gib, 53 * gib));
    });
  });

  group('dossier', () {
    phoneTest(
      'iPhone : « Sur mon iPhone › LAFLEURMUSIC »',
      TargetPlatform.iOS,
      (tester) async {
        await pumpOnDevice(tester);
        await scrollTo(tester, find.byKey(const Key('folder')));
        expect(find.text('Sur mon iPhone › LAFLEURMUSIC'), findsOneWidget);
        expect(find.text('Choisir le dossier…'), findsOneWidget);
      },
    );

    phoneTest(
      'Android : « Musique › LAFLEURMUSIC », « téléphone »',
      TargetPlatform.android,
      (tester) async {
        await pumpOnDevice(tester);
        await scrollTo(tester, find.byKey(const Key('folder')));
        expect(find.text('Musique › LAFLEURMUSIC'), findsOneWidget);
        expect(find.text('PLACE SUR LE TÉLÉPHONE'), findsOneWidget);
      },
    );

    Future<void> choose(WidgetTester tester) async {
      await scrollTo(tester, find.byKey(const Key('chooseFolder')));
      await tester.tap(find.byKey(const Key('chooseFolder')));
      await done(tester);
    }

    phoneTest('annulé : rien ne bouge', TargetPlatform.iOS, (tester) async {
      final r = await pumpOnDevice(tester);
      r.device.picked = null;
      await choose(tester);
      expect(r.f.downloader.moves, isEmpty);
      expect(find.byType(SnackBar), findsNothing);
    });

    phoneTest('pas sur le téléphone : le message', TargetPlatform.android, (
      tester,
    ) async {
      final r = await pumpOnDevice(tester);
      r.device.pickError = FolderNotLocalException();
      await choose(tester);
      expect(r.f.downloader.moves, isEmpty);
      expect(
        find.text(
          'Ce dossier n’est pas sur le téléphone. Choisis un dossier du téléphone ou de la carte SD.',
        ),
        findsOneWidget,
      );
    });

    phoneTest('pas modifiable : le message', TargetPlatform.android, (
      tester,
    ) async {
      final r = await pumpOnDevice(tester);
      r.device.pickError = FolderNotWritableException();
      await choose(tester);
      expect(r.f.downloader.moves, isEmpty);
      expect(
        find.text(
          'L’appli ne peut pas écrire dans ce dossier. Choisis-en un autre, par exemple dans Musique.',
        ),
        findsOneWidget,
      );
    });

    phoneTest('trop gros : « Pas assez de place »', TargetPlatform.iOS, (
      tester,
    ) async {
      final r = await pumpOnDevice(tester);
      r.device.picked = const PickedFolder('/x/Cloud/LAFLEURMUSIC');
      r.f.downloader.moveResult = const KeepResult.tooBig(2 * gib);
      await choose(tester);
      expect(
        find.text('Pas assez de place : il faut encore 2 Go.'),
        findsOneWidget,
      );
      expect(r.device.committed, isEmpty);
      expect(r.services.single.refreshes, 0);
      expect(r.folder.rescans, 0);
      expect(find.text('Sur mon iPhone › LAFLEURMUSIC'), findsOneWidget);
    });

    phoneTest('raté : « Rien n\'a été déplacé »', TargetPlatform.iOS, (
      tester,
    ) async {
      final r = await pumpOnDevice(tester);
      r.device.picked = const PickedFolder('/x/Cloud/LAFLEURMUSIC');
      r.f.downloader.moveResult = const KeepResult.failed();
      await choose(tester);
      expect(
        find.text("Le dossier n'a pas pu être changé. Rien n'a été déplacé."),
        findsOneWidget,
      );
      expect(r.services.single.refreshes, 0);
      expect(r.folder.rescans, 0);
    });

    phoneTest(
      'accepté : déplacé depuis l\'ancien, adopté, relu',
      TargetPlatform.iOS,
      (tester) async {
        final r = await pumpOnDevice(tester);
        r.device.picked = const PickedFolder('/x/Cloud/LAFLEURMUSIC', 'b64');
        await choose(tester);
        final (from, to) = r.f.downloader.moves.single;
        expect(from.path, '/var/mobile/Documents/LAFLEURMUSIC');
        expect(to.path, '/x/Cloud/LAFLEURMUSIC');
        expect(r.device.committed.single.path, '/x/Cloud/LAFLEURMUSIC');
        expect(r.services.single.refreshes, 1);
        expect(r.folder.rescans, 1);
        expect(find.byType(SnackBar), findsNothing);
        expect(find.text('Cloud › LAFLEURMUSIC'), findsOneWidget);
      },
    );

    phoneTest(
      'pendant le déplacement : « Déplacement… », bouton éteint',
      TargetPlatform.iOS,
      (tester) async {
        final r = await pumpOnDevice(tester);
        r.device.picked = const PickedFolder('/x/Cloud/LAFLEURMUSIC', 'b64');
        final gate = r.f.downloader.moveGate = Completer<void>();
        await choose(tester);
        expect(find.text('Déplacement…'), findsOneWidget);
        expect(find.text('Choisir le dossier…'), findsNothing);
        await tester.tap(find.byKey(const Key('chooseFolder')));
        await done(tester);
        expect(r.f.downloader.moves.length, 1);
        gate.complete();
        await done(tester);
        expect(find.text('Choisir le dossier…'), findsOneWidget);
      },
    );
  });
}
