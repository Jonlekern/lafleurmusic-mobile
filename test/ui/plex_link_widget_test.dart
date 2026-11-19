import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/sources/accounts.dart';
import 'package:lafleurmusic/sources/plex.dart';
import 'package:lafleurmusic/sources/plex_link.dart';
import 'package:lafleurmusic/sources/source.dart';
import 'package:lafleurmusic/ui/phone/account_form.dart';
import 'package:lafleurmusic/ui/phone/plex_link_screen.dart';

import '../sources/fake_plex.dart';
import 'accounts_fixture.dart';
import 'plex_fixture.dart';
import 'fonts.dart';
import 'phone_fixture.dart';

Future<void> tapIt(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await tester.pump();
  await settle(tester);
  await tester.pump(const Duration(milliseconds: 600)); // page transition
  await settle(tester);
}

/// « + Ajouter un compte » → Plex → [name] → « Se connecter avec Plex ».
Future<void> openCode(WidgetTester tester, {String name = ''}) async {
  await tapIt(tester, find.text('+ Ajouter un compte'));
  await tapIt(tester, find.text('Plex'));
  if (name.isNotEmpty) {
    await tester.enterText(find.byKey(const ValueKey('account-name')), name);
  }
  await tapIt(tester, find.text('Se connecter avec Plex'));
  await settle(tester);
}

/// One poll more (2 s), then the saving.
Future<void> nextPoll(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 2));
  await settle(tester);
  await settle(tester);
  await tester.pump(const Duration(milliseconds: 600)); // pages closing
  await settle(tester);
}

