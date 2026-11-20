import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lafleurmusic/settings.dart';
import 'package:lafleurmusic/update/update_service.dart';

/// La version 0.11.0 de la maquette 19 (98 Mo, APK et IPA).
const update0110 = UpdateInfo(
  version: '0.11.0',
  notes: [
    'Ce qui change, en quelques lignes',
    'Comme sur la page GitHub de la version',
  ],
  pageUrl:
      'https://github.com/Jonlekern/lafleurmusic-mobile/releases/tag/v0.11.0',
  apkUrl: 'https://example.invalid/LAFLEURMUSIC-android.apk',
  apkSize: 98 * 1024 * 1024,
  apkSha256: 'ab',
  ipaUrl: 'https://example.invalid/LAFLEURMUSIC-iphone-unsigned.ipa',
);

/// Un service sans réseau : le test pose la mise à jour, mène le téléchargement et la recherche.
class FakeUpdateService extends UpdateService {
  FakeUpdateService({UpdateInfo? available, AppSettings? settings})
    : super(
        client: MockClient((_) async => http.Response('', 500)),
        settings: settings ?? AppSettings(),
        saveSettings: () async {},
        current: '0.10.2',
      ) {
    this.available.value = available;
  }

  // téléchargement en cours
  Completer<File>? download;
  void Function(double)? progress;
  CancelToken? token;
  Directory? dir;
  int downloads = 0;
  // vrai : l'annulation n'arrête pas l'attente (le fichier arrive quand même)
  bool ignoreCancel = false;

  // recherche à la demande
  UpdateCheck nextCheck = UpdateCheck.upToDate;
  UpdateInfo? found;

  @override
  UpdateInfo? get latest => found;

  @override
  Future<UpdateCheck> checkNow() async => nextCheck;

  @override
  Future<File> downloadApk(
    UpdateInfo u,
    Directory cacheDir, {
    void Function(double)? onProgress,
    CancelToken? cancel,
  }) {
    downloads++;
    progress = onProgress;
    token = cancel;
    dir = cacheDir;
    final c = download = Completer<File>();
    // comme le vrai : l'annulation fait échouer l'attente
    cancel?.whenCancelled.then((_) {
      if (!ignoreCancel && !c.isCompleted) {
        c.completeError(StateError('annulé'));
      }
    });
    return c.future;
  }
}
