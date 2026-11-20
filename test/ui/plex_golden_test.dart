// Pixel comparison: run on macOS only (CI job goldens), see dart_test.yaml.
@Tags(['golden'])
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/sources/accounts.dart';
import 'package:lafleurmusic/sources/plex.dart';
import 'package:lafleurmusic/sources/plex_link.dart';
import 'package:lafleurmusic/sources/source.dart';
import 'package:lafleurmusic/ui/phone/account_form.dart';
import 'package:lafleurmusic/ui/phone/accounts_screen.dart';
import 'package:lafleurmusic/ui/phone/plex_link_screen.dart';

import '../sources/fake_plex.dart';
import 'accounts_fixture.dart';
import 'fonts.dart';
import 'phone_fixture.dart' show settle;
import 'plex_fixture.dart';

/// Maquette 14 (connexion Plex par code), écrans A à D, 390 × 844, sur un iPhone.
void main() {
  setUpAll(() async {
    await loadFonts();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  /// Le logo se décode hors de l'horloge simulée : avant que l'écran le demande.
  Future<void> precacheLogo(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    final ctx = tester.element(find.byType(Scaffold));
    await tester.runAsync(() async {
      for (final logo in logos) {
        await precacheImage(AssetImage(logo), ctx);
      }
    });
  }

  for (final (mode, sfx) in goldenModes) {
    testWidgets(inMode(mode, '14 A onglet Plex'), (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await precacheLogo(tester);
      await pumpWithPlex(
        tester,
        brightness: mode,
        FakePlexTv(),
        home: () => const AccountFormScreen(),
      );
      await tester.tap(find.text('Plex'));
      await settle(tester);
      await tester.enterText(
        find.byKey(const ValueKey('account-name')),
        'Plex maison',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await settle(tester);
      await expectLater(
        find.byType(AccountFormScreen),
        matchesGoldenFile('goldens/phone-14a$sfx.png'),
      );
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets(inMode(mode, '14 B le code'), (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await precacheLogo(tester);
      await pumpWithPlex(
        tester,
        brightness: mode,
        FakePlexTv()..validateAfter = null,
        home: () => const PlexLinkScreen(),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await expectLater(
        find.byType(PlexLinkScreen),
        matchesGoldenFile('goldens/phone-14b$sfx.png'),
      );
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets(inMode(mode, '14 C choisir le serveur'), (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await precacheLogo(tester);
      await pumpWithPlex(
        tester,
        brightness: mode,
        FakePlexTv(),
        home: () => const PlexLinkScreen(),
      );
      await settle(tester);
      await expectLater(
        find.byType(PlexLinkScreen),
        matchesGoldenFile('goldens/phone-14c$sfx.png'),
      );
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets(inMode(mode, '14 D À reconnecter'), (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await precacheLogo(tester);
      final f = await pumpWithPlex(
        tester,
        brightness: mode,
        FakePlexTv(),
        seed: [mockupAccounts.first, ...plexSeed],
        results: (l) => {l[1].id: TestResult.tokenRevoked},
      );
      final plex = (await f.list(tester))[1].id;
      f.secrets.data[PlexSource.serverKey(plex)] = jsonEncode(
        PlexServer.fromResource(resourceJson(homeResource))!.toJson(),
      );
      await settle(tester);
      await expectLater(
        find.byType(AccountsScreen),
        matchesGoldenFile('goldens/phone-14d$sfx.png'),
      );
      debugDefaultTargetPlatformOverride = null;
    });

    // états hors maquette, montrés à Johnny pour accord (correction 1)
    testWidgets(inMode(mode, '14 E code expiré'), (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await precacheLogo(tester);
      await pumpWithPlex(
        tester,
        brightness: mode,
        FakePlexTv()
          ..validateAfter = null
          ..expiresIn = 60,
        home: () => const PlexLinkScreen(),
      );
      await tester.pump(const Duration(seconds: 61));
      await settle(tester);
      await expectLater(
        find.byType(PlexLinkScreen),
        matchesGoldenFile('goldens/phone-14e$sfx.png'),
      );
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets(inMode(mode, '14 F plex.tv ne répond pas'), (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await precacheLogo(tester);
      await pumpWithPlex(
        tester,
        brightness: mode,
        FakePlexTv()..down = true,
        home: () => const PlexLinkScreen(),
      );
      await settle(tester);
      await expectLater(
        find.byType(PlexLinkScreen),
        matchesGoldenFile('goldens/phone-14f$sfx.png'),
      );
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets(inMode(mode, '14 G C\'est bon ✓, je cherche tes serveurs'), (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await precacheLogo(tester);
      final tv = FakePlexTv()..resources = [homeResource];
      tv.pms.delay = {homeLocal: const Duration(seconds: 3)};
      await pumpWithPlex(
        tester,
        brightness: mode,
        tv,
        home: () => const PlexLinkScreen(),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await expectLater(
        find.byType(PlexLinkScreen),
        matchesGoldenFile('goldens/phone-14g$sfx.png'),
      );
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(seconds: 4));
        await settle(tester);
      }
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets(inMode(mode, '14 H un serveur ne répond pas'), (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await precacheLogo(tester);
      final tv = FakePlexTv();
      tv.pms.down = {officeRemote};
      await pumpWithPlex(
        tester,
        brightness: mode,
        tv,
        home: () => const PlexLinkScreen(),
      );
      await settle(tester);
      await expectLater(
        find.byType(PlexLinkScreen),
        matchesGoldenFile('goldens/phone-14h$sfx.png'),
      );
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets(inMode(mode, '14 I fiche du compte Plex'), (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await precacheLogo(tester);
      late Account acc;
      await pumpWithPlex(
        tester,
        brightness: mode,
        FakePlexTv(),
        seed: plexSeed,
        results: (l) {
          acc = l.single;
          return const {};
        },
        home: () => AccountFormScreen(editing: acc),
      );
      await settle(tester);
      await expectLater(
        find.byType(AccountFormScreen),
        matchesGoldenFile('goldens/phone-14i$sfx.png'),
      );
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
