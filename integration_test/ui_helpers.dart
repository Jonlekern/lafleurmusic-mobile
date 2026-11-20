// Shared by the end-to-end runs (app_test.dart, offline_test.dart): a keychain / Keystore
// namespace of their own, and helpers to drive the screens on phones of any size.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/main.dart';
import 'package:lafleurmusic/offline/paths.dart' show isPartialName;
import 'package:path/path.dart' as p;

/// Test-only secure storage: another keychain service on iOS, another preferences file on Android.
const testStorage = FlutterSecureStorage(
  iOptions: IOSOptions(accountName: 'lafleurmusic.e2e-test'),
  aOptions: AndroidOptions(sharedPreferencesName: 'lafleurmusic_e2e_test'),
);

/// Pumps frames until [finder] finds something, for at most [timeout].
Future<void> pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final end = DateTime.now().add(timeout);
  while (finder.evaluate().isEmpty) {
    if (DateTime.now().isAfter(end)) {
      throw TestFailure('Not found within $timeout: $finder');
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Scrolls the screen's list until [finder] is built and on screen: lists build lazily, a small
/// phone (the 320×640 Android emulator) shows only the top of the form, and the real keyboard
/// takes half the screen. Down first, then up (the keyboard may have pushed it above).
Future<void> reveal(WidgetTester tester, Finder finder) async {
  final list = find
      .descendant(of: find.byType(ListView), matching: find.byType(Scrollable))
      .first;
  for (var attempt = 0; attempt < 4; attempt++) {
    await tester.pump();
    for (final delta in const [150.0, -150.0]) {
      if (finder.evaluate().isNotEmpty) break;
      try {
        await tester.scrollUntilVisible(
          finder,
          delta,
          scrollable: list,
          maxScrolls: 60,
        );
      } on StateError {
        // not in this direction
      }
    }
    if (finder.evaluate().isNotEmpty) {
      await tester.ensureVisible(finder);
      await tester.pump(const Duration(milliseconds: 300));
      if (finder.hitTestable().evaluate().isNotEmpty) return;
    }
  }
  throw TestFailure('Could not bring on screen: $finder');
}

/// Taps a button: the keyboard goes away first, so the whole screen is free on a small phone.
Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump(const Duration(milliseconds: 500));
  await reveal(tester, finder);
  await tester.tap(finder.hitTestable().first);
  await tester.pump();
}

Future<void> typeInto(WidgetTester tester, String key, String text) async {
  final field = find.byKey(ValueKey(key));
  await reveal(tester, field);
  await tester.enterText(field, text);
  await tester.pump(
    const Duration(milliseconds: 300),
  ); // keyboard up: the list may move
  await reveal(tester, field);
  await tester.pump();
}

/// Replaces the text of a field that already holds some, then lets go of the keyboard.
///
/// `enterText` hands the text to the app as if the keyboard had typed it, but the real keyboard
/// is never told: it keeps its own copy of the old text. On Android the keyboard takes the word
/// under the caret back as it opens (« e2e » of the old name) and sends its copy to the app,
/// which puts the old name back. So: the keyboard is opened and left to settle first, the text
/// goes in, then the field lets go of the keyboard (nothing the keyboard sends after can reach
/// it), and the field must hold [text], else it is tried again.
Future<void> replaceText(WidgetTester tester, Finder field, String text) async {
  final editable = find.descendant(
    of: field,
    matching: find.byType(EditableText),
    matchRoot: true,
  );
  var shown = '';
  for (var attempt = 0; attempt < 3; attempt++) {
    await tester.showKeyboard(field);
    await tester.pump(
      const Duration(seconds: 1),
    ); // the keyboard is up and settled
    await tester.enterText(field, text);
    await tester.pump(const Duration(milliseconds: 500));
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(milliseconds: 500));
    shown = tester.widget<EditableText>(editable).controller.text;
    if (shown == text) return;
  }
  throw TestFailure('The field holds « $shown », not « $text »');
}

/// The phone's real LAFLEURMUSIC folder (iOS: Documents, Android: Music), where copies go.
Future<Directory> deviceRoot() async => Directory(
  (await const MethodChannel('studio.lafleur/device')
      .invokeMethod<String>('defaultRoot'))!,
);

List<String> _filesUnder(Directory root) => root.existsSync()
    ? [
        for (final e in root.listSync(recursive: true, followLinks: false))
          if (e is File) p.relative(e.path, from: root.path),
      ]
    : const [];

/// Builds the app with [mount] and guards the folder: whatever the run leaves in the phone's folder is removed
/// when the test ends, passing or not. The Top 100 and the queue are stopped first (nothing
/// re-queues after), every copy is forgotten, then the files our rows made and the `.part`
/// files that weren't there at the start are deleted. Files that were there are never touched.
Future<LafleurApp> mountGuarded(Future<LafleurApp> Function() mount) async {
  final root = await deviceRoot();
  final before = _filesUnder(root).toSet();
  final app = await mount();
  addTearDown(() async {
    final made = <String>{};
    try {
      await app.topSub.cancel();
      app.topKeeper.dispose();
      app.downloader.pause();
      await app.downloader.whenIdle();
      final rows = (await app.db.watchOffline().first).values;
      // the `.m3u8` files the app wrote itself (KeptPlaylists), under Playlists/; the app itself drops the folder when empty
      for (final k in await app.db.keptPlaylistRows()) {
        if (k.fileName.isNotEmpty) made.add(p.join('Playlists', k.fileName));
      }
      made.addAll([
        for (final r in rows)
          if (r.filePath != null) r.filePath!,
      ]);
      await app.downloader.forget([for (final r in rows) r.trackPath]);
    } finally {
      for (final rel in _filesUnder(root)) {
        if (before.contains(rel)) continue;
        if (made.contains(rel) || isPartialName(rel)) {
          File(p.join(root.path, rel)).deleteSync();
        }
      }
    }
  });
  return app;
}
