import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/sources/account_service.dart';
import 'package:lafleurmusic/sources/source.dart';
import 'package:lafleurmusic/ui/phone/account_form.dart';
import 'package:lafleurmusic/ui/phone/accounts_screen.dart';

import 'accounts_fixture.dart';
import 'fonts.dart';

/// Maquette 2, écrans 6 (Réglages → Comptes) et 7 (Ajouter un compte), 390 × 844, sur un iPhone.
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
    await tester.runAsync(
      () => precacheImage(const AssetImage('assets/logo-texte-grand.png'), ctx),
    );
  }

  testWidgets('6 Réglages → Comptes', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await precacheLogo(tester);
    await pumpAccounts(
      tester,
      home: () => const AccountsScreen(),
      results: (l) => {l[1].id: TestResult.unreachable},
    );
    await expectLater(
      find.byType(AccountsScreen),
      matchesGoldenFile('goldens/phone-6.png'),
    );
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('7 Ajouter un compte', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await precacheLogo(tester);
    await pumpAccounts(
      tester,
      seed: const [],
      home: () => const AccountFormScreen(
        initial: AccountDraft(
          name: 'Navidrome maison',
          address: 'http://192.168.1.20:4533',
          user: 'johnny',
          password: 'motdepas',
          headers: {'CF-Access-Client-Id': 'abc123…'},
        ),
      ),
    );
    // l'adresse en cours de saisie : contour rose, comme la maquette
    await tester.tap(find.byKey(const ValueKey('account-address')));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 300)); // contour animé
    await expectLater(
      find.byType(AccountFormScreen),
      matchesGoldenFile('goldens/phone-7.png'),
    );
    debugDefaultTargetPlatformOverride = null;
  });
}
