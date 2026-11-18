import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../l10n/strings.dart';
import '../library/db.dart' show OfflineRow;
import '../library/models.dart';
import '../offline/downloader.dart' show KeepResult;
import '../player/media_resolver.dart';
import '../theme/colors.dart';

/// « iPhone » sur iOS, « téléphone » ailleurs (pour les textes).
bool get onIphone => defaultTargetPlatform == TargetPlatform.iOS;

/// Seuls les morceaux d'un serveur se gardent (pas les fichiers locaux).
bool isRemote(Track t) => parseRemoteKey(t.path) != null;

/// Une copie existe (finie ou en file) : « Retirer » plutôt que « Garder ».
bool isKept(Track t, Map<String, OfflineRow> rows) {
  final r = rows[t.path];
  return r != null && r.state != OfflineState.failed.name;
}

/// Une barre de message du téléphone, aux couleurs de l'appli.
void say(ScaffoldMessengerState messenger, String text) =>
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: LafleurColors.bar,
        content: Text(text, style: const TextStyle(color: LafleurColors.text)),
      ),
    );

/// Garde [tracks] (ceux d'un serveur) : dit pourquoi si c'est refusé. Vrai si c'est en file.
Future<bool> keepTracks(BuildContext context, List<Track> tracks) async {
  final app = AppScope.of(context);
  final downloader = app.downloader;
  if (downloader == null) return false;
  final s = app.strings;
  final messenger = ScaffoldMessenger.of(context);
  final result = await downloader.keep([
    for (final t in tracks)
      if (isRemote(t)) t,
  ]);
  if (result.ok) {
    // l'accès au dossier Musique (Android) se demande au premier téléchargement
    void warn() {
      if (!downloader.accessDenied) return;
      downloader.removeListener(warn);
      say(messenger, s.storageDenied);
    }

    if (downloader.accessDenied) {
      say(messenger, s.storageDenied);
    } else {
      downloader.addListener(warn);
      unawaited(
        downloader.whenIdle().whenComplete(
          () => downloader.removeListener(warn),
        ),
      );
    }
    return true;
  }
  say(messenger, refusal(s, result));
  return false;
}

/// Pourquoi [Downloader.keep] a refusé : place, dossier indisponible, ou erreur.
String refusal(Strings s, KeepResult r) {
  if (r.folderUnavailable) return s.folderUnavailable(onIphone);
  if (r.neededBytes > 0) return s.notEnoughSpace(s.size(r.neededBytes));
  return s.keepFailed;
}

/// Retire la copie de [tracks] du téléphone (les leurs, celles de l'utilisateur comme du Top 100).
Future<void> forgetTracks(BuildContext context, List<Track> tracks) async {
  final downloader = AppScope.of(context).downloader;
  if (downloader == null) return;
  await downloader.forget([
    for (final t in tracks)
      if (isRemote(t)) t.path,
  ]);
}
