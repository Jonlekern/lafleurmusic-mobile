import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_scope.dart';
import '../theme/colors.dart';
import '../update/update_service.dart';
import 'keep_actions.dart' show say;

/// Ce que la feuille fait hors de l'appli : ouvrir une adresse dans Safari, le dossier
/// cache d'Android, l'installeur. Remplaçables dans les tests ([reset] après).
class UpdateHooks {
  UpdateHooks._();

  /// Ouvre [Uri] hors de l'appli (iPhone : Safari).
  static Future<bool> Function(Uri) launch = _launchExternal;

  /// Le cache de l'appli (Android) : l'APK va dans `<cache>/updates/`.
  static Future<Directory> Function() cacheDir = getTemporaryDirectory;

  /// L'installeur Android ; sans : celui de `AppScope.device`.
  static Future<bool> Function(String path)? install;

  @visibleForTesting
  static void reset() {
    launch = _launchExternal;
    cacheDir = getTemporaryDirectory;
    install = null;
  }

  static Future<bool> _launchExternal(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// Maquette 19 : la feuille « LAFLEURMUSIC {v} » (ce qui change, puis télécharger et
/// installer sur Android, ou ouvrir l'IPA dans Safari sur iPhone).
Future<void> showUpdateSheet(BuildContext context, UpdateInfo info) {
  final app = AppScope.of(context);
  final service = app.update;
  if (service == null) return Future.value();
  final device = app.device;
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true, // par-dessus le mini-lecteur
    isScrollControlled: true,
    backgroundColor: context.colors.sheet,
    barrierColor: context.colors.scrim,
    shape: RoundedRectangleBorder(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
      side: BorderSide(color: context.colors.borderSoft),
    ),
    builder: (_) => UpdateSheet(
      info: info,
      service: service,
      android: defaultTargetPlatform == TargetPlatform.android,
      launch: UpdateHooks.launch,
      cacheDir: UpdateHooks.cacheDir,
      install:
          UpdateHooks.install ??
          (path) async => await device?.installApk(path) ?? false,
    ),
  );
}

enum _Step { idle, downloading, ready }

class UpdateSheet extends StatefulWidget {
  const UpdateSheet({
    super.key,
    required this.info,
    required this.service,
    required this.android,
    required this.launch,
    required this.cacheDir,
    required this.install,
  });
  final UpdateInfo info;
  final UpdateService service;
  final bool android;
  final Future<bool> Function(Uri) launch;
  final Future<Directory> Function() cacheDir;
  final Future<bool> Function(String path) install;

  @override
  State<UpdateSheet> createState() => _UpdateSheetState();
}

class _UpdateSheetState extends State<UpdateSheet> {
  var _step = _Step.idle;
  double _progress = 0;
  bool _failed = false;
  File?
  _file; // téléchargé et vérifié : « Installer » le rouvre sans retélécharger
  CancelToken? _cancel;
  ModalRoute<Object?>? _route;
  bool _closed =
      false; // la feuille se ferme (ou est fermée) : plus rien ne part

  /// La feuille est encore là et au premier plan (pas pendant l'animation de fermeture).
  bool get _active =>
      mounted && !_closed && (ModalRoute.of(context)?.isCurrent ?? true);

