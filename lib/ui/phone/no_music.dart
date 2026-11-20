import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../app_scope.dart';
import '../../offline/device.dart';
import '../../theme/colors.dart';
import '../keep_actions.dart' show say;
import 'account_form.dart';
import 'new_playlist_screen.dart' show PillButton;
import 'phone_shell.dart';

/// Accueil sans aucun morceau ni compte (maquette 16, écran B) : où poser les fichiers, choisir un autre
/// dossier, ajouter un compte.
class NoMusicBody extends StatefulWidget {
  const NoMusicBody({super.key});

  @override
  State<NoMusicBody> createState() => _NoMusicBodyState();
}

class _NoMusicBodyState extends State<NoMusicBody> {
  String? _path; // Android : le dossier choisi ; iPhone : le chemin de Fichiers (rien à lire)
  bool _busy = false;

  bool get _iphone => defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPath());
  }

  Future<void> _loadPath() async {
    final device = AppScope.of(context).device;
    if (device == null) return;
    try {
      final path = (await device.musicRoot()).path;
      if (mounted) setState(() => _path = path);
    } on Object {
      // chemin inconnu : le dossier par défaut est dit
    }
  }

  Future<void> _chooseFolder() async {
    if (_busy) return;
    final app = AppScope.of(context);
    final device = app.device;
    if (device == null) return;
    final s = app.strings;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final PickedFolder? c;
      try {
        c = await device.pickFolder();
      } on FolderNotLocalException {
        say(messenger, s.folderNotLocal);
        return;
      } on FolderNotWritableException {
        say(messenger, s.folderNotWritable);
        return;
      } on Object {
        say(messenger, s.folderMoveFailed);
        return;
      }
      if (c == null) return;
      var ok = true;
      try {
        final downloader = app.downloader;
        if (downloader != null) {
          ok = (await downloader.adoptRoot(
            commit: () => device.commitFolder(c!),
          )).ok;
        } else {
          await device.commitFolder(c);
        }
      } on Object {
        ok = false;
      }
      if (!ok) {
        await device.releaseCandidate();
        say(messenger, s.folderMoveFailed);
        return;
      }
      await app.accountService?.refreshRoot();
      unawaited(app.localFolder?.rescan());
      await _loadPath();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.strings;
    final grey = TextStyle(
      color: context.colors.textMuted,
      fontSize: 13,
      height: 1.5,
    );
    final bold = TextStyle(
      color: context.colors.textBody,
      fontWeight: FontWeight.w700,
    );
    // iPhone : le chemin de Fichiers tant que le dossier est celui de l'appli ; sinon le dossier choisi
    final chosen = app.settings?.musicFolder != null;
    final String lead, where;
    if (_iphone && !chosen) {
      lead = s.putFilesInFilesApp;
      where = s.defaultFolder(true);
    } else {
      lead = s.filesPutIn;
      final path = _path;
      where = path == null
          ? s.defaultFolder(_iphone)
          : _iphone
          ? p.split(path).reversed.take(2).toList().reversed.join(' › ')
          : path;
    }
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(28, 20, 28, 60),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.music_note_rounded,
              size: 52,
              color: context.colors.text,
            ),
            const SizedBox(height: 14),
            Text(
              s.noMusicYet,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Text.rich(
              TextSpan(
                style: grey,
                children: [
                  TextSpan(text: lead),
                  TextSpan(text: where, style: bold),
                  const TextSpan(text: '.\n'),
                  TextSpan(text: s.filesAppearByThemselves),
                ],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 26),
            Opacity(
              opacity: _busy ? 0.5 : 1,
              child: PillButton(
                s.chooseAnotherFolder,
                key: const Key('chooseAnotherFolder'),
                onTap: _busy ? () {} : _chooseFolder,
              ),
            ),
            const SizedBox(height: 12),
            PinkOutlineButton(
              s.addAnAccount,
              key: const Key('addAnAccount'),
              onTap: () => pushPhone(context, const AccountFormScreen()),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bouton en contour rose, texte rose (maquette 16 : « Ajouter un compte », « Juste la musique de mon iPhone »).
class PinkOutlineButton extends StatelessWidget {
  const PinkOutlineButton(
    this.label, {
    super.key,
    required this.onTap,
    this.wide = false,
  });
  final String label;
  final VoidCallback onTap;
  final bool wide; // toute la largeur (écran A)

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Container(
      width: wide ? double.infinity : null,
      alignment: wide ? Alignment.center : null,
      padding: EdgeInsets.symmetric(horizontal: wide ? 20 : 28, vertical: 13),
      decoration: BoxDecoration(
        border: Border.all(color: context.colors.pink),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: context.colors.pink,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}
