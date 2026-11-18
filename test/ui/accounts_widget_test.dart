import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/player/media_resolver.dart';
import 'package:lafleurmusic/sources/accounts.dart';
import 'package:lafleurmusic/sources/source.dart';
import 'package:lafleurmusic/ui/phone/account_form.dart';
import 'package:lafleurmusic/ui/phone/accounts_screen.dart';
import 'package:lafleurmusic/ui/phone/home_screen.dart';

import 'accounts_fixture.dart';
import 'fonts.dart';
import 'phone_fixture.dart';

Finder field(String key) => find.byKey(ValueKey('account-$key'));

Future<void> fillForm(
  WidgetTester tester, {
  String name = 'Navidrome maison',
  String address = 'http://192.168.1.20:4533',
  String user = 'johnny',
  String password = 'secret',
}) async {
  await tester.enterText(field('name'), name);
  await tester.enterText(field('address'), address);
  await tester.enterText(field('user'), user);
  await tester.enterText(field('password'), password);
  await tester.pump();
}

Future<void> tapAndSettle(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await tester.pump();
  await settle(tester);
}

void main() {
  setUpAll(loadFonts);

  group('écran 7, Ajouter un compte', () {
    final messages = {
      TestResult.ok: 'Ça marche !',
      TestResult.unreachable: 'Serveur injoignable',
      TestResult.wrongPassword: 'Mauvais nom ou mot de passe',
      TestResult.headerRefused: 'En-tête refusé par le proxy',
      TestResult.notSubsonic: "Ce n'est pas un serveur Subsonic",
    };
    for (final MapEntry(key: result, value: text) in messages.entries) {
      testWidgets('« Tester » → $text', (tester) async {
        final f = await pumpAccounts(
          tester,
          seed: const [],
          home: () => const AccountFormScreen(),
        );
        f.draftResult = result;
        await fillForm(tester);
        await tapAndSettle(tester, find.text('Tester'));
        expect(find.text(text), findsOneWidget);
        // une source temporaire faite du formulaire, rien d'enregistré
        expect(f.drafts, hasLength(1));
        final (d, password) = f.drafts.single;
        expect(d.base, Uri.parse('http://192.168.1.20:4533'));
        expect(d.user, 'johnny');
        expect(password, 'secret');
        expect(await f.list(tester), isEmpty);
      });
    }

    testWidgets('le mot de passe est masqué', (tester) async {
      await pumpAccounts(
        tester,
        seed: const [],
        home: () => const AccountFormScreen(),
      );
      final tf = tester.widget<TextField>(
        find.descendant(
          of: field('password'),
          matching: find.byType(TextField),
        ),
      );
      expect(tf.obscureText, isTrue);
    });

    testWidgets('« + Ajouter un en-tête » ajoute une paire, ✕ la retire', (
      tester,
    ) async {
      final f = await pumpAccounts(
        tester,
        seed: const [],
        home: () => const AccountFormScreen(),
      );
      expect(find.byKey(const ValueKey('header-0')), findsNothing);
      await tapAndSettle(tester, find.text('+ Ajouter un en-tête'));
      await tapAndSettle(tester, find.text('+ Ajouter un en-tête'));
      expect(find.byKey(const ValueKey('header-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('header-1')), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('header-0-name')),
        'CF-Access-Client-Id',
      );
      await tester.enterText(
        find.byKey(const ValueKey('header-0-value')),
        'abc123',
      );
      await tapAndSettle(tester, find.byKey(const ValueKey('header-1-remove')));
      expect(find.byKey(const ValueKey('header-1')), findsNothing);
      expect(find.byKey(const ValueKey('header-0')), findsOneWidget);
      // les en-têtes partent avec « Tester »
      await fillForm(tester);
      await tapAndSettle(tester, find.text('Tester'));
      expect(f.drafts.single.$1.headers, {'CF-Access-Client-Id': 'abc123'});
    });

    testWidgets('« Enregistrer » → Accounts.add puis LibrarySync.run', (
      tester,
    ) async {
      final f = await pumpAccounts(
        tester,
        seed: const [],
        home: () => const AccountFormScreen(),
      );
      await fillForm(tester);
      await tapAndSettle(tester, find.text('+ Ajouter un en-tête'));
      await tester.enterText(
        find.byKey(const ValueKey('header-0-name')),
        'CF-Access-Client-Id',
      );
      await tester.enterText(
        find.byKey(const ValueKey('header-0-value')),
        'abc123',
      );
      await tapAndSettle(tester, find.text('Enregistrer'));
      final list = await f.list(tester);
      expect(list.map((a) => a.name), ['Navidrome maison']);
      final a = list.single;
      expect(a.type, AccountType.subsonic);
      expect(a.base, Uri.parse('http://192.168.1.20:4533'));
      expect(a.user, 'johnny');
      expect(await tester.runAsync(() => f.accounts.password(a.id)), 'secret');
      expect(await tester.runAsync(() => f.accounts.headers(a.id)), {
        'CF-Access-Client-Id': 'abc123',
      });
      expect(f.synced, [a.id]);
    });

    testWidgets('adresse ou utilisateur manquant : rien d’enregistré', (
      tester,
    ) async {
      final f = await pumpAccounts(
        tester,
        seed: const [],
        home: () => const AccountFormScreen(),
      );
      await fillForm(tester, address: '');
      await tapAndSettle(tester, find.text('Enregistrer'));
      expect(await f.list(tester), isEmpty);
      expect(f.synced, isEmpty);
      expect(find.textContaining('Il manque'), findsOneWidget);
    });

    testWidgets('Jellyfin et Plex visibles mais grisés « bientôt »', (
      tester,
    ) async {
      await pumpAccounts(
        tester,
        seed: const [],
        home: () => const AccountFormScreen(),
      );
      expect(find.text('Subsonic'), findsOneWidget);
      expect(find.text('Jellyfin'), findsOneWidget);
      expect(find.text('Plex'), findsOneWidget);
      expect(find.textContaining('bientôt'), findsWidgets);
      await tapAndSettle(tester, find.text('Plex'));
      expect(
        tester
            .widget<AccountTypeSegment>(find.byType(AccountTypeSegment))
            .value,
        AccountType.subsonic,
      );
    });
  });

  group('écran 6, Réglages → Comptes', () {
    testWidgets('les comptes, leur état (connecté / absent), l’ordre', (
      tester,
    ) async {
      await pumpAccounts(
        tester,
        home: () => const AccountsScreen(),
        results: (l) => {l[1].id: TestResult.unreachable},
      );
      expect(find.text('MES COMPTES'), findsOneWidget);
      expect(find.text('Navidrome maison'), findsWidgets);
      expect(find.text('Subsonic · 192.168.1.20:4533'), findsOneWidget);
      expect(find.text('Jellyfin · 2 en-têtes'), findsOneWidget);
      expect(find.text('● connecté'), findsNWidgets(2));
      expect(find.text('● absent'), findsOneWidget);
      expect(find.text('+ Ajouter un compte'), findsOneWidget);
    });

    testWidgets('glisser ⋮⋮ → reorder', (tester) async {
      final f = await pumpAccounts(tester, home: () => const AccountsScreen());
      final before = await f.list(tester);
      final grip = find.byKey(ValueKey('grip-${before.first.id}'));
      final g = await tester.startGesture(tester.getCenter(grip));
      await tester.pump(const Duration(milliseconds: 100));
      for (var i = 0; i < 6; i++) {
        await g.moveBy(const Offset(0, 15));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await g.up();
      await tester.pumpAndSettle();
      await settle(tester);
      final after = await f.list(tester);
      expect(after.map((a) => a.name), [
        'Jellyfin de Max',
        'Navidrome maison',
        'Plex',
      ]);
    });

    testWidgets('Affichage : Un compte actif, Tout et Perso « bientôt »', (
      tester,
    ) async {
      await pumpAccounts(tester, home: () => const AccountsScreen());
      await tester.ensureVisible(find.text('AFFICHAGE'));
      expect(find.text('Un compte'), findsOneWidget);
      expect(find.textContaining('Tout'), findsOneWidget);
      expect(find.textContaining('Perso'), findsOneWidget);
      expect(find.textContaining('bientôt'), findsWidgets);
      await tapAndSettle(tester, find.textContaining('Perso'));
      expect(
        tester.widget<DisplaySegment>(find.byType(DisplaySegment)).value,
        AccountsDisplay.one,
      );
    });

    testWidgets('« + Ajouter un compte » ouvre l’écran 7', (tester) async {
      await pumpAccounts(tester, home: () => const AccountsScreen());
      await tapAndSettle(tester, find.text('+ Ajouter un compte'));
      await tester.pumpAndSettle();
      expect(find.byType(AccountFormScreen), findsOneWidget);
      expect(find.text('Comptes'), findsOneWidget); // ‹ Comptes
    });

    testWidgets(
      'toucher un compte : écran 7 prérempli, mot de passe vide = inchangé',
      (tester) async {
        var built = 0;
        final resolver = MediaResolver((id) async {
          built++;
          return ProbeSource(id, TestResult.ok);
        });
        final f = await pumpAccounts(
          tester,
          home: () => const AccountsScreen(),
          resolver: resolver,
        );
        final jelly = (await f.list(tester))[1];
        await tester.runAsync(() => resolver.source(jelly.id));
        expect(built, 1);
        await tapAndSettle(tester, find.text('Jellyfin de Max').first);
        await tester.pumpAndSettle();
        await settle(tester);
        expect(find.byType(AccountFormScreen), findsOneWidget);
        String text(String k) => tester
            .widget<TextField>(
              find.descendant(of: field(k), matching: find.byType(TextField)),
            )
            .controller!
            .text;
        expect(text('name'), 'Jellyfin de Max');
        expect(text('address'), 'https://jellyfin.max.example');
        expect(text('user'), 'johnny');
        expect(text('password'), '');
        expect(
          tester
              .widget<TextField>(
                find.descendant(
                  of: find.byKey(const ValueKey('header-0-name')),
                  matching: find.byType(TextField),
                ),
              )
              .controller!
              .text,
          'CF-Access-Client-Id',
        );
        await tester.enterText(field('name'), 'Jellyfin de Maxime');
        await tapAndSettle(tester, find.text('Enregistrer'));
        await tester.pumpAndSettle();
        final after = (await f.list(tester))[1];
        expect(after.name, 'Jellyfin de Maxime');
        expect(after.id, jelly.id);
        expect(
          await tester.runAsync(() => f.accounts.password(jelly.id)),
          'secret',
        );
        // l'adresse ou les en-têtes ont pu changer : la source du lecteur est refaite
        await tester.runAsync(() => resolver.source(jelly.id));
        expect(built, 2);
        expect(find.byType(AccountsScreen), findsOneWidget);
      },
    );

    testWidgets(
      'Enregistrer avant que les en-têtes soient lus : en-têtes gardés',
      (tester) async {
        final slow = SlowSecretStore();
        final f = await pumpAccounts(
          tester,
          home: () => const AccountsScreen(),
          secretStore: slow,
        );
        final jelly = (await f.list(tester))[1];
        final before = slow.data['account.${jelly.id}.headers'];
        slow.armed = true;
        await tapAndSettle(tester, find.text('Jellyfin de Max').first);
        await tester.pumpAndSettle();
        expect(find.byType(AccountFormScreen), findsOneWidget);
        // tout de suite, en-têtes pas encore lus : rien ne part
        await tapAndSettle(tester, find.text('Enregistrer'));
        await tester.pumpAndSettle();
        expect(find.byType(AccountFormScreen), findsOneWidget);
        expect(slow.data['account.${jelly.id}.headers'], before);
        expect(f.synced, isEmpty);
        // lus : enregistrer garde les mêmes en-têtes
        slow.release();
        await settle(tester);
        await tapAndSettle(tester, find.text('Enregistrer'));
        await tester.pumpAndSettle();
        await settle(tester);
        expect(find.byType(AccountsScreen), findsOneWidget);
        expect(slow.data['account.${jelly.id}.headers'], before);
        expect(f.synced, [jelly.id]);
      },
    );

    testWidgets(
      '« Supprimer le compte » demande confirmation, ne touche pas au serveur',
      (tester) async {
        final f = await pumpAccounts(
          tester,
          home: () => const AccountsScreen(),
        );
        await tapAndSettle(tester, find.text('Plex').first);
        await tester.pumpAndSettle();
        await tapAndSettle(tester, find.text('Supprimer le compte'));
        await tester.pumpAndSettle();
        expect(find.text('Supprimer « Plex » ?'), findsOneWidget);
        expect(
          find.textContaining('rien n’est effacé sur le serveur'),
          findsOneWidget,
        );
        await tapAndSettle(tester, find.text('Annuler'));
        await tester.pumpAndSettle();
        expect(await f.list(tester), hasLength(3));
        await tapAndSettle(tester, find.text('Supprimer le compte'));
        await tester.pumpAndSettle();
        await tapAndSettle(tester, find.text('Supprimer'));
        await tester.pumpAndSettle();
        await settle(tester);
        expect((await f.list(tester)).map((a) => a.name), [
          'Navidrome maison',
          'Jellyfin de Max',
        ]);
        expect(find.byType(AccountsScreen), findsOneWidget);
      },
    );
  });

  group('premier lancement et Accueil', () {
    testWidgets('aucun compte → écran 7 ; enregistré → Accueil', (
      tester,
    ) async {
      final f = await pumpAccounts(tester, seed: const []);
      expect(find.byType(AccountFormScreen), findsOneWidget);
      expect(find.byType(HomeScreen), findsNothing);
      await fillForm(tester);
      await tapAndSettle(tester, find.text('Enregistrer'));
      await tester.pumpAndSettle();
      await settle(tester);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(f.synced, hasLength(1));
    });

    testWidgets('⚙︎ ouvre Réglages → Comptes', (tester) async {
      await pumpAccounts(tester);
      expect(find.byType(HomeScreen), findsOneWidget);
      await tapAndSettle(tester, find.byIcon(Icons.settings_rounded));
      await tester.pumpAndSettle();
      expect(find.byType(AccountsScreen), findsOneWidget);
    });

    testWidgets('tirer la liste vers le bas synchronise tous les comptes', (
      tester,
    ) async {
      final f = await pumpAccounts(tester);
      await tester.fling(find.text('BIBLIOTHÈQUE'), const Offset(0, 400), 1000);
      // l'indicateur tourne tant que la synchro (base hors horloge simulée) n'est pas finie
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 300));
        await settle(tester);
      }
      await tester.pumpAndSettle();
      expect(f.synced, hasLength(3));
    });

    testWidgets('« Hors ligne » quand aucun compte ne répond', (tester) async {
      final f = await pumpAccounts(
        tester,
        results: (l) => {for (final a in l) a.id: TestResult.unreachable},
      );
      expect(find.text('Hors ligne'), findsNothing);
      f.syncComplete = false;
      await tester.runAsync(f.service.syncAll);
      await tester.pump();
      expect(find.text('Hors ligne'), findsOneWidget);
      f.syncComplete = true;
      await tester.runAsync(f.service.syncAll);
      await tester.pump();
      expect(find.text('Hors ligne'), findsNothing);
    });
  });
}