void main() {
  setUpAll(loadFonts);

  testWidgets('onglet Plex : pas de mot de passe, « Se connecter avec Plex »', (
    tester,
  ) async {
    await pumpWithPlex(
      tester,
      FakePlexTv(),
      home: () => const AccountFormScreen(),
    );
    await tapIt(tester, find.text('Plex'));
    expect(find.text('NOM DU COMPTE'), findsOneWidget);
    expect(find.textContaining('Pas de mot de passe à taper ici.'), findsOne);
    expect(find.text('Se connecter avec Plex'), findsOneWidget);
    expect(find.byKey(const ValueKey('account-address')), findsNothing);
    expect(find.byKey(const ValueKey('account-password')), findsNothing);
    expect(find.text('Tester'), findsNothing);
  });

  testWidgets('un seul serveur : le code, puis le compte sans écran de choix', (
    tester,
  ) async {
    final tv = FakePlexTv()
      ..resources = [homeResource]
      ..validateAfter = 2;
    final f = await pumpWithPlex(tester, tv);
    await openCode(tester, name: 'Plex maison');
    expect(find.text('Ton code Plex'), findsOneWidget);
    for (final c in ['K', '7', 'Q', 'X']) {
      expect(find.text(c), findsOneWidget);
    }
    expect(
      find.text(
        'Va sur plex.tv/link,\nconnecte-toi et tape ce code.',
        findRichText: true,
      ),
      findsOneWidget,
    );
    expect(find.text('Ouvrir plex.tv/link'), findsOneWidget);
    expect(find.text('Copier le code'), findsOneWidget);
    expect(find.text('En attente de Plex…'), findsOneWidget);
    expect(find.text('Le code marche 15 minutes.'), findsOneWidget);
    expect(find.text('‹ '), findsWidgets);
    expect(find.text('Annuler'), findsOneWidget);
    expect(await f.list(tester), isEmpty);

    await nextPoll(tester);
    final list = await f.list(tester);
    expect(list, hasLength(1));
    final a = list.single;
    expect(a.type, AccountType.plex);
    expect(a.name, 'Plex maison');
    expect(a.base.host, homeLocal);
    expect(f.secrets.data[PlexSource.tokenKey(a.id)], 'server-token-home');
    // the plex.tv token and who it belongs to (relink, address refresh)
    expect(f.secrets.data[PlexSource.accountTokenKey(a.id)], 'user-token-1');
    expect(f.secrets.data[PlexSource.userKey(a.id)], 'user-uuid-1');
    // the code screen and the form are gone: back on the accounts
    expect(find.byType(PlexLinkScreen), findsNothing);
    expect(find.byType(AccountFormScreen), findsNothing);
    expect(find.text('Plex maison'), findsOneWidget);
    // the token is never on screen
    expect(find.textContaining('token'), findsNothing);
  });

  testWidgets('nom laissé vide : le nom du serveur', (tester) async {
    final tv = FakePlexTv()..resources = [homeResource];
    final f = await pumpWithPlex(tester, tv);
    await openCode(tester);
    await settle(tester);
    expect((await f.list(tester)).single.name, 'Maison');
  });

  testWidgets('Copier le code, Ouvrir plex.tv/link', (tester) async {
    final tv = FakePlexTv()..validateAfter = null;
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final opened = <Uri>[];
    await pumpWithPlex(
      tester,
      tv,
      home: () => PlexLinkScreen(
        openUrl: (u) async {
          opened.add(u);
          return true;
        },
      ),
    );
    await tapIt(tester, find.text('Copier le code'));
    expect(copied, 'K7QX');
    await tapIt(tester, find.text('Ouvrir plex.tv/link'));
    expect(opened, [Uri.parse('https://plex.tv/link')]);
  });

  testWidgets('deux serveurs : « C\'est bon ✓ », choix, Ajouter', (
    tester,
  ) async {
    final tv = FakePlexTv();
    final f = await pumpWithPlex(tester, tv);
    await openCode(tester, name: 'Au bureau');
    await settle(tester);
    expect(find.text("C'est bon ✓"), findsOneWidget);
    expect(find.text('Ton compte Plex a 2 serveurs. Lequel ?'), findsOneWidget);
    expect(find.text('Maison'), findsOneWidget);
    expect(find.text('À la maison · 2 bibliothèques musique'), findsOneWidget);
    expect(find.text('Bureau'), findsOneWidget);
    expect(find.text('Par Internet · 1 bibliothèque musique'), findsOneWidget);
    expect(find.text('Retour'), findsOneWidget);
    expect(await f.list(tester), isEmpty);
    await tapIt(tester, find.text('Bureau'));
    await tapIt(tester, find.text('Ajouter'));
    await settle(tester);
    final a = (await f.list(tester)).single;
    expect(a.name, 'Au bureau');
    expect(a.base.host, officeRemote);
    expect(f.secrets.data[PlexSource.tokenKey(a.id)], 'server-token-office');
    final server = PlexServer.fromJson(
      jsonDecode(f.secrets.data[PlexSource.serverKey(a.id)]!),
    );
    expect(server.machineId, 'mach-office');
  });

  testWidgets(
    'Focus 1 : code jamais validé → « Code expiré », rien d\'enregistré, « Nouveau code »',
    (tester) async {
      final tv = FakePlexTv()
        ..validateAfter = null
        ..expiresIn = 60;
      final f = await pumpWithPlex(tester, tv);
      await openCode(tester);
      await tester.pump(const Duration(seconds: 59));
      expect(find.text('Code expiré'), findsNothing);
      await tester.pump(const Duration(seconds: 2));
      await settle(tester);
      expect(find.text('Code expiré'), findsOneWidget);
      expect(find.text('Nouveau code'), findsOneWidget);
      expect(find.text('En attente de Plex…'), findsNothing);
      expect(await f.list(tester), isEmpty);
      final polls = tv.log.length;
      await tester.pump(const Duration(minutes: 1));
      expect(tv.log, hasLength(polls)); // the polling stopped
      await tapIt(tester, find.text('Nouveau code'));
      for (final c in ['B', '2', 'R', 'T']) {
        expect(find.text(c), findsOneWidget);
      }
      expect(find.text('En attente de Plex…'), findsOneWidget);
      expect(tv.pinsMade, 2);
      // leave: the second wait stops too
      await tapIt(tester, find.text('Annuler'));
    },
  );

  testWidgets('Annuler : l\'attente s\'arrête avec l\'écran', (tester) async {
    final tv = FakePlexTv()..validateAfter = null;
    final f = await pumpWithPlex(tester, tv);
    await openCode(tester);
    await tester.pump(const Duration(seconds: 4));
    await tapIt(tester, find.text('Annuler'));
    expect(find.byType(PlexLinkScreen), findsNothing);
    final n = tv.log.length;
    await tester.pump(const Duration(seconds: 30));
    expect(tv.log, hasLength(n));
    expect(await f.list(tester), isEmpty);
  });

  testWidgets('modifier un compte Plex : le nom seul, le jeton reste', (
    tester,
  ) async {
    late Account acc;
    final f = await pumpWithPlex(
      tester,
      FakePlexTv(),
      seed: plexSeed,
      results: (l) {
        acc = l.single;
        return const {};
      },
    );
    f.secrets.data[PlexSource.tokenKey(acc.id)] = 'server-token-home';
    await tapIt(tester, find.text('Plex maison'));
    expect(find.byType(AccountFormScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('account-address')), findsNothing);
    expect(find.text('Se connecter avec Plex'), findsNothing);
    // the type stays: a tap on another one changes nothing
    await tapIt(tester, find.text('Subsonic'));
    expect(find.text('NOM DU COMPTE'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('account-name')),
      'Plex du salon',
    );
    await tapIt(tester, find.text('Enregistrer'));
    final a = (await f.list(tester)).single;
    expect(a.id, acc.id);
    expect(a.name, 'Plex du salon');
    expect(a.type, AccountType.plex);
    expect(f.secrets.data[PlexSource.tokenKey(acc.id)], 'server-token-home');
    expect(find.byType(AccountFormScreen), findsNothing);
  });

  group('Focus 5 : « À reconnecter »', () {
    Future<(AccountsFixture, Account)> pumpRevoked(
      WidgetTester tester,
      FakePlexTv tv, {
      String machine = 'mach-home',
    }) async {
      late Account acc;
      final f = await pumpWithPlex(
        tester,
        tv,
        seed: plexSeed,
        results: (l) {
          acc = l.single;
          return {l.single.id: TestResult.tokenRevoked};
        },
      );
      final server = PlexServer.fromResource(
        resourceJson(homeResource.replaceAll('mach-home', machine)),
      )!;
      f.secrets.data[PlexSource.tokenKey(acc.id)] = 'revoked-token';
      f.secrets.data[PlexSource.userKey(acc.id)] = 'user-uuid-1';
      f.secrets.data[PlexSource.serverKey(acc.id)] = jsonEncode(
        server.toJson(),
      );
      return (f, acc);
    }

    testWidgets('la ligne du compte : « À reconnecter » et « Nouveau code »', (
      tester,
    ) async {
      await pumpRevoked(tester, FakePlexTv());
      expect(find.text('À reconnecter'), findsOneWidget);
      expect(find.text('Nouveau code'), findsOneWidget);
      expect(
        find.text(
          'Ta musique gardée sur le téléphone reste là et continue de jouer.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('« Nouveau code » remplace le jeton sur place (même compte)', (
      tester,
    ) async {
      final tv = FakePlexTv();
      final (f, acc) = await pumpRevoked(tester, tv);
      await tapIt(tester, find.text('Nouveau code'));
      await settle(tester);
      await settle(tester);
      await tester.pump(const Duration(milliseconds: 600));
      await settle(tester);
      expect(find.byType(PlexLinkScreen), findsNothing);
      final list = await f.list(tester);
      expect(list.single.id, acc.id);
      expect(list.single.name, 'Plex maison');
      expect(f.secrets.data[PlexSource.tokenKey(acc.id)], 'server-token-home');
      expect(find.text('À reconnecter'), findsNothing);
      expect(f.synced, contains(acc.id));
    });

    testWidgets('le serveur n\'est plus sur ce compte Plex : rien ne change', (
      tester,
    ) async {
      final tv = FakePlexTv();
      final (f, acc) = await pumpRevoked(tester, tv, machine: 'mach-gone');
      await tapIt(tester, find.text('Nouveau code'));
      await settle(tester);
      await settle(tester);
      expect(
        find.text("Ce serveur n'est plus sur ce compte Plex."),
        findsOneWidget,
      );
      expect(f.secrets.data[PlexSource.tokenKey(acc.id)], 'revoked-token');
      await tapIt(tester, find.text('Annuler'));
    });

    testWidgets('un code d\'un autre compte Plex : refusé, rien ne change', (
      tester,
    ) async {
      final tv = FakePlexTv()..userUuid = 'user-uuid-2';
      final (f, acc) = await pumpRevoked(tester, tv);
      await tapIt(tester, find.text('Nouveau code'));
      await settle(tester);
      await settle(tester);
      expect(
        find.text("Ce code vient d'un autre compte Plex. Rien n'a changé."),
        findsOneWidget,
      );
      expect(f.secrets.data[PlexSource.tokenKey(acc.id)], 'revoked-token');
      expect(f.secrets.data[PlexSource.userKey(acc.id)], 'user-uuid-1');
      expect(
        f.secrets.data.containsKey(PlexSource.accountTokenKey(acc.id)),
        isFalse,
      );
      expect(f.synced, isNot(contains(acc.id)));
      await tapIt(tester, find.text('Annuler'));
    });

    testWidgets('« Nouveau code » aussi dans la fiche du compte Plex', (
      tester,
    ) async {
      final tv = FakePlexTv();
      final (f, acc) = await pumpRevoked(tester, tv);
      await tapIt(tester, find.text('Plex maison'));
      expect(find.byType(AccountFormScreen), findsOneWidget);
      await tapIt(tester, find.text('Nouveau code'));
      await settle(tester);
      await settle(tester);
      await tester.pump(const Duration(milliseconds: 600));
      await settle(tester);
      expect(find.byType(PlexLinkScreen), findsNothing);
      expect(find.byType(AccountFormScreen), findsNothing);
      expect((await f.list(tester)).single.id, acc.id);
      expect(f.secrets.data[PlexSource.tokenKey(acc.id)], 'server-token-home');
    });
  });

  testWidgets('un serveur sans adresse : message clair, rien d\'enregistré', (
    tester,
  ) async {
    final tv = FakePlexTv()
      ..resources = [
        homeResource.replaceAll(
          RegExp(r'"connections":\[[\s\S]*\]'),
          '"connections":[]',
        ),
      ];
    final f = await pumpWithPlex(tester, tv);
    await openCode(tester);
    await settle(tester);
    expect(find.text('Ce serveur ne donne aucune adresse.'), findsOneWidget);
    expect(find.text('Aucun serveur Plex sur ce compte.'), findsNothing);
    expect(await f.list(tester), isEmpty);
  });

  testWidgets(
    '« C\'est bon ✓ » : « Je cherche tes serveurs… », plus « En attente »',
    (tester) async {
      final tv = FakePlexTv()..resources = [homeResource];
      tv.pms.delay = {homeLocal: const Duration(seconds: 3)};
      await pumpWithPlex(tester, tv);
      await openCode(tester);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text("C'est bon ✓"), findsOneWidget);
      expect(find.text('Je cherche tes serveurs…'), findsOneWidget);
      expect(find.text('En attente de Plex…'), findsNothing);
      expect(find.text('Le code marche 15 minutes.'), findsNothing);
      // the server answers late (identity, then its libraries): saved, the screen closes
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(seconds: 4));
        await settle(tester);
      }
      await tester.pump(const Duration(milliseconds: 600));
      await settle(tester);
      expect(find.byType(PlexLinkScreen), findsNothing);
    },
  );
}
