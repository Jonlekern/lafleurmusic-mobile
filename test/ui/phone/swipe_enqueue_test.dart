import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/demo/demo_library.dart';
import 'package:lafleurmusic/sources/account_service.dart';
import 'package:lafleurmusic/ui/phone/album_screen.dart';
import 'package:lafleurmusic/ui/phone/mini_player.dart';
import 'package:lafleurmusic/ui/phone/now_screen.dart';
import 'package:lafleurmusic/ui/phone/phone_shell.dart';
import 'package:lafleurmusic/ui/queue_toast.dart';

import '../fonts.dart';
import '../keep_fixture.dart';
import '../phone_fixture.dart';
import 'keep_screen_test.dart' show done, phoneTest;

/// Glisse « [title] » de [dx] (négatif : vers la gauche) par petits pas, sans lâcher.
Future<TestGesture> pull(WidgetTester tester, String title, double dx) async {
  final g = await tester.startGesture(tester.getCenter(find.text(title)));
  final steps = (dx.abs() / 25).ceil();
  for (var i = 0; i < steps; i++) {
    await g.moveBy(Offset(dx.sign * 25, 0));
    await tester.pump();
  }
  return g;
}

Future<void> release(WidgetTester tester, TestGesture g) async {
  await g.up();
  await tester.pumpAndSettle(const Duration(seconds: 5)); // y compris la bulle
}

const _bubble = Key('queueToast');
const _nothing = "Pas sur l'iPhone : rien à jouer hors ligne.";

/// Le vrai « jouable ? » du service, avec tous les comptes absents (serveur injoignable, compte coupé).
class _AllAbsent extends AccountService {
  _AllAbsent(super.accounts, {required super.db});
  @override
  AccountState? stateOf(String id) => AccountState.absent;
}

