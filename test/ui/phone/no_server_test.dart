import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/demo/demo_offline.dart';
import 'package:lafleurmusic/library/models.dart';
import 'package:lafleurmusic/offline/device.dart';
import 'package:lafleurmusic/offline/local_folder.dart';
import 'package:lafleurmusic/settings.dart';
import 'package:lafleurmusic/ui/phone/account_form.dart';

import '../accounts_fixture.dart';
import '../accounts_widget_test.dart' show fillForm, tapAndSettle;
import '../phone_fixture.dart' show settle;

class _FolderSpy implements LocalFolder {
  int rescans = 0;
  @override
  Future<void> rescan() async => rescans++;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

const _localTrack = Track(
  path: '/music/LAFLEURMUSIC/a.mp3',
  title: 'Un morceau',
  artist: 'Quelqu’un',
  album: 'Un album',
  durationMs: 180000,
  hasCover: false,
  size: 1000,
);

/// Le test, puis la plateforme remise (avant la vérification de fin de test du banc).
void phoneTest(String name, Future<void> Function(WidgetTester) body) {
  testWidgets(name, (tester) async {
    try {
      await body(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

void main() {
  Future<({AccountsFixture f, DemoDevice device, _FolderSpy folder})> pump(
    WidgetTester tester, {
    bool localOnly = false,
    bool android = false,
  }) async {
    debugDefaultTargetPlatformOverride = android
        ? TargetPlatform.android
        : TargetPlatform.iOS;
    final device = DemoDevice(
      root: android
          ? '/storage/emulated/0/Music/LAFLEURMUSIC'
          : '/docs/LAFLEURMUSIC',
    );
    final folder = _FolderSpy();
    final f = await pumpAccounts(
      tester,
      seed: const [],
      device: device,
      localFolder: folder,
      configure: (s) => s.localOnly = localOnly,
    );
    return (f: f, device: device, folder: folder);
  }

  phoneTest(
    'A : premier lancement, le bouton « Juste la musique de mon iPhone »',
    (tester) async {
      final r = await pump(tester);
      expect(find.text('OU'), findsOneWidget);
      expect(find.text('Juste la musique de mon iPhone'), findsOneWidget);
      expect(
        find.text(
          'Pas de serveur ? Pas de souci. Tu pourras ajouter un compte plus tard.',
        ),
        findsOneWidget,
      );
      await tapAndSettle(tester, find.text('Juste la musique de mon iPhone'));
      expect(r.f.settings.localOnly, isTrue);
      expect(r.f.saves, 1);
      expect(find.byType(AccountFormScreen), findsNothing);
      expect(find.text('Pas encore de musique'), findsOneWidget);
    },
  );

  phoneTest('A sur Android : « … de mon téléphone »', (tester) async {
    await pump(tester, android: true);
    expect(find.text('Juste la musique de mon téléphone'), findsOneWidget);
  });

  phoneTest('relance : le choix est gardé, plus d’écran de compte', (
    tester,
  ) async {
    await pump(tester, localOnly: true);
    expect(find.byType(AccountFormScreen), findsNothing);
    expect(find.text('Pas encore de musique'), findsOneWidget);
  });

  phoneTest('le choix est écrit dans settings.json et relu', (tester) async {
    final s = AppSettings()..localOnly = true;
    final back = await tester.runAsync(() async {
      final dir = Directory.systemTemp.createTempSync('nosrv');
      final file = File('${dir.path}/settings.json');
      await s.save(file);
      final r = await AppSettings.load(file);
      dir.deleteSync(recursive: true);
      return r;
    });
    expect(back!.localOnly, isTrue);
    expect(AppSettings().localOnly, isFalse);
  });

  phoneTest('B : texte iPhone avec le chemin de Fichiers', (tester) async {
    await pump(tester, localOnly: true);
    expect(
      find.textContaining(
        'Mets tes fichiers dans l’app Fichiers',
        findRichText: true,
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('Sur mon iPhone › LAFLEURMUSIC', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'Ils apparaissent ici tout seuls',
        findRichText: true,
      ),
      findsOneWidget,
    );
  });

  phoneTest('B sur Android : le chemin du dossier choisi', (tester) async {
    await pump(tester, localOnly: true, android: true);
    expect(
      find.textContaining(
        '/storage/emulated/0/Music/LAFLEURMUSIC',
        findRichText: true,
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Fichiers', findRichText: true), findsNothing);
  });

  phoneTest('B : « Choisir un autre dossier » adopte le dossier choisi', (
    tester,
  ) async {
    final r = await pump(tester, localOnly: true);
    r.device.picked = const PickedFolder('/docs/Autre');
    await tapAndSettle(tester, find.text('Choisir un autre dossier'));
    expect(r.device.picks, 1);
    expect(r.device.committed.single.path, '/docs/Autre');
    expect(r.folder.rescans, 1);
  });

  phoneTest('B : « Choisir un autre dossier » annulé ne change rien', (
    tester,
  ) async {
    final r = await pump(tester, localOnly: true);
    r.device.picked = null;
    await tapAndSettle(tester, find.text('Choisir un autre dossier'));
    expect(r.device.committed, isEmpty);
    expect(r.folder.rescans, 0);
  });

  phoneTest('B : « Ajouter un compte » ouvre le formulaire, avec retour', (
    tester,
  ) async {
    await pump(tester, localOnly: true);
    await tapAndSettle(tester, find.text('Ajouter un compte'));
    expect(find.byType(AccountFormScreen), findsOneWidget);
    expect(find.text('‹ '), findsOneWidget); // le retour est là
    expect(
      find.text('OU'),
      findsNothing,
    ); // pas de « juste la musique » hors premier lancement
  });

  phoneTest('ajouter un compte plus tard : enregistré, l’Accueil reste', (
    tester,
  ) async {
    final r = await pump(tester, localOnly: true);
    await tapAndSettle(tester, find.text('Ajouter un compte'));
    await tester.pump(const Duration(seconds: 1)); // la page a fini de glisser
    await fillForm(tester);
    await tapAndSettle(tester, find.text('Enregistrer'));
    expect((await r.f.list(tester)).map((a) => a.name), ['Navidrome maison']);
    await tester.pump(const Duration(seconds: 1)); // la page a fini de se fermer
    expect(find.byType(AccountFormScreen), findsNothing);
    expect(find.text('Navidrome maison'), findsOneWidget); // sa puce
  });

  phoneTest('C : un morceau posé → l’Accueil habituel, sans « Comptes »', (
    tester,
  ) async {
    final r = await pump(tester, localOnly: true);
    expect(find.text('Pas encore de musique'), findsOneWidget);
    await tester.runAsync(() => r.f.db.upsertTracks([_localTrack]));
    await settle(tester);
    expect(find.text('Pas encore de musique'), findsNothing);
    expect(find.text('Albums'), findsOneWidget);
    expect(find.text('Un album'), findsOneWidget);
    expect(find.text('Comptes'), findsNothing);
  });

  phoneTest(
    'premier lancement sans choix : un compte enregistré mène à l’Accueil',
    (tester) async {
      final r = await pump(tester);
      await fillForm(tester);
      await tapAndSettle(tester, find.text('Enregistrer'));
      expect(find.byType(AccountFormScreen), findsNothing);
      expect(r.f.settings.localOnly, isFalse);
    },
  );
}
