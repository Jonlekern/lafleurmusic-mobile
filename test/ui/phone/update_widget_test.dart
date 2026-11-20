import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/settings.dart';
import 'package:lafleurmusic/ui/classic/classic_menu.dart';
import 'package:lafleurmusic/ui/classic/classic_shell.dart';
import 'package:lafleurmusic/ui/phone/accounts_screen.dart';
import 'package:lafleurmusic/ui/update_sheet.dart';
import 'package:lafleurmusic/update/update_service.dart';

import '../classic/classic_shell_test.dart' show press, rotate, selected;
import '../fonts.dart';
import '../phone_fixture.dart';
import '../update_fixture.dart';

/// Un test de widget qui remet la plateforme à zéro avant les vérifications de fin.
void tw(String name, Future<void> Function(WidgetTester tester) body) =>
    testWidgets(name, (tester) async {
      try {
        await body(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

void main() {
  setUpAll(loadFonts);

  late List<String> installed;
  late List<Uri> launched;
  late bool installAnswer;
  setUp(() {
    installed = [];
    launched = [];
    installAnswer = true;
    UpdateHooks.install = (path) async {
      installed.add(path);
      return installAnswer;
    };
    UpdateHooks.launch = (uri) async {
      launched.add(uri);
      return true;
    };
    UpdateHooks.cacheDir = () async => Directory('/cache');
  });
  tearDown(() {
    UpdateHooks.reset();
    debugDefaultTargetPlatformOverride = null;
  });

  Future<FakeUpdateService> start(
    WidgetTester tester, {
    UpdateInfo? available = update0110,
    TargetPlatform platform = TargetPlatform.android,
    Widget? home,
  }) async {
    debugDefaultTargetPlatformOverride = platform;
    final service = FakeUpdateService(available: available);
    if (home == null) {
      await pumpPhone(tester, update: service);
    } else {
      await pumpPhone(tester, update: service, home: home);
    }
    return service;
  }

  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(find.text('Mettre à jour'));
    await tester.pumpAndSettle();
    expect(find.byType(UpdateSheet), findsOneWidget);
  }

  group('bandeau', () {
    tw('sans service : rien', (tester) async {
      await pumpPhone(tester);
      expect(find.byType(UpdateBanner), findsNothing);
      expect(find.text('Nouvelle version 0.11.0'), findsNothing);
    });

    tw('sans mise à jour : pas de bandeau', (tester) async {
      await start(tester, available: null);
      expect(find.text('Nouvelle version 0.11.0'), findsNothing);
      expect(find.text('Mettre à jour'), findsNothing);
    });

    tw('avec une mise à jour : le bandeau de la maquette', (tester) async {
      await start(tester);
      expect(find.text('Nouvelle version 0.11.0'), findsOneWidget);
      expect(find.text('Touche pour voir ce qui change'), findsOneWidget);
      expect(find.text('Mettre à jour'), findsOneWidget);
    });

    tw('✕ écarte cette version et le bandeau part', (tester) async {
      final settings = AppSettings();
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final service = FakeUpdateService(
        available: update0110,
        settings: settings,
      );
      await pumpPhone(tester, update: service);
      await tester.tap(find.byKey(const Key('updateDismiss')));
      await tester.pump();
      expect(settings.dismissedUpdate, '0.11.0');
      expect(service.available.value, isNull);
      expect(find.text('Nouvelle version 0.11.0'), findsNothing);
    });

    tw('« Mettre à jour » ouvre la feuille', (tester) async {
      await start(tester);
      await openSheet(tester);
      expect(find.text('LAFLEURMUSIC 0.11.0'), findsOneWidget);
      expect(find.text('Tu as la 0.10.2'), findsOneWidget);
      expect(find.text('Ce qui change, en quelques lignes'), findsOneWidget);
    });

    tw('toucher le bandeau ouvre aussi la feuille', (tester) async {
      await start(tester);
      await tester.tap(find.text('Touche pour voir ce qui change'));
      await tester.pumpAndSettle();
      expect(find.byType(UpdateSheet), findsOneWidget);
    });
  });

  group('feuille Android', () {
    tw('bouton → progression → installeur avec le fichier', (tester) async {
      final service = await start(tester);
      await openSheet(tester);
      expect(find.text('Télécharger et installer · 98 Mo'), findsOneWidget);
      expect(
        find.text('Ta musique, tes playlists et tes comptes restent.'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('updateAction')));
      await tester.pump();
      expect(service.downloads, 1);
      expect(service.dir!.path, '/cache');
      service.progress!(0.62);
      await tester.pump();
      expect(
        find.text(
          '62 % — puis Android demande « Installer ? ». '
          'Ta musique, tes playlists et tes comptes restent.',
        ),
        findsOneWidget,
      );
      // pendant le téléchargement, le bouton ne relance rien
      await tester.tap(find.byKey(const Key('updateAction')));
      await tester.pump();
      expect(service.downloads, 1);
      service.download!.complete(
        File('/cache/updates/LAFLEURMUSIC-android.apk'),
      );
      await tester.pumpAndSettle();
      expect(installed, ['/cache/updates/LAFLEURMUSIC-android.apk']);
      // le fichier reste : « Installer » rouvre l'installeur sans retélécharger
      expect(find.text('Installer'), findsOneWidget);
      await tester.tap(find.text('Installer'));
      await tester.pumpAndSettle();
      expect(installed, hasLength(2));
      expect(service.downloads, 1);
    });

    tw('échec du téléchargement : message, et le bouton revient', (
      tester,
    ) async {
      final service = await start(tester);
      await openSheet(tester);
      await tester.tap(find.byKey(const Key('updateAction')));
      await tester.pump();
      service.download!.completeError(const FormatException('empreinte'));
      await tester.pumpAndSettle();
      expect(
        find.text('Le téléchargement a échoué. Réessaie.'),
        findsOneWidget,
      );
      expect(find.text('Télécharger et installer · 98 Mo'), findsOneWidget);
      expect(installed, isEmpty);
      // réessayer repart de zéro
      await tester.tap(find.byKey(const Key('updateAction')));
      await tester.pump();
      expect(service.downloads, 2);
      expect(find.text('Le téléchargement a échoué. Réessaie.'), findsNothing);
    });

    tw('installeur refusé : message, et le bouton revient', (tester) async {
      installAnswer = false;
      final service = await start(tester);
      await openSheet(tester);
      await tester.tap(find.byKey(const Key('updateAction')));
      await tester.pump();
      service.download!.complete(
        File('/cache/updates/LAFLEURMUSIC-android.apk'),
      );
      await tester.pumpAndSettle();
      expect(installed, hasLength(1));
      expect(
        find.text('Le téléchargement a échoué. Réessaie.'),
        findsOneWidget,
      );
      expect(find.text('Télécharger et installer · 98 Mo'), findsOneWidget);
      expect(find.text('Installer'), findsNothing);
    });

    tw(
      'fermer la feuille pendant le téléchargement l\'annule, sans installeur',
      (tester) async {
        final service = await start(tester);
        await openSheet(tester);
        await tester.tap(find.byKey(const Key('updateAction')));
        await tester.pump();
        service.progress!(0.3);
        await tester.pump();
        final token = service.token!;
        expect(token.cancelled, isFalse);
        // toucher le voile ferme la feuille
        await tester.tapAt(const Offset(195, 100));
        await tester.pumpAndSettle();
        expect(find.byType(UpdateSheet), findsNothing);
        expect(token.cancelled, isTrue);
        // une progression tardive ne touche plus à rien (pas de setState après dispose)
        service.progress!(0.9);
        await tester.pumpAndSettle();
        expect(installed, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );

    tw(
      'un téléchargement qui finit après la fermeture n\'ouvre pas l\'installeur',
      (tester) async {
        final service = await start(tester);
        service.ignoreCancel = true;
        await openSheet(tester);
        await tester.tap(find.byKey(const Key('updateAction')));
        await tester.pump();
        await tester.tapAt(const Offset(195, 100));
        await tester.pumpAndSettle();
        expect(service.token!.cancelled, isTrue);
        // le fichier arrive quand même, après la fermeture
        service.download!.complete(
          File('/cache/updates/LAFLEURMUSIC-android.apk'),
        );
        await tester.pumpAndSettle();
        expect(installed, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );

    tw(
      'un téléchargement fini pendant l\'animation de fermeture n\'ouvre pas l\'installeur',
      (tester) async {
        final service = await start(tester);
        service.ignoreCancel = true;
        await openSheet(tester);
        await tester.tap(find.byKey(const Key('updateAction')));
        await tester.pump();
        Navigator.of(tester.element(find.byType(UpdateSheet))).pop();
        await tester.pump(); // l'animation de fermeture commence
        await tester.pump(const Duration(milliseconds: 50));
        expect(find.byType(UpdateSheet), findsOneWidget); // encore à l'écran
        expect(service.token!.cancelled, isTrue);
        service.download!.complete(
          File('/cache/updates/LAFLEURMUSIC-android.apk'),
        );
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pumpAndSettle();
        expect(find.byType(UpdateSheet), findsNothing);
        expect(installed, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );

    tw('Android sans APK : ouvre la page de la version', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final service = FakeUpdateService(
        available: UpdateInfo(
          version: '0.11.0',
          notes: const [],
          pageUrl: update0110.pageUrl,
        ),
      );
      await pumpPhone(tester, update: service);
      await openSheet(tester);
      await tester.tap(find.text('Ouvrir le téléchargement'));
      await tester.pump();
      expect(launched, [Uri.parse(update0110.pageUrl)]);
      expect(service.downloads, 0);
    });
  });

  group('feuille iPhone', () {
    tw('bouton → l\'IPA s\'ouvre hors de l\'appli', (tester) async {
      final service = await start(tester, platform: TargetPlatform.iOS);
      await openSheet(tester);
      expect(find.text('Ouvrir le téléchargement'), findsOneWidget);
      expect(
        find.text(
          "Le fichier s'ouvre dans Safari. Signe-le avec Signulous comme "
          "d'habitude. Ta musique, tes playlists et tes comptes restent.",
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Ouvrir le téléchargement'));
      await tester.pump();
      expect(launched, [Uri.parse(update0110.ipaUrl!)]);
      expect(service.downloads, 0);
      expect(installed, isEmpty);
    });

    tw('sans IPA : la page de la version', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final service = FakeUpdateService(
        available: UpdateInfo(
          version: '0.11.0',
          notes: const ['x'],
          pageUrl: update0110.pageUrl,
          apkUrl: update0110.apkUrl,
        ),
      );
      await pumpPhone(tester, update: service);
      await openSheet(tester);
      await tester.tap(find.text('Ouvrir le téléchargement'));
      await tester.pump();
      expect(launched, [Uri.parse(update0110.pageUrl)]);
    });
  });

  group('Réglages', () {
    Future<FakeUpdateService> openSettings(
      WidgetTester tester, {
      UpdateInfo? available,
    }) async {
      final service = await start(
        tester,
        available: available,
        home: const AccountsScreen(),
      );
      await settle(tester);
      await tester.scrollUntilVisible(
        find.byKey(const Key('updateCheck')),
        100,
      );
      expect(find.text('Version 0.10.2'), findsOneWidget);
      expect(find.text('Chercher une mise à jour ›'), findsOneWidget);
      return service;
    }

    tw('sans service : pas de ligne', (tester) async {
      await pumpPhone(tester, home: const AccountsScreen());
      expect(find.byKey(const Key('updateCheck')), findsNothing);
    });

    tw('nouvelle version (même écartée) : la feuille', (tester) async {
      final service = await openSettings(tester);
      service
        ..nextCheck = UpdateCheck.newer
        ..found = update0110;
      await tester.tap(find.byKey(const Key('updateCheck')));
      await tester.pumpAndSettle();
      expect(find.byType(UpdateSheet), findsOneWidget);
      expect(find.text('LAFLEURMUSIC 0.11.0'), findsOneWidget);
    });

    tw('à jour : « Tu as la dernière version »', (tester) async {
      final service = await openSettings(tester);
      service.nextCheck = UpdateCheck.upToDate;
      await tester.tap(find.byKey(const Key('updateCheck')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Tu as la dernière version'), findsOneWidget);
      expect(find.byType(UpdateSheet), findsNothing);
    });

    tw('sans réseau : « Pas de réseau, réessaie plus tard »', (tester) async {
      final service = await openSettings(tester);
      service.nextCheck = UpdateCheck.offline;
      await tester.tap(find.byKey(const Key('updateCheck')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Pas de réseau, réessaie plus tard'), findsOneWidget);
      expect(find.byType(UpdateSheet), findsNothing);
    });
  });

  group('Mode Classic', () {
    tw('sans mise à jour : pas de ligne « Mise à jour »', (tester) async {
      await start(tester, available: null, home: const ClassicShell());
      expect(find.text('Mise à jour'), findsNothing);
      expect(selected(tester), 'Cover Flow');
    });

    tw('avec : en haut du menu ; la molette et le milieu l\'ouvrent', (
      tester,
    ) async {
      await start(tester, home: const ClassicShell());
      final rows = tester
          .widgetList<ClassicRow>(find.byType(ClassicRow))
          .map((r) => r.label)
          .toList();
      expect(rows.first, 'Mise à jour');
      expect(rows[1], 'Cover Flow');
      expect(selected(tester), 'Mise à jour');
      // la molette descend et remonte dessus comme sur les autres lignes
      await rotate(tester, 1);
      expect(selected(tester), 'Cover Flow');
      await rotate(tester, -1);
      expect(selected(tester), 'Mise à jour');
      await press(tester, 'select');
      await tester.pumpAndSettle();
      expect(find.byType(UpdateSheet), findsOneWidget);
      expect(find.text('LAFLEURMUSIC 0.11.0'), findsOneWidget);
    });

    tw('la ligne arrive et part : la même ligne reste choisie', (tester) async {
      final service = await start(
        tester,
        available: null,
        home: const ClassicShell(),
      );
      await rotate(tester, 2);
      expect(selected(tester), 'Albums');
      service.available.value = update0110; // la recherche du jour répond
      await tester.pump();
      expect(find.text('Mise à jour'), findsOneWidget);
      expect(selected(tester), 'Albums');
      await rotate(tester, -3);
      expect(selected(tester), 'Mise à jour');
      service.available.value = null;
      await tester.pump();
      expect(find.text('Mise à jour'), findsNothing);
      expect(selected(tester), 'Cover Flow');
    });
  });
}
