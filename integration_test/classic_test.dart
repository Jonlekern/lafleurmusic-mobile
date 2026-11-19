// End-to-end run of plan 6 (Classic mode): the real app, one account on a fake Subsonic server
// in the test process (fake_subsonic.dart), so the album "Studio Lafleur" is there.
//
//   flutter test integration_test/classic_test.dart -d <phone>
//
// Home → Settings → Classic mode → the Classic menu shows → with the wheel (real finger turns on
// the ring, presses in the middle): Albums → the album → its second song → Classic Now Playing
// shows and the song plays past 1 s → the wheel turns the volume down → MENU back to the menu
// → Settings row → Normal mode → Home shows and the same song keeps playing, not started again
// (same player, no new stream; repeated: the test song is short), the volume back to full.
//
// Same clean start as the other runs (own library folder deleted first, own keychain / Keystore
// namespace emptied first and last) and the same safe cleanup (`mountGuarded`).
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lafleurmusic/main.dart';
import 'package:lafleurmusic/player/queue.dart' show Repeat;
import 'package:lafleurmusic/sources/account_service.dart';
import 'package:lafleurmusic/sources/secret_store.dart';
import 'package:lafleurmusic/ui/classic/classic_menu.dart';
import 'package:lafleurmusic/ui/classic/classic_now.dart';
import 'package:lafleurmusic/ui/classic/click_wheel.dart';
import 'package:lafleurmusic/ui/phone/accounts_screen.dart';
import 'package:lafleurmusic/ui/phone/home_screen.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart' show MpvAudioKit;
import 'package:path_provider/path_provider.dart';

import 'fake_subsonic.dart';
import 'ui_helpers.dart';

/// Lets a page slide in or out (Cupertino routes: about 400 ms).
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// The wheel on screen (the one under a covered page is offstage).
Rect wheelRect(WidgetTester tester) =>
    tester.getRect(find.byType(ClickWheel).hitTestable().last);

/// A point on the ring, [deg] degrees clockwise from noon.
Offset onRing(WidgetTester tester, double deg) {
  final r = wheelRect(tester);
  final a = deg * math.pi / 180;
  final radius = r.width / 2 * .8;
  return r.center + Offset(math.sin(a) * radius, -math.cos(a) * radius);
}

