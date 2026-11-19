import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../l10n/strings.dart';
import '../library/db.dart' show OfflineRow;
import '../library/models.dart';
import '../offline/downloader.dart' show Downloader, KeepOrigin, KeepResult;
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
/// [origin] : pourquoi (pour lui-même par défaut, ou avec son album : [KeepOrigin]).
Future<bool> keepTracks(
  BuildContext context,
  List<Track> tracks, {
  String Function(Track) origin = KeepOrigin.songOf,
}) => keepWith(
  context,
  (d) => d.keep([
    for (final t in tracks)
      if (isRemote(t)) t,
  ], origin: origin),
);

/// Un « Garder » ([keep] : ce qu'on demande au téléchargeur) : dit pourquoi si c'est refusé,
/// et si l'accès au stockage manque. Vrai si c'est en file.
Future<bool> keepWith(
  BuildContext context,
  Future<KeepResult> Function(Downloader) keep,
) async {
  final app = AppScope.of(context);
  final downloader = app.downloader;
  if (downloader == null) return false;
  final s = app.strings;
  final messenger = ScaffoldMessenger.of(context);
  final result = await keep(downloader);
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

/// Retire la copie de [tracks] du téléphone (les leurs, celles de l'utilisateur comme du Top 100),
/// après confirmation (maquette 10) sauf si l'utilisateur a dit « Ne plus me demander ».
/// [name] : ce que la fenêtre nomme (l'album ou le morceau).
Future<void> forgetTracks(
  BuildContext context,
  List<Track> tracks, {
  required String name,
}) async {
  final paths = [
    for (final t in tracks)
      if (isRemote(t)) t.path,
  ];
  if (!await confirmRemoval(context, name: name, paths: paths)) return;
  if (!context.mounted) return;
  await AppScope.of(context).downloader?.forget(paths, byUser: true);
}

/// Retire un album ([tracks]) du téléphone : seuls partent ceux qui ne sont gardés pour aucune
/// autre raison (une playlist, le morceau lui-même : règle Q13), après la question, qui ne
/// compte qu'eux ; s'il n'y en a aucun, pas de question, un mot le dit.
Future<void> forgetAlbum(
  BuildContext context,
  List<Track> tracks, {
  required String name,
}) async {
  final d = AppScope.of(context).downloader;
  if (d == null) return;
  final byOrigin = <String, List<String>>{};
  for (final t in tracks) {
    if (isRemote(t)) (byOrigin[KeepOrigin.albumOf(t)] ??= []).add(t.path);
  }
  final gone = [
    for (final e in byOrigin.entries) ...await d.toForgetFrom(e.key, e.value),
  ];
  if (!context.mounted) return;
  if (gone.isEmpty) {
    // tout est gardé autrement : seule la raison « album » part
    say(
      ScaffoldMessenger.of(context),
      AppScope.of(context).strings.stillKeptElsewhere,
    );
  } else if (!await confirmRemoval(context, name: name, paths: gone)) {
    return;
  }
  for (final e in byOrigin.entries) {
    await d.forgetFrom(e.key, e.value);
  }
}

/// Demande « Retirer du téléphone ? » avant un retrait voulu par l'utilisateur. Vrai : on retire
/// (tout de suite si la question est éteinte). La case « Ne plus me demander » cochée avec « Retirer »
/// éteint la question ; « Annuler » ne change rien. Le texte compte les morceaux et la taille des
/// copies de [paths] et de leurs jumeaux (qui partent avec).
Future<bool> confirmRemoval(
  BuildContext context, {
  required String name,
  required List<String> paths,
}) async {
  final app = AppScope.of(context);
  if (app.settings?.confirmRemove == false) return true;
  final s = app.strings;
  final songs = <String>{};
  final sizes =
      <
        String,
        int
      >{}; // chaque copie une fois (un jumeau peut être cité deux fois)
  final counted = <String>{}; // un morceau et son jumeau ne font qu'un morceau
  for (final path in paths) {
    if (counted.contains(path)) continue;
    var any = false;
    final group = {path, ...await app.db.twinPaths(path)};
    counted.addAll(group);
    for (final c in group) {
      final row = await app.db.offlineOf(c);
      if (row == null || row.state == OfflineState.failed.name) continue;
      any = true;
      sizes[c] = row.state == OfflineState.done.name ? row.size : 0;
    }
    if (any) songs.add(path);
  }
  final bytes = sizes.values.fold(0, (a, b) => a + b);
  if (!context.mounted) return false;
  final result = await showDialog<_RemoveAnswer>(
    context: context,
    builder: (ctx) => _RemoveDialog(
      title: s.removeConfirmTitle(onIphone),
      body: s.removeConfirmBody(name, songs.length, s.size(bytes), onIphone),
    ),
  );
  if (result == null) return false;
  if (result.dontAsk) {
    app.settings?.confirmRemove = false;
    app.saveSettings?.call();
  }
  return true;
}

class _RemoveAnswer {
  const _RemoveAnswer(this.dontAsk);
  final bool dontAsk;
}

class _RemoveDialog extends StatefulWidget {
  const _RemoveDialog({required this.title, required this.body});
  final String title, body;

  @override
  State<_RemoveDialog> createState() => _RemoveDialogState();
}

class _RemoveDialogState extends State<_RemoveDialog> {
  bool _dontAsk = false;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context).strings;
    return AlertDialog(
      backgroundColor: const Color(0xFF232323),
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFF3A3A3A)),
      ),
      title: Text(
        widget.title,
        style: const TextStyle(
          color: LafleurColors.text,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.body,
            style: const TextStyle(
              color: Color(0xFFCCCCCC),
              fontSize: 14,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          InkWell(
            key: const Key('dontAsk'),
            borderRadius: BorderRadius.circular(6),
            onTap: () => setState(() => _dontAsk = !_dontAsk),
            child: Row(
              children: [
                SizedBox(
                  width: 22,
                  height: 22,
                  child: Checkbox(
                    value: _dontAsk,
                    onChanged: (v) => setState(() => _dontAsk = v ?? false),
                    activeColor: LafleurColors.pink,
                    checkColor: LafleurColors.ink,
                    side: const BorderSide(color: Color(0xFF666666), width: 2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(5),
                    ),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  s.doNotAskAgain,
                  style: const TextStyle(
                    color: LafleurColors.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actionsPadding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          style: OutlinedButton.styleFrom(
            foregroundColor: LafleurColors.text,
            side: const BorderSide(color: Color(0xFF444444)),
            shape: const StadiumBorder(),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          ),
          child: Text(
            s.cancel,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
        ),
        FilledButton(
          key: const Key('confirmRemove'),
          onPressed: () => Navigator.of(context).pop(_RemoveAnswer(_dontAsk)),
          style: FilledButton.styleFrom(
            backgroundColor: LafleurColors.pink,
            foregroundColor: LafleurColors.ink,
            shape: const StadiumBorder(),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          ),
          child: Text(
            s.removeAction,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}
