import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/demo/demo_library.dart';
import 'package:lafleurmusic/demo/demo_offline.dart';
import 'package:lafleurmusic/library/models.dart';
import 'package:lafleurmusic/offline/downloader.dart';
import 'package:lafleurmusic/ui/phone/album_screen.dart';
import 'package:lafleurmusic/ui/phone/home_screen.dart';
import 'package:lafleurmusic/ui/phone/keep_screen.dart';
import 'package:lafleurmusic/ui/phone/phone_shell.dart';

import '../fonts.dart';
import '../keep_fixture.dart';
import '../phone_fixture.dart';

List<String> pathsOf(String album) => [
  for (final t in DemoLibrary.remote)
    if (t.album == album) t.path,
];

/// Laisse la base répondre, puis finit les animations (feuille, écran qui glisse).
Future<void> done(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await settle(tester);
  await tester.pumpAndSettle();
}

/// « Retirer » dans la fenêtre de confirmation.
Future<void> confirmRemoval(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('confirmRemove')));
  await done(tester);
}

Future<void> longPress(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f); // les albums du bas sont sous le mini-lecteur
  await tester.pump();
  await tester.longPress(f);
  await done(tester);
}

/// Un test sur iOS ou Android : le texte dit « iPhone » ou « téléphone ».
void phoneTest(
  String name,
  TargetPlatform platform,
  Future<void> Function(WidgetTester) body,
) => testWidgets(name, (tester) async {
  debugDefaultTargetPlatformOverride = platform;
  try {
    await body(tester);
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
});

void main() {
  setUpAll(loadFonts);

  group('feuille d\'appui long', () {
    phoneTest(
      '« Garder sur mon iPhone » tant que tout n\'est pas gardé',
      TargetPlatform.iOS,
      (tester) async {
        final f = await pumpKeep(tester);
        await longPress(tester, find.text('Studio Lafleur'));
        expect(find.text('Lire ensuite'), findsOneWidget);
        expect(find.text('Garder sur mon iPhone'), findsOneWidget);
        expect(find.text('Retirer du téléphone'), findsNothing);
        expect(find.text('Sélectionner…'), findsOneWidget);
        await tester.tap(find.text('Garder sur mon iPhone'));
        await done(tester);
        expect(f.downloader.kept, [pathsOf('Studio Lafleur')]);
      },
    );

    phoneTest(
      '« Retirer du téléphone » quand tout est gardé : copies effacées',
      TargetPlatform.iOS,
      (tester) async {
        final f = await pumpKeep(tester);
        await longPress(tester, find.text('Lafleur Surf').first);
        expect(find.text('Retirer du téléphone'), findsOneWidget);
        expect(find.text('Garder sur mon iPhone'), findsNothing);
        await tester.tap(find.text('Retirer du téléphone'));
        await done(tester);
        await confirmRemoval(tester);
        expect(f.downloader.forgotten, [pathsOf('Lafleur Surf')]);
        expect(f.downloader.kept, isEmpty);
      },
    );

    phoneTest('Android : « téléphone »', TargetPlatform.android, (
      tester,
    ) async {
      await pumpKeep(tester);
      await longPress(tester, find.text('Studio Lafleur'));
      expect(find.text('Garder sur mon téléphone'), findsOneWidget);
    });

    phoneTest(
      'un morceau de fichier local : ni Garder ni Retirer',
      TargetPlatform.iOS,
      (tester) async {
        await pumpKeep(
          tester,
          extra: [
            Track(
              path: '/musique/local.mp3',
              title: 'Local',
              artist: 'Moi',
              album: 'Fichiers',
              durationMs: 1000,
              hasCover: false,
              size: 1,
            ),
          ],
        );
        await longPress(tester, find.text('Fichiers'));
        expect(find.text('Lire ensuite'), findsOneWidget);
        expect(find.text('Garder sur mon iPhone'), findsNothing);
        expect(find.text('Retirer du téléphone'), findsNothing);
        expect(find.text('Sélectionner…'), findsNothing);
      },
    );

    phoneTest(
      '« Sélectionner… » ouvre l\'écran avec l\'album coché',
      TargetPlatform.iOS,
      (tester) async {
        await pumpKeep(tester);
        await longPress(tester, find.text('Summer Mix'));
        await tester.tap(find.text('Sélectionner…'));
        await done(tester);
        expect(find.byType(KeepScreen), findsOneWidget);
        expect(find.text('ALBUMS · 1 SÉLECTIONNÉ'), findsOneWidget);
        expect(find.textContaining('+ 480 Mo'), findsOneWidget);
      },
    );
  });

  group('écran 8', () {
    Future<KeepFixture> open(
      WidgetTester tester, {
      Set<String> pre = const {'Studio Lafleur', 'Summer Mix'},
      KeepResult? result,
    }) => pumpKeep(
      tester,
      home: KeepScreen(preselect: pre),
      downloader: result == null ? null : DemoDownloader(result: result),
    );

    phoneTest(
      'albums, durée · taille, déjà gardé, place et total',
      TargetPlatform.iOS,
      (tester) async {
        await open(tester);
        expect(find.text('ALBUMS · 2 SÉLECTIONNÉS'), findsOneWidget);
        for (final t in [
          'Studio Lafleur',
          'Lafleur Surf',
          'Summer Mix',
          'Night Drive',
          'Ports',
          '36 min · 310 Mo',
          '52 min · 480 Mo',
          '41 min · 390 Mo',
          '28 min · 260 Mo',
          'déjà gardé',
          "PLACE SUR L'IPHONE",
          'Annuler',
        ]) {
          expect(find.text(t), findsOneWidget, reason: t);
        }
        expect(
          find.text('4,2 Go utilisés sur 10 Go · + 790 Mo'),
          findsOneWidget,
        );
        expect(
          find.textContaining('Fichiers → Sur mon iPhone → LAFLEURMUSIC'),
          findsOneWidget,
        );
        expect(find.text('Garder sur mon iPhone · 790 Mo'), findsOneWidget);
      },
    );

    phoneTest(
      'cocher et décocher change le total ; « déjà gardé » ne se coche pas',
      TargetPlatform.iOS,
      (tester) async {
        await open(tester);
        await tester.tap(find.text('Night Drive'));
        await tester.pump();
        expect(find.text('ALBUMS · 3 SÉLECTIONNÉS'), findsOneWidget);
        expect(find.text('Garder sur mon iPhone · 1,2 Go'), findsOneWidget);
        await tester.tap(find.text('Summer Mix'));
        await tester.pump();
        expect(find.text('Garder sur mon iPhone · 700 Mo'), findsOneWidget);
        await tester.tap(find.text('Lafleur Surf'));
        await tester.pump();
        expect(find.text('ALBUMS · 2 SÉLECTIONNÉS'), findsOneWidget);
        await tester.tap(find.text('Studio Lafleur'));
        await tester.tap(find.text('Night Drive'));
        await tester.pump();
        expect(find.text('ALBUMS · 0 SÉLECTIONNÉ'), findsOneWidget);
        expect(
          find.text('Garder sur mon iPhone'),
          findsOneWidget,
        ); // bouton sans total
        final button = tester.widget<InkWell>(
          find.ancestor(
            of: find.text('Garder sur mon iPhone'),
            matching: find.byType(InkWell),
          ),
        );
        expect(button.onTap, isNull);
      },
    );

    phoneTest(
      'le bouton garde les morceaux cochés, dans l\'ordre, et ferme l\'écran',
      TargetPlatform.iOS,
      (tester) async {
        // l'écran est ouvert par-dessus l'Accueil : il se ferme une fois les morceaux en file
        final f = await pumpKeep(
          tester,
          downloader: DemoDownloader(result: const KeepResult.queued(13, 1)),
        );
        pushPhone(
          tester.element(find.byType(HomeScreen)),
          const KeepScreen(preselect: {'Studio Lafleur', 'Summer Mix'}),
        );
        await done(tester);
        await tester.tap(find.text('Garder sur mon iPhone · 790 Mo'));
        await done(tester);
        expect(f.downloader.kept, hasLength(1));
        expect(f.downloader.kept.single.toSet(), {
          ...pathsOf('Studio Lafleur'),
          ...pathsOf('Summer Mix'),
        });
        expect(find.byType(KeepScreen), findsNothing);
      },
    );

    phoneTest(
      'trop gros : le message dit combien il manque, l\'écran reste',
      TargetPlatform.iOS,
      (tester) async {
        await open(tester, result: KeepResult.tooBig(1288490189)); // 1,2 Go
        await tester.tap(find.text('Garder sur mon iPhone · 790 Mo'));
        await done(tester);
        expect(
          find.text('Pas assez de place : il faut encore 1,2 Go.'),
          findsOneWidget,
        );
        expect(find.byType(KeepScreen), findsOneWidget);
      },
    );

    phoneTest('trop gros : seul le manque est annoncé', TargetPlatform.iOS, (
      tester,
    ) async {
      // 790 Mo demandés, 500 Mo de place : il manque 290 Mo
      await open(tester, result: KeepResult.tooBig(290 * 1024 * 1024));
      await tester.tap(find.text('Garder sur mon iPhone · 790 Mo'));
      await done(tester);
      expect(
        find.text('Pas assez de place : il faut encore 290 Mo.'),
        findsOneWidget,
      );
    });

    phoneTest(
      'dossier choisi indisponible : le message, l\'écran reste',
      TargetPlatform.iOS,
      (tester) async {
        await open(tester, result: const KeepResult.folderUnavailable());
        await tester.tap(find.text('Garder sur mon iPhone · 790 Mo'));
        await done(tester);
        expect(
          find.text(
            "Le dossier choisi n'est pas disponible. Branche-le ou choisis-en un autre dans Sur mon iPhone.",
          ),
          findsOneWidget,
        );
        expect(find.byType(KeepScreen), findsOneWidget);
      },
    );

    phoneTest(
      'chosen folder unavailable (English, phone)',
      TargetPlatform.android,
      (tester) async {
        await pumpKeep(
          tester,
          home: const KeepScreen(preselect: {'Ports'}),
          locale: const Locale('en'),
          downloader: DemoDownloader(
            result: const KeepResult.folderUnavailable(),
          ),
        );
        await tester.tap(find.text('Keep on my phone · 260 MB'));
        await done(tester);
        expect(
          find.text(
            "The chosen folder isn't available. Reconnect it or pick another one in On my phone.",
          ),
          findsOneWidget,
        );
      },
    );

    phoneTest('en anglais', TargetPlatform.android, (tester) async {
      await pumpKeep(
        tester,
        home: const KeepScreen(preselect: {'Ports'}),
        locale: const Locale('en'),
        downloader: DemoDownloader(
          result: const KeepResult.tooBig(300 * 1024 * 1024),
        ),
      );
      expect(find.text('ALBUMS · 1 SELECTED'), findsOneWidget);
      expect(find.text('Keep on my phone · 260 MB'), findsOneWidget);
      await tester.tap(find.text('Keep on my phone · 260 MB'));
      await done(tester);
      expect(
        find.text('Not enough space: 300 MB more needed.'),
        findsOneWidget,
      );
    });

    phoneTest(
      'Android : accès au dossier Musique refusé',
      TargetPlatform.android,
      (tester) async {
        final d = DemoDownloader(result: const KeepResult.queued(2, 1))
          ..accessDenied = true;
        await pumpKeep(
          tester,
          home: const KeepScreen(preselect: {'Ports'}),
          downloader: d,
        );
        expect(find.textContaining('Musique/LAFLEURMUSIC'), findsOneWidget);
        await tester.tap(find.text('Garder sur mon téléphone · 260 Mo'));
        await done(tester);
        expect(
          find.text(
            "L'appli n'a pas le droit d'écrire dans Musique. Autorise-la dans les réglages du téléphone.",
          ),
          findsOneWidget,
        );
      },
    );
  });

  group('morceaux grisés', () {
    Future<KeepFixture> studio(WidgetTester tester) async {
      final f = await pumpKeep(tester);
      await tester.ensureVisible(find.text('Studio Lafleur'));
      await tester.pump();
      await tester.tap(find.text('Studio Lafleur'));
      await done(tester);
      expect(find.byType(AlbumScreen), findsOneWidget);
      return f;
    }

    phoneTest(
      '« Kavinsky · pas sur l\'iPhone », un toucher ne joue rien',
      TargetPlatform.iOS,
      (tester) async {
        final f = await studio(tester);
        expect(find.text("Kavinsky · pas sur l'iPhone"), findsOneWidget);
        await tester.tap(find.text('Night Swim'));
        await tester.pump();
        expect(f.player.calls, isEmpty);
        expect(
          find.text("Pas sur l'iPhone : rien à jouer hors ligne."),
          findsOneWidget,
        );
      },
    );

    phoneTest(
      'un morceau jouable démarre, avec toute la liste',
      TargetPlatform.iOS,
      (tester) async {
        final f = await studio(tester);
        await tester.tap(find.text('Ocean Drive'));
        await tester.pump();
        expect(f.player.calls, ['play']);
        expect(f.player.lastIndex, 0);
        expect(find.textContaining('rien à jouer'), findsNothing);
      },
    );

    phoneTest('Android : « pas sur le téléphone »', TargetPlatform.android, (
      tester,
    ) async {
      await studio(tester);
      expect(find.text('Kavinsky · pas sur le téléphone'), findsOneWidget);
    });

    phoneTest(
      'l\'appui long d\'un morceau grisé propose de le garder',
      TargetPlatform.iOS,
      (tester) async {
        final f = await studio(tester);
        await longPress(tester, find.text('Night Swim'));
        await tester.tap(find.text('Garder sur mon iPhone'));
        await done(tester);
        expect(f.downloader.kept.single, [DemoLibrary.notOnPhonePaths.single]);
      },
    );
  });

  group('⬇ de l\'album et de l\'Accueil', () {
    phoneTest(
      'le rond ⬇ garde l\'album, et le retire quand tout y est',
      TargetPlatform.iOS,
      (tester) async {
        final f = await pumpKeep(tester);
        await tester.ensureVisible(find.text('Studio Lafleur'));
        await tester.pump();
        await tester.tap(find.text('Studio Lafleur'));
        await done(tester);
        await tester.tap(find.byTooltip('Garder sur mon iPhone'));
        await tester.pump();
        expect(f.downloader.kept.single, pathsOf('Studio Lafleur'));
      },
    );

    phoneTest(
      'le rond ⬇ rose d\'un album gardé ne retire rien, il dit comment',
      TargetPlatform.iOS,
      (tester) async {
        final f = await pumpKeep(tester);
        await tester.ensureVisible(find.text('Lafleur Surf').first);
        await tester.tap(find.text('Lafleur Surf').first);
        await done(tester);
        await tester.tap(find.byIcon(Icons.arrow_downward_rounded).first);
        await tester.pump();
        expect(f.downloader.forgotten, isEmpty);
        expect(f.downloader.kept, isEmpty);
        expect(
          find.text(
            "Déjà sur l'iPhone. Appui long sur un morceau pour le retirer.",
          ),
          findsOneWidget,
        );
      },
    );

    phoneTest(
      'Lecture / Aléatoire sans rien de jouable : le message, pas de lecture',
      TargetPlatform.iOS,
      (tester) async {
        final f = await pumpKeep(
          tester,
          notOnPhone: {
            for (final t in DemoLibrary.remote)
              if (t.album == 'Ports') t.path,
          },
        );
        await tester.ensureVisible(find.text('Ports'));
        await tester.tap(find.text('Ports'));
        await done(tester);
        await tester.tap(find.text('Lecture'));
        await tester.pump();
        expect(f.player.calls, isEmpty);
        expect(
          find.text("Pas sur l'iPhone : rien à jouer hors ligne."),
          findsOneWidget,
        );
        await tester.tap(find.text('Aléatoire'));
        await tester.pump();
        expect(f.player.calls, isEmpty);
      },
    );

    phoneTest(
      '⬇ rose après le nom d\'un album gardé en entier, pas les autres',
      TargetPlatform.iOS,
      (tester) async {
        await pumpKeep(tester);
        final mark = find.byIcon(Icons.arrow_downward_rounded);
        expect(mark, findsOneWidget);
        final row = find.ancestor(of: mark, matching: find.byType(Row)).first;
        expect(
          find.descendant(of: row, matching: find.text('Lafleur Surf')),
          findsOneWidget,
        );
      },
    );
  });
}