/// Turns the wheel with a real finger by [notches] (+ clockwise = down), 5° per move, then lifts.
Future<void> turn(WidgetTester tester, int notches) async {
  final end = notches * 15.0 + notches.sign * 5; // a little past the last notch
  var deg = 0.0;
  final g = await tester.startGesture(onRing(tester, deg));
  while (deg.abs() < end.abs()) {
    deg += 5 * notches.sign;
    await g.moveTo(onRing(tester, deg));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await g.up();
  await tester.pump(const Duration(milliseconds: 100));
}

/// Presses the middle of the wheel, or MENU at the top of the ring.
Future<void> pressCentre(WidgetTester tester) async {
  await tester.tapAt(wheelRect(tester).center);
  await settle(tester);
}

Future<void> pressMenu(WidgetTester tester) async {
  await tester.tapAt(onRing(tester, 0));
  await settle(tester);
}

/// The chosen (pink) row of the Classic list on screen; null while a page slides (two lists).
String? chosen(WidgetTester tester) {
  final rows = tester
      .widgetList<ClassicRow>(find.byType(ClassicRow).hitTestable())
      .where((r) => r.selected)
      .toList();
  return rows.length == 1 ? rows.single.label : null;
}

/// Waits until the chosen row is [label].
Future<void> chosenIs(WidgetTester tester, String label) async {
  final end = DateTime.now().add(const Duration(seconds: 20));
  while (chosen(tester) != label) {
    if (DateTime.now().isAfter(end)) {
      fail('Chosen row is ${chosen(tester)}, not $label');
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Taps a choice of the Settings screen (a scrolling sliver list).
Future<void> tapSetting(WidgetTester tester, Finder finder) async {
  await pumpUntil(tester, finder);
  await tester.ensureVisible(finder.first);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(finder.hitTestable().first);
  await tester.pump();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MpvAudioKit.ensureInitialized();

  late FakeSubsonic server;
  late Directory support;

  setUpAll(() async {
    server = await FakeSubsonic.start(topPlays: false);
    support = Directory(
      '${(await getTemporaryDirectory()).path}/lafleurmusic-e2e-classic',
    );
    if (support.existsSync()) support.deleteSync(recursive: true);
    support.createSync(recursive: true);
    await testStorage.deleteAll();
  });

  tearDownAll(() async {
    await testStorage.deleteAll();
    await server.close();
  });

  testWidgets(
    'Classic mode: wheel → album → plays → back to normal, still playing',
    (tester) async {
      final app = await mountGuarded(
        () => buildLafleurApp(
          support: support,
          secrets: SecureSecretStore(testStorage),
        ),
      );
      final s = app.strings;
      final player = app.player;
      // passing or not, the sound stops at the end
      addTearDown(() async {
        if (player.current.playing) await player.toggle();
      });
      await tester.pumpWidget(app);
      await tester.pump(const Duration(seconds: 1));
      expect(app.classicMode.value, isFalse); // normal mode by default

      // one account, as the form saves it (the form itself is driven by app_test.dart)
      await app.accountService.save(
        AccountDraft(
          name: 'Fake Navidrome',
          address: server.address,
          user: server.user,
          password: server.password,
          headers: const {fakeHeader: fakeHeaderValue},
        ),
      );

      // normal Home, the album synced
      await pumpUntil(tester, find.text('Studio Lafleur'));
      expect(find.byType(HomeScreen), findsOneWidget);

      // Settings → Classic mode
      await tester.tap(find.byIcon(Icons.settings_rounded).hitTestable().first);
      await settle(tester);
      await pumpUntil(tester, find.byType(AccountsScreen));
      await tapSetting(tester, find.text(s.classicMode));
      await settle(tester);

      // the Classic menu replaces the phone view, Cover Flow chosen first
      await pumpUntil(tester, find.byType(ClassicMenu));
      expect(find.byType(HomeScreen), findsNothing);
      expect(app.classicMode.value, isTrue);
      await chosenIs(tester, s.coverFlow);

      // the wheel: two notches down → Albums, press the middle
      await turn(tester, 2);
      await chosenIs(tester, s.albumsBack);
      await pressCentre(tester);
      await chosenIs(tester, 'Studio Lafleur');
      await pressCentre(tester);

      // the album's songs: one notch down → Surf Break, press the middle → it plays
      await chosenIs(tester, 'Night Drive');
      await turn(tester, 1);
      await chosenIs(tester, 'Surf Break');
      await pressCentre(tester);

      // Classic Now Playing, and the song really plays past 1 s
      await pumpUntil(tester, find.byType(ClassicNow));
      // the test song is about 3 s long: once it is the current song, repeat it, so it is
      // still playing at the switch
      final queued = DateTime.now().add(const Duration(seconds: 30));
      while (player.queue == null ||
          player.current.track?.title != 'Surf Break') {
        if (DateTime.now().isAfter(queued)) {
          fail('Surf Break not current: ${player.current.track?.title}');
        }
        await tester.pump(const Duration(milliseconds: 50));
      }
      for (var i = 0; i < 3 && player.queue?.repeat != Repeat.one; i++) {
        await player.cycleRepeat();
      }
      expect(player.queue?.repeat, Repeat.one);
      final end = DateTime.now().add(const Duration(seconds: 30));
      while (!(player.current.track?.title == 'Surf Break' &&
          player.current.position > const Duration(seconds: 1))) {
        if (DateTime.now().isAfter(end)) {
          fail(
            'Not past 1 s within 30 s: ${player.current.track?.title} '
            'at ${player.current.position}; server saw ${server.requests}',
          );
        }
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(player.current.playing, isTrue);
      final streams = server.requests.where((r) => r.method == 'stream');
      expect(streams.map((r) => r.params['id']), contains('s-2'));
      debugPrint(
        'PREUVE Classic : ${player.current.track?.title} à '
        '${player.current.position} ; serveur : ${server.requests}',
      );

      // turning on Now Playing is the volume: three notches up the other way → 85
      expect(player.volume, 100);
      await turn(tester, -3);
      expect(player.volume, 100 - 3 * ClassicNow.volumeStep);

      // MENU → the song list, MENU again → Albums, again → the top menu
      await pressMenu(tester);
      expect(find.byType(ClassicNow), findsNothing);
      await chosenIs(tester, 'Surf Break');
      await pressMenu(tester);
      await chosenIs(tester, 'Studio Lafleur');
      await pressMenu(tester);
      await chosenIs(tester, s.albumsBack);

      // down to the last row, Settings, press the middle
      await turn(tester, 8);
      await chosenIs(tester, s.classicSettings);
      await pressCentre(tester);
      await pumpUntil(tester, find.byType(AccountsScreen));

      // Normal mode: Home again, the same song still playing
      final queue = [for (final t in player.queue!.order) t.path];
      int streamCount() =>
          server.requests.where((r) => r.method == 'stream').length;
      final streamsBefore = streamCount();
      await tapSetting(tester, find.text(s.normalMode));
      await settle(tester);
      await pumpUntil(tester, find.byType(HomeScreen));
      expect(find.byType(ClassicMenu), findsNothing);
      expect(find.byType(ClickWheel), findsNothing);
      expect(app.classicMode.value, isFalse);
      await pumpUntil(tester, find.text('Studio Lafleur'));

      // the sound goes on: the position keeps moving (it may wrap round, the song repeats)
      final before = player.current.position;
      final until = DateTime.now().add(const Duration(seconds: 10));
      while ((player.current.position - before).abs() <
          const Duration(milliseconds: 500)) {
        if (DateTime.now().isAfter(until)) {
          fail('Stopped after the switch: at ${player.current.position}');
        }
        await tester.pump(const Duration(milliseconds: 100));
      }
      // not started again: the same player, no new stream asked of the server
      expect(identical(app.player, player), isTrue);
      expect(streamCount(), streamsBefore);
      expect(player.current.track?.title, 'Surf Break');
      expect(player.current.playing, isTrue);
      expect([for (final t in player.queue!.order) t.path], queue);
      expect(player.volume, 100); // back to full: normal mode has no volume
      expect(server.requests.where((r) => r.status != 200), isEmpty);
      debugPrint(
        'PREUVE retour au mode normal : ${player.current.track?.title} à '
        '${player.current.position} ; streams : ${streamCount()}',
      );
    },
  );
}
