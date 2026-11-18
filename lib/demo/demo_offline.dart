import 'package:flutter/foundation.dart';

import '../library/db.dart';
import '../library/models.dart';
import '../offline/downloader.dart';
import '../sources/account_service.dart';
import 'demo_library.dart';

/// « Garder sur mon iPhone » sans réseau ni disque (mode démo et tests d'écran) : note ce qu'on lui
/// demande et répond [result].
class DemoDownloader extends ChangeNotifier implements Downloader {
  DemoDownloader({this.result = const KeepResult.queued(0, 0)});

  /// Réponse de [keep] (ok, trop gros, erreur).
  KeepResult result;

  /// Chemins demandés à [keep], un lot par appel.
  final kept = <List<String>>[];

  /// Chemins passés à [forget], un lot par appel.
  final forgotten = <List<String>>[];

  @override
  bool accessDenied = false;

  @override
  Future<KeepResult> keep(
    List<Track> tracks, {
    OfflineReason reason = OfflineReason.user,
  }) async {
    kept.add([for (final t in tracks) t.path]);
    return result;
  }

  @override
  Future<void> forget(List<String> trackPaths, {OfflineReason? only}) async =>
      forgotten.add(trackPaths);

  @override
  Future<void> whenIdle() => Future.value();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Les comptes de la démo : les morceaux de [notOnPhone] ne sont pas jouables (hors ligne, jamais gardés).
class DemoAccountService extends AccountService {
  DemoAccountService(
    super.accounts, {
    required super.db,
    super.draftSource,
    super.sourceOf,
    super.sync,
    this.notOnPhone = const {},
  });
  final Set<String> notOnPhone;

  @override
  bool playableNow(Track t) => !notOnPhone.contains(t.path);
}

/// Un album déjà copié : une ligne `done` par morceau, [bytes] au total (la place utilisée).
Future<void> seedKept(LibraryDb db, List<String> paths, int bytes) async {
  await db.queueOffline(paths, OfflineReason.user);
  for (final (i, p) in paths.indexed) {
    await db.markOfflineDone(p, 'kept/$i.mp3', bytes ~/ paths.length);
  }
}

/// Les données de la démo « Garder » : la bibliothèque serveur, Lafleur Surf gardé (4,2 Go utilisés).
Future<void> seedKeepDemo(LibraryDb db) async {
  await db.upsertTracks(DemoLibrary.remote);
  await seedKept(db, DemoLibrary.keptPaths, 4509715661); // 4,2 Go
}
