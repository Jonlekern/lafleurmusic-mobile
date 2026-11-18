import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:lafleurmusic/demo/demo_library.dart';
import 'package:lafleurmusic/demo/demo_offline.dart';
import 'package:lafleurmusic/library/db.dart';
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
  Future<void> Function(LibraryDb)? also, // données en plus de la démo
  bool images = false,
  int? free,
  Object? freeError,
}) async {
  final settings = AppSettings();
  final device = DemoDevice(settings: settings);
  if (free != null) device.free = free;
  device.freeError = freeError;
  final folder = _FolderSpy();
  final services = <_CountingService>[];
  final saves = <int>[];
  final f = await pumpKeep(
    tester,
    images: images,
    seed: (db) async {
      await seedOnDeviceDemo(db);
      await also?.call(db);
    },
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
        expect(find.text('48 min · 420 Mo'), findsOneWidget);
        // Night Drive : seulement le Top 100
        expect(find.text('Night Drive'), findsOneWidget);
        expect(find.text('TOP 100'), findsOneWidget);
        expect(find.text('4 titres · 38 Mo'), findsOneWidget);
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
      expect(r.f.downloader.resumes, 1, reason: 'Reprendre lève la pause');
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
        [for (var i = 1; i <= 4; i++) 'subsonic://demo/Night Drive/$i'],
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
    // par « Garder » : la limite et le dossier sont vérifiés
    expect(r.f.downloader.kept, [
      [harbour],
    ]);
    expect(find.byType(SnackBar), findsNothing);
  });

  phoneTest('Réessayer au-delà de la limite : « Pas assez de place »', TargetPlatform.iOS, (
    tester,
  ) async {
    final r = await pumpOnDevice(
      tester,
      downloader: DemoDownloader(result: const KeepResult.tooBig(gib)),
    );
    await tester.tap(find.text('Réessayer'));
    await done(tester);
    expect(find.text('Pas assez de place : il faut encore 1 Go.'), findsOneWidget);
    final row = (await tester.runAsync(
      () => r.f.db.offlineOf('subsonic://demo/Ports/1'),
    ))!;
    expect(row.state, OfflineState.failed.name);
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
      'ancien dossier indisponible : « Utiliser ce dossier » l\'adopte sans rien déplacer',
      TargetPlatform.iOS,
      (tester) async {
        final r = await pumpOnDevice(tester);
        r.device.reachable = false;
        r.device.picked = const PickedFolder('/x/Cloud/LAFLEURMUSIC', 'b64');
        await choose(tester);
        expect(find.text("L'ancien dossier est introuvable"), findsOneWidget);
        await tester.tap(find.text('Utiliser ce dossier'));
        await done(tester);
        expect(r.f.downloader.moves, isEmpty);
        expect(r.f.downloader.adopted, 1);
        expect(r.device.committed.single.path, '/x/Cloud/LAFLEURMUSIC');
        expect(r.services.single.refreshes, 1);
        expect(r.folder.rescans, 1);
      },
    );

    phoneTest(
      'ancien dossier indisponible, annulé : le candidat est abandonné',
      TargetPlatform.iOS,
      (tester) async {
        final r = await pumpOnDevice(tester);
        r.device.reachable = false;
        r.device.picked = const PickedFolder('/x/Cloud/LAFLEURMUSIC', 'b64');
        await choose(tester);
        await tester.tap(find.text('Annuler'));
        await done(tester);
        expect(r.f.downloader.adopted, 0);
        expect(r.f.downloader.moves, isEmpty);
        expect(r.device.committed, isEmpty);
        expect(r.device.released, 1);
      },
    );

    group('chercher l\'ancien dossier', () {
      /// Écrit les copies finies (fichiers creux de la taille des lignes) dans un dossier :
      /// toutes, ou seulement [only] ; [extra] octets de trop pour les mal tailler.
      Future<Directory> oldFolder(
        WidgetTester tester,
        LibraryDb db, {
        int? only,
        int extra = 0,
      }) async {
        final dir = Directory.systemTemp.createTempSync('lm_relink');
        addTearDown(() => dir.deleteSync(recursive: true));
        await tester.runAsync(() async {
          // la démo réutilise des noms (kept/0.mp3) : un fichier par nom, une seule ligne
          final seen = <String>{};
          final rows = [
            for (final o in await db.offlineRows())
              if (o.state == OfflineState.done.name && o.filePath != null)
                if (seen.add(o.filePath!)) o else ...<OfflineRow>[],
          ];
          await db.removeOffline([
            for (final o in await db.offlineRows())
              if (o.state == OfflineState.done.name &&
                  o.filePath != null &&
                  !rows.any((k) => k.trackPath == o.trackPath))
                o.trackPath,
          ]);
          for (var i = 0; i < rows.length; i++) {
            if (only != null && i >= only) break;
            final file = File(p.join(dir.path, rows[i].filePath!))
              ..createSync(recursive: true);
            final raf = file.openSync(mode: FileMode.write)
              ..truncateSync(rows[i].size + extra);
            raf.closeSync();
          }
        });
        return dir;
      }

      Future<void> openRelink(WidgetTester tester, DemoDevice device) async {
        device.reachable = false;
        await scrollTo(tester, find.byKey(const Key('chooseFolder')));
        await tester.tap(find.byKey(const Key('chooseFolder')));
        await done(tester);
        await tester.tap(find.text("Chercher l'ancien dossier"));
        await done(tester);
      }

      const nouveau = PickedFolder('/x/Nouveau/LAFLEURMUSIC');

      void expectRefused(dynamic r, List<OfflineRow> before, String msg) {
        expect(r.device.committed, isEmpty);
        expect(r.device.released, 2);
        expect(r.f.downloader.adopted, 0);
        expect(r.services.single.refreshes, 0);
        expect(find.text(msg), findsOneWidget);
      }

      phoneTest('tout est là à la bonne taille : adopté, rien ne bouge', TargetPlatform.iOS, (tester) async {
        final r = await pumpOnDevice(tester);
        final dir = await oldFolder(tester, r.f.db);
        final before = (await tester.runAsync(() => r.f.db.offlineRows()))!;
        r.device.pickQueue.addAll([nouveau, PickedFolder(dir.path, 'old')]);
        await openRelink(tester, r.device);
        expect(r.device.picks, 2);
        expect(r.device.released, 1); // le nouveau candidat
        expect(r.device.committed.single.path, dir.path);
        expect(r.f.downloader.adopted, 0);
        expect(r.f.downloader.moves, isEmpty);
        expect(r.f.downloader.starts, 1);
        expect(r.services.single.refreshes, 1);
        expect(r.folder.rescans, 1);
        expect((await tester.runAsync(() => r.f.db.offlineRows()))!, before);
        expect(
          find.text('Ancien dossier retrouvé. Choisis maintenant le nouveau dossier.'),
          findsOneWidget,
        );
      });

      phoneTest('un seul fichier sur plusieurs : refusé', TargetPlatform.iOS, (tester) async {
        final r = await pumpOnDevice(tester);
        final dir = await oldFolder(tester, r.f.db, only: 1);
        final before = (await tester.runAsync(() => r.f.db.offlineRows()))!;
        r.device.pickQueue.addAll([nouveau, PickedFolder(dir.path)]);
        await openRelink(tester, r.device);
        expectRefused(r, before, 'Ce dossier ne contient pas tes morceaux gardés.');
        expect((await tester.runAsync(() => r.f.db.offlineRows()))!, before);
      });

      phoneTest('même nom, autre taille : refusé', TargetPlatform.iOS, (tester) async {
        final r = await pumpOnDevice(tester);
        final dir = await oldFolder(tester, r.f.db, extra: 1);
        final before = (await tester.runAsync(() => r.f.db.offlineRows()))!;
        r.device.pickQueue.addAll([nouveau, PickedFolder(dir.path)]);
        await openRelink(tester, r.device);
        expectRefused(r, before, 'Ce dossier ne contient pas tes morceaux gardés.');
      });

      phoneTest('aucune copie finie : refusé', TargetPlatform.iOS, (tester) async {
        final r = await pumpOnDevice(tester);
        await tester.runAsync(() async {
          await r.f.db.removeOffline([
            for (final o in await r.f.db.offlineRows()) o.trackPath,
          ]);
        });
        final dir = Directory.systemTemp.createTempSync('lm_relink');
        addTearDown(() => dir.deleteSync(recursive: true));
        r.device.pickQueue.addAll([nouveau, PickedFolder(dir.path)]);
        await openRelink(tester, r.device);
        expectRefused(r, const [], 'Ce dossier ne contient pas tes morceaux gardés.');
      });

      phoneTest('annulé dans le sélecteur : rien ne change', TargetPlatform.iOS, (tester) async {
        final r = await pumpOnDevice(tester);
        final before = (await tester.runAsync(() => r.f.db.offlineRows()))!;
        r.device.pickQueue.addAll([nouveau, null]);
        await openRelink(tester, r.device);
        expect(r.device.committed, isEmpty);
        expect(r.device.released, 1);
        expect(r.f.downloader.adopted, 0);
        expect((await tester.runAsync(() => r.f.db.offlineRows()))!, before);
        expect(find.byType(SnackBar), findsNothing);
      });

      phoneTest('le sélecteur refuse : pas sur le téléphone', TargetPlatform.iOS, (tester) async {
        final r = await pumpOnDevice(tester);
        r.device.pickQueue.add(nouveau);
        r.device.reachable = false;
        await scrollTo(tester, find.byKey(const Key('chooseFolder')));
        await tester.tap(find.byKey(const Key('chooseFolder')));
        await done(tester);
        r.device.pickError = FolderNotLocalException();
        await tester.tap(find.text("Chercher l'ancien dossier"));
        await done(tester);
        expect(r.device.committed, isEmpty);
        expect(find.textContaining("n’est pas sur le"), findsOneWidget);
      });

      phoneTest('le sélecteur refuse : pas modifiable', TargetPlatform.iOS, (tester) async {
        final r = await pumpOnDevice(tester);
        r.device.pickQueue.add(nouveau);
        r.device.reachable = false;
        await scrollTo(tester, find.byKey(const Key('chooseFolder')));
        await tester.tap(find.byKey(const Key('chooseFolder')));
        await done(tester);
        r.device.pickError = FolderNotWritableException();
        await tester.tap(find.text("Chercher l'ancien dossier"));
        await done(tester);
        expect(r.device.committed, isEmpty);
        expect(find.textContaining("ne peut pas écrire"), findsOneWidget);
      });
    });

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

  group('robustesse', () {
    phoneTest(
      'Retirer un album mêlé : seulement les copies de cet album',
      TargetPlatform.iOS,
      (tester) async {
        // Summer Mix : un morceau fini, les autres en file
        final r = await pumpOnDevice(
          tester,
          also: (db) async {
            await db.queueOffline([
              'subsonic://demo/Summer Mix/4',
            ], OfflineReason.user);
            await db.markOfflineDone(
              'subsonic://demo/Summer Mix/4',
              'kept/s4.mp3',
              1000,
            );
          },
        );
        await tester.longPress(find.text('Summer Mix'));
        await done(tester);
        await tester.tap(find.text('Retirer du téléphone'));
        await done(tester);
        final batch = r.f.downloader.forgotten.single;
        expect(
          batch,
          unorderedEquals([
            'subsonic://demo/Summer Mix/1',
            'subsonic://demo/Summer Mix/2',
            'subsonic://demo/Summer Mix/3',
            'subsonic://demo/Summer Mix/4',
            'subsonic://demo/Summer Mix/5',
          ]),
        );
      },
    );

    phoneTest('deux appuis rapides : un seul sélecteur', TargetPlatform.iOS, (
      tester,
    ) async {
      final r = await pumpOnDevice(tester);
      final gate = r.device.pickGate = Completer<void>();
      await scrollTo(tester, find.byKey(const Key('chooseFolder')));
      await tester.tap(find.byKey(const Key('chooseFolder')));
      await tester.tap(find.byKey(const Key('chooseFolder')));
      await tester.pump();
      expect(r.device.picks, 1);
      gate.complete();
      await done(tester);
      expect(r.device.picks, 1);
    });

    phoneTest(
      'l\'écran part pendant le choix : le candidat est abandonné',
      TargetPlatform.iOS,
      (tester) async {
        final r = await pumpOnDevice(tester);
        final gate = r.device.pickGate = Completer<void>();
        r.device.picked = const PickedFolder('/x/Cloud/LAFLEURMUSIC', 'b64');
        await scrollTo(tester, find.byKey(const Key('chooseFolder')));
        await tester.tap(find.byKey(const Key('chooseFolder')));
        await tester.pump();
        await tester.pumpWidget(const SizedBox()); // l'écran est fermé
        gate.complete();
        await done(tester);
        expect(r.device.released, 1);
        expect(r.f.downloader.moves, isEmpty);
        expect(r.device.committed, isEmpty);
      },
    );

    phoneTest(
      'déplacement raté ou trop gros : le candidat est abandonné',
      TargetPlatform.iOS,
      (tester) async {
        final r = await pumpOnDevice(tester);
        r.device.picked = const PickedFolder('/x/Cloud/LAFLEURMUSIC', 'b64');
        r.f.downloader.moveResult = const KeepResult.failed();
        await scrollTo(tester, find.byKey(const Key('chooseFolder')));
        await tester.tap(find.byKey(const Key('chooseFolder')));
        await done(tester);
        expect(r.device.released, 1);
        r.f.downloader.moveResult = const KeepResult.tooBig(gib);
        await tester.tap(find.byKey(const Key('chooseFolder')));
        await done(tester);
        expect(r.device.released, 2);
      },
    );

    phoneTest(
      'fermé pendant le déplacement : rien ne casse',
      TargetPlatform.iOS,
      (tester) async {
        final r = await pumpOnDevice(tester);
        r.device.picked = const PickedFolder('/x/Cloud/LAFLEURMUSIC', 'b64');
        final gate = r.f.downloader.moveGate = Completer<void>();
        await scrollTo(tester, find.byKey(const Key('chooseFolder')));
        await tester.tap(find.byKey(const Key('chooseFolder')));
        await tester.pump();
        await tester.pumpWidget(const SizedBox());
        gate.complete();
        await done(tester);
        expect(tester.takeException(), isNull);
        expect(r.services.single.refreshes, 1);
      },
    );

    phoneTest(
      'la limite réglée reste affichée même sans assez de place',
      TargetPlatform.iOS,
      (tester) async {
        await pumpOnDevice(tester, free: 0); // 4,2 Go en tout, limite 10 Go
        await scrollTo(tester, find.byKey(const Key('limit')));
        expect(
          tester.widget<Text>(find.byKey(const Key('limit'))).data,
          '10 Go',
        );
        final slider = tester.widget<Slider>(
          find.byKey(const Key('limitSlider')),
        );
        expect(slider.max, 10);
        expect(slider.value, 10);
      },
    );

    phoneTest(
      'place inconnue : borne sûre, puis on réessaie à la construction suivante',
      TargetPlatform.iOS,
      (tester) async {
        final r = await pumpOnDevice(tester, freeError: StateError('nope'));
        await scrollTo(tester, find.byKey(const Key('limitSlider')));
        var slider = tester.widget<Slider>(
          find.byKey(const Key('limitSlider')),
        );
        expect(
          slider.max,
          10,
        ); // la limite, les copies (5 Go) étant plus petites
        expect(find.text('toute la place libre · 10 Go'), findsOneWidget);
        r.device.freeError = null;
        await tester.drag(
          find.byKey(const Key('limitSlider')),
          const Offset(-20, 0),
        );
        await done(tester);
        expect(find.text('toute la place libre · 54 Go'), findsOneWidget);
      },
    );
  });
}