  /// Android avec un APK : télécharger puis installer ; sinon ouvrir le fichier (ou la page).
  bool get _apk => widget.android && widget.info.apkUrl != null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null && !identical(route, _route)) {
      _route = route;
      // fermée : le téléchargement s'arrête dès le début de l'animation, pas seulement à la fin
      route.popped.then((_) => _close());
    }
  }

  void _close() {
    _closed = true;
    _cancel?.cancel();
  }

  @override
  void dispose() {
    // la feuille fermée pendant le téléchargement : il s'arrête, pas d'installeur plus tard
    _close();
    super.dispose();
  }

  Future<void> _download() async {
    final token = _cancel = CancelToken();
    setState(() {
      _step = _Step.downloading;
      _progress = 0;
      _failed = false;
    });
    try {
      final dir = await widget.cacheDir();
      if (token.cancelled || !_active) return;
      final file = await widget.service.downloadApk(
        widget.info,
        dir,
        cancel: token,
        onProgress: (p) {
          if (mounted && !token.cancelled) setState(() => _progress = p);
        },
      );
      if (token.cancelled || !_active) return;
      _file = file;
      await _install();
    } on Object {
      if (!mounted || token.cancelled) return;
      setState(() {
        _step = _Step.idle;
        _failed = true;
      });
    }
  }

  Future<void> _install() async {
    final file = _file;
    if (file == null || !_active) return;
    bool ok;
    try {
      ok = await widget.install(file.path);
    } on Object {
      ok = false;
    }
    if (!mounted) return;
    setState(() {
      if (ok) {
        // Android 8+ passe parfois par « installer des applis inconnues » sans revenir :
        // le fichier reste, « Installer » rouvre l'installeur
        _step = _Step.ready;
      } else {
        _step = _Step.idle;
        _failed = true;
        _file = null;
      }
    });
  }

  Future<void> _open() async {
    final info = widget.info;
    final url = (widget.android ? null : info.ipaUrl) ?? info.pageUrl;
    try {
      await widget.launch(Uri.parse(url));
    } on Object {
      // rien à faire : le bouton reste
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.strings;
    final c = context.colors;
    final info = widget.info;
    final small = TextStyle(color: c.textMuted, fontSize: 12, height: 1.5);
    final String label;
    final VoidCallback? onTap;
    if (!_apk) {
      label = s.updateOpenDownload;
      onTap = _open;
    } else {
      switch (_step) {
        case _Step.idle:
          label = s.updateDownload(info.apkSize);
          onTap = _download;
        case _Step.downloading:
          label = s.updateDownload(info.apkSize);
          onTap = null;
        case _Step.ready:
          label = s.updateInstall;
          onTap = _install;
      }
    }
    final percent = (_progress * 100).floor().clamp(0, 100);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 5,
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: c.outlineDim,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 4, 6, 2),
              child: Text(
                s.updateTitle(info.version),
                style: TextStyle(
                  color: c.text,
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 6, 12),
              child: Text(
                s.updateYouHave(widget.service.current),
                style: TextStyle(color: c.textMuted, fontSize: 13),
              ),
            ),
            if (info.notes.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 0, 6, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final n in info.notes.take(8))
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 16,
                            child: Text('•', style: _note(c)),
                          ),
                          Expanded(child: Text(n, style: _note(c))),
                        ],
                      ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
              child: _BigButton(
                key: const Key('updateAction'),
                label: label,
                onTap: onTap,
              ),
            ),
            if (_apk && _step == _Step.downloading) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 16, 6, 6),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: SizedBox(
                    height: 6,
                    child: Stack(
                      children: [
                        Positioned.fill(child: ColoredBox(color: c.divider)),
                        FractionallySizedBox(
                          widthFactor: _progress.clamp(0.0, 1.0),
                          heightFactor: 1,
                          child: ColoredBox(color: c.pink),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  '${s.updateProgress(percent)} ${s.updateKeeps}',
                  style: small,
                ),
              ),
            ] else ...[
              if (_failed)
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 12, 6, 0),
                  child: Text(
                    s.updateFailed,
                    style: TextStyle(
                      color: c.danger,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 12, 6, 0),
                child: Text(
                  widget.android
                      ? s.updateKeeps
                      : '${s.updateSafariNote} ${s.updateKeeps}',
                  style: small,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static TextStyle _note(LafleurColors c) =>
      TextStyle(color: c.textBright, fontSize: 14, height: 1.6);
}

/// Le gros bouton rose de la feuille (maquette 19 `.big`).
class _BigButton extends StatelessWidget {
  const _BigButton({super.key, required this.label, this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: onTap != null,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: context.colors.pink,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: context.colors.onPink,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ),
  );
}

/// Maquette 19 A : le bandeau en haut de l'Accueil quand une nouvelle version (non écartée)
/// existe. Le toucher ou « Mettre à jour » ouvre la feuille ; ✕ l'écarte pour cette version.
class UpdateBanner extends StatelessWidget {
  const UpdateBanner({super.key, required this.service});
  final UpdateService service;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<UpdateInfo?>(
    valueListenable: service.available,
    builder: (context, info, _) {
      if (info == null) return const SizedBox.shrink();
      final s = AppScope.of(context).strings;
      final c = context.colors;
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: GestureDetector(
          key: const Key('updateBanner'),
          behavior: HitTestBehavior.opaque,
          onTap: () => showUpdateSheet(context, info),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: c.banner,
              border: Border.all(color: c.pink),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.updateNewVersion(info.version),
                        style: TextStyle(
                          color: c.text,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        s.updateTapToSee,
                        style: TextStyle(color: c.textLabel, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Semantics(
                  button: true,
                  child: GestureDetector(
                    onTap: () => showUpdateSheet(context, info),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: c.pink,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        s.updateNow,
                        maxLines: 1,
                        style: TextStyle(
                          color: c.onPink,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Semantics(
                  button: true,
                  label: s.updateHide,
                  child: GestureDetector(
                    key: const Key('updateDismiss'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () => service.dismiss(info),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: c.textDim,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// Maquette 19 A, en bas des Réglages : « Version {v} » et « Chercher une mise à jour › ».
/// Nouvelle version : la feuille (même écartée) ; sinon un petit message.
class UpdateCheckRow extends StatefulWidget {
  const UpdateCheckRow({super.key, required this.service});
  final UpdateService service;

  @override
  State<UpdateCheckRow> createState() => _UpdateCheckRowState();
}

class _UpdateCheckRowState extends State<UpdateCheckRow> {
  bool _busy = false;

  Future<void> _check() async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final s = AppScope.of(context).strings;
    final r = await widget.service.checkNow();
    if (!mounted) return;
    setState(() => _busy = false);
    switch (r) {
      case UpdateCheck.newer:
        final info = widget.service.latest;
        if (info != null) await showUpdateSheet(context, info);
      case UpdateCheck.upToDate:
        say(messenger, s.updateLatest);
      case UpdateCheck.offline:
        say(messenger, s.updateOffline);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context).strings;
    final c = context.colors;
    return Semantics(
      button: true,
      child: GestureDetector(
        key: const Key('updateCheck'),
        behavior: HitTestBehavior.opaque,
        onTap: _check,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: c.field,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Text(
                s.updateVersion(widget.service.current),
                style: TextStyle(
                  color: c.text,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Opacity(
                opacity: _busy ? .5 : 1,
                child: Text(
                  '${s.updateCheck} ›',
                  style: TextStyle(color: c.textMuted, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