void main() {
  setUpAll(loadFonts);

  Future<KeepFixture> open(
    WidgetTester tester, {
    Set<String>? notOnPhone,
    bool local = false,
    bool accountOff = false,
  }) async {
    // local : aucun compte, seulement des fichiers sur le téléphone
    final f = await pumpKeep(
      tester,
      notOnPhone: notOnPhone ?? const {},
      addAccount: !local,
      makeService: accountOff ? (a, db) => _AllAbsent(a, db: db) : null,
      seed: local ? (db) => db.upsertTracks(DemoLibrary.studio) : null,
      // sans compte l'Accueil demande d'en ajouter un : on va droit à l'album qui joue
      home: local ? const PhoneShell(debugStart: 'album') : const PhoneShell(),
    );
    if (!local) await tester.ensureVisible(find.text('Studio Lafleur'));
    await tester.pump();
    if (!local) await tester.tap(find.text('Studio Lafleur'));
    await done(tester);
    return f;
  }

  group('glisser à droite = Ajouter à la file', () {
    phoneTest('bandeau rose, puis enqueue et la bulle', TargetPlatform.iOS, (
      tester,
    ) async {
      final f = await open(tester);
      final g = await pull(tester, 'Night Swim', 175);
      expect(find.text('+ Ajouter à la file'), findsOneWidget);
      await g.up();
      await tester.pump();
      expect(f.player.calls, contains('enqueue'));
      expect(f.player.calls, isNot(contains('playNext')));
      expect(f.player.lastAdded!.single.title, 'Night Swim');
      expect(find.byKey(_bubble), findsOneWidget);
      expect(find.text('✓ Ajouté à la file'), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 5));
    });

    phoneTest(
      'à gauche : Lire ensuite comme avant, sans bulle',
      TargetPlatform.iOS,
      (tester) async {
        final f = await open(tester);
        final g = await pull(tester, 'Night Swim', -150);
        expect(find.text('← Lire ensuite'), findsOneWidget);
        await release(tester, g);
        expect(f.player.calls, contains('playNext'));
        expect(f.player.calls, isNot(contains('enqueue')));
        expect(find.byKey(_bubble), findsNothing);
      },
    );

    phoneTest('un petit glissement à droite ne fait rien', TargetPlatform.iOS, (
      tester,
    ) async {
      final f = await open(tester);
      await tester.drag(find.text('Night Swim'), const Offset(40, 0));
      await tester.pumpAndSettle();
      expect(f.player.calls, isNot(contains('enqueue')));
      expect(find.byKey(_bubble), findsNothing);
    });

    phoneTest('la bulle part seule après 4 s', TargetPlatform.iOS, (
      tester,
    ) async {
      await open(tester);
      final g = await pull(tester, 'Night Swim', 175);
      await g.up();
      await tester.pump(); // la bulle se pose
      await tester.pump(const Duration(milliseconds: 3900));
      expect(find.byKey(_bubble), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byKey(_bubble), findsNothing);
      await tester.pumpAndSettle();
    });

    phoneTest('Annuler retire l’ajout de la file', TargetPlatform.iOS, (
      tester,
    ) async {
      final f = await open(tester);
      final before = f.player.queue!.order.length;
      final g = await pull(tester, 'Night Swim', 175);
      await g.up();
      await tester.pump();
      expect(f.player.queue!.order.length, before + 1);
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(f.player.calls, contains('removeAdded'));
      expect(f.player.queue!.order.length, before);
      expect(f.player.queue!.added.map((t) => t.title), ['Nightcall']);
      expect(find.byKey(_bubble), findsNothing);
    });

    phoneTest(
      'Annuler quand l’ajout joue déjà : rien ne casse, il n’est pas retiré',
      TargetPlatform.iOS,
      (tester) async {
        final f = await open(tester);
        final q = f.player.queue!;
        final g = await pull(tester, 'Night Swim', 175);
        await g.up();
        await tester.pump();
        // la file avance jusqu'à lui pendant que la bulle est encore là
        final swim = q.added.last;
        expect(swim.title, 'Night Swim');
        q.next(); // Nightcall
        q.next(); // Night Swim joue
        expect(q.current, swim);
        final order = [for (final t in q.order) t.path];
        await tester.tap(find.text('Annuler'));
        await tester.pumpAndSettle();
        expect(q.current, swim);
        expect([for (final t in q.order) t.path], order);
        expect(find.byKey(_bubble), findsNothing);
      },
    );

    phoneTest('Voir la file ouvre En cours sur À suivre', TargetPlatform.iOS, (
      tester,
    ) async {
      await open(tester);
      final g = await pull(tester, 'Night Swim', 175);
      await g.up();
      await tester.pump();
      await tester.tap(find.text('Voir la file'));
      await tester.pumpAndSettle();
      expect(find.byType(NowScreen), findsOneWidget);
      expect(find.byKey(_bubble), findsNothing);
      // l'onglet À suivre est celui qu'on voit
      expect(find.text('AJOUTÉS PAR TOI'), findsOneWidget);
      expect(find.text('Night Swim'), findsWidgets);
    });

    phoneTest(
      'Voir la file depuis En cours : pas de 2e écran, on passe à À suivre',
      TargetPlatform.iOS,
      (tester) async {
        await open(tester);
        await tester.tap(find.byType(MiniPlayer));
        await tester.pumpAndSettle();
        expect(find.byType(NowScreen), findsOneWidget);
        await tester.tap(find.text('Égaliseur'));
        await tester.pump();
        expect(find.text('AJOUTÉS PAR TOI'), findsNothing);
        // un ajout fait depuis En cours même : la bulle se pose
        await enqueueWithToast(tester.element(find.byType(NowScreen)), [
          DemoLibrary.nightcall,
        ]);
        await tester.pump();
        expect(find.byKey(_bubble), findsOneWidget);
        await tester.tap(find.text('Voir la file'));
        await tester.pumpAndSettle();
        expect(find.byType(NowScreen), findsOneWidget);
        expect(find.text('AJOUTÉS PAR TOI'), findsOneWidget);
        Navigator.of(tester.element(find.byType(NowScreen)))
            .pop(); // un seul retour suffit
        await tester.pumpAndSettle();
        expect(find.byType(NowScreen), findsNothing);
      },
    );

    phoneTest(
      'un morceau grisé (pas sur le téléphone) : rien n’est ajouté, un petit message',
      TargetPlatform.iOS,
      (tester) async {
        final f = await open(
          tester,
          notOnPhone: DemoLibrary.notOnPhonePaths.toSet(),
        );
        final g = await pull(tester, 'Night Swim', 175);
        await g.up();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(f.player.calls, isNot(contains('enqueue')));
        expect(find.byKey(_bubble), findsNothing);
        expect(
          find.text("Pas sur l'iPhone : rien à jouer hors ligne."),
          findsOneWidget,
        );
        await tester.pumpAndSettle(const Duration(seconds: 5));
      },
    );

    phoneTest('sans aucun compte : fichiers du téléphone', TargetPlatform.iOS, (
      tester,
    ) async {
      final f = await open(tester, local: true);
      final g = await pull(tester, 'Night Swim', 175);
      await g.up();
      await tester.pump();
      expect(f.player.calls, contains('enqueue'));
      expect(find.byKey(_bubble), findsOneWidget);
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(f.player.calls, contains('removeAdded'));
      expect(f.player.queue!.added.map((t) => t.title), ['Nightcall']);
    });
  });

  group('une ligne grisée n’entre pas dans la file, dans les deux sens', () {
    for (final (name, dx, call) in [
      ('à droite', 175.0, 'enqueue'),
      ('à gauche', -175.0, 'playNext'),
    ]) {
      phoneTest('pas sur le téléphone, $name', TargetPlatform.iOS, (
        tester,
      ) async {
        final f = await open(
          tester,
          notOnPhone: DemoLibrary.notOnPhonePaths.toSet(),
        );
        final g = await pull(tester, 'Night Swim', dx);
        await g.up();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(f.player.calls, isNot(contains(call)));
        expect(find.byKey(_bubble), findsNothing);
        expect(find.text(_nothing), findsOneWidget);
        await tester.pumpAndSettle(const Duration(seconds: 5));
      });

      phoneTest('compte coupé et pas de copie, $name', TargetPlatform.iOS, (
        tester,
      ) async {
        final f = await open(tester, accountOff: true);
        final g = await pull(tester, 'Night Swim', dx);
        await g.up();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(f.player.calls, isNot(contains(call)));
        expect(find.byKey(_bubble), findsNothing);
        expect(find.text(_nothing), findsOneWidget);
        await tester.pumpAndSettle(const Duration(seconds: 5));
      });
    }
  });

  group('feuille « Ajouter à la file » (appui long)', () {
    phoneTest(
      'la bulle aussi ; « Lire ensuite » sans bulle',
      TargetPlatform.iOS,
      (tester) async {
        final f = await open(tester);
        await tester.longPress(find.text('Sunset Tape'));
        await done(tester);
        await tester.tap(find.text('Lire ensuite'));
        await done(tester);
        expect(f.player.calls, contains('playNext'));
        expect(find.byKey(_bubble), findsNothing);
        await tester.longPress(find.text('Sunset Tape'));
        await done(tester);
        await tester.tap(find.text('Ajouter à la file'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(f.player.calls, contains('enqueue'));
        expect(find.byKey(_bubble), findsOneWidget);
        await tester.pumpAndSettle(const Duration(seconds: 5));
      },
    );
  });

  testWidgets('pumpPhone (un compte) : le même geste', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      final f = await pumpPhone(tester);
      await tester.ensureVisible(find.text('Studio Lafleur'));
      await tester.pump();
      await tester.tap(find.text('Studio Lafleur'));
      await tester.pumpAndSettle();
      await settle(tester);
      expect(find.byType(AlbumScreen), findsOneWidget);
      final g = await pull(tester, 'Night Swim', 175);
      await g.up();
      await tester.pump();
      expect(f.player.lastAdded!.single.title, 'Night Swim');
      await tester.pumpAndSettle(const Duration(seconds: 5));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
