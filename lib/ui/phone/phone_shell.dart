import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../app_scope.dart';
import '../../sources/accounts.dart';
import '../../theme/colors.dart';
import '../library_screen.dart';
import 'account_form.dart';
import 'album_screen.dart';
import 'home_screen.dart';
import 'mini_player.dart';
import 'now_screen.dart';

/// Android ou iOS.
bool isMobilePlatform(TargetPlatform p) =>
    p == TargetPlatform.android || p == TargetPlatform.iOS;

/// Téléphone (Android, iOS) : toujours la vue téléphone ; sur ordinateur, la vue en colonnes du Mac.
class AdaptiveHome extends StatelessWidget {
  const AdaptiveHome({super.key, this.debugStart, this.debugScreens});
  final String? debugStart; // voir [PhoneShell.debugStart]
  final List<Widget> Function()? debugScreens; // voir [PhoneShell.debugScreens]

  /// Android et iOS : toujours le téléphone (plan 1, téléphones seulement, quelle que soit la largeur).
  /// Mac, Windows, Linux : les colonnes, sauf fenêtre étroite (< 900 px).
  static bool isPhone(Size size, [TargetPlatform? platform]) =>
      isMobilePlatform(platform ?? defaultTargetPlatform) || size.width < 900;

  @override
  Widget build(BuildContext context) => isPhone(MediaQuery.sizeOf(context))
      ? PhoneShell(debugStart: debugStart, debugScreens: debugScreens)
      : const LibraryScreen();
}

/// Téléphone debout (maquette 1) : les colonnes du Mac empilées. Accueil → Album / Morceaux / Artistes /
/// Genres / Top 100 → En cours. Retour : glisser depuis le bord gauche, ou le bouton retour d'Android.
class PhoneShell extends StatefulWidget {
  const PhoneShell({super.key, this.debugStart, this.debugScreens});

  /// Mode démo (debug) : écran ouvert au lancement, « album » ou « now ».
  final String? debugStart;

  /// Mode démo (debug) : écrans ouverts l'un sur l'autre au lancement (Comptes, Ajouter un compte).
  final List<Widget> Function()? debugScreens;

  @override
  State<PhoneShell> createState() => _PhoneShellState();
}

class _PhoneShellState extends State<PhoneShell> {
  final _nav = GlobalKey<NavigatorState>();
  StreamSubscription<String>? _skipped;

  @override
  void initState() {
    super.initState();
    final start = widget.debugStart;
    if (start != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _nav.currentContext;
        if (ctx == null) return;
        final album = AppScope.of(ctx).player.current.track?.album;
        if (start == 'album' && album != null) {
          openAlbum(ctx, album);
        } else if (start == 'now') {
          openNow(ctx);
        }
      });
    }
    final screens = widget.debugScreens;
    if (screens != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final nav = _nav.currentState;
        for (final s in screens()) {
          nav?.push(CupertinoPageRoute<void>(builder: (_) => s));
        }
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = AppScope.of(context);
    // même message que sur le Mac quand un morceau illisible est passé
    _skipped ??= app.player.skipped.listen((path) {
      if (!mounted) return;
      final title =
          app.player.queue?.order
              .where((t) => t.path == path)
              .firstOrNull
              ?.title ??
          p.basename(path);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: LafleurColors.bar,
          content: Text(
            app.strings.unreadableSkipped(title),
            style: const TextStyle(color: LafleurColors.text),
          ),
        ),
      );
    });
  }

  @override
  void dispose() {
    _skipped?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => NavigatorPopHandler<Object?>(
    onPopWithResult: (_) => _nav.currentState?.maybePop(),
    child: Navigator(
      key: _nav,
      onGenerateRoute: (_) =>
          CupertinoPageRoute<void>(builder: (_) => const _Start()),
    ),
  );
}

/// Premier écran : l'Accueil ; sur un téléphone sans aucun compte, « Ajouter un compte » (premier lancement),
/// remplacé par l'Accueil dès que le compte est enregistré.
class _Start extends StatefulWidget {
  const _Start();

  @override
  State<_Start> createState() => _StartState();
}

class _StartState extends State<_Start> {
  static bool get _mobile =>
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.android;

  Stream<List<Account>>? _accounts; // abonné une fois, pas à chaque image
  bool _ready = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ready) return;
    _ready = true;
    // Mac en fenêtre étroite : bibliothèque locale, pas de compte obligatoire
    if (_mobile) _accounts = AppScope.of(context).accounts?.watch();
  }

  @override
  Widget build(BuildContext context) {
    final stream = _accounts;
    if (stream == null) return const HomeScreen();
    return StreamBuilder<List<Account>>(
      stream: stream,
      builder: (_, snap) {
        final list = snap.data;
        if (list == null) return const ColoredBox(color: LafleurColors.bg);
        return list.isEmpty
            ? const AccountFormScreen(first: true)
            : const HomeScreen();
      },
    );
  }
}

/// Ouvre un écran du téléphone : glisse depuis la droite, retour en glissant depuis le bord gauche.
Future<void> pushPhone(BuildContext context, Widget screen) =>
    Navigator.of(context)
        .push(CupertinoPageRoute<void>(builder: (_) => screen));

/// Barre du haut du téléphone : logo LAFLEURMUSIC, « ‹ retour » rose à gauche, bouton à droite.
class PhoneHeader extends StatelessWidget {
  const PhoneHeader({
    super.key,
    this.back,
    this.leading,
    this.trailing,
    this.status,
  });
  final String? back; // « ‹ Albums »
  final Widget?
  status; // petit texte à gauche sans déplacer le logo (« Hors ligne »)
  final Widget? leading; // à la place du retour (⌄ d'En cours)
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final small = back != null || leading != null;
    return Container(
      height: 50,
      width: double.infinity,
      decoration: const BoxDecoration(
        color: LafleurColors.bar,
        border: Border(bottom: BorderSide(color: Colors.black)),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Padding(
            padding: EdgeInsets.only(left: small ? 40 : 0),
            child: Image.asset(
              'assets/logo-texte-grand.png',
              height: small ? 11 : 15,
            ),
          ),
          if (back != null)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).maybePop(),
                child: Padding(
                  padding: const EdgeInsets.only(left: 14, right: 8),
                  child: Row(
                    children: [
                      const Text('‹ ', style: _backStyle),
                      Text(back!, style: _backStyle),
                    ],
                  ),
                ),
              ),
            ),
          if (status != null)
            Positioned(
              left: 16,
              top: 0,
              bottom: 0,
              child: Center(child: status),
            ),
          if (leading != null)
            Positioned(left: 4, top: 0, bottom: 0, child: leading!),
          if (trailing != null)
            Positioned(right: 4, top: 0, bottom: 0, child: trailing!),
        ],
      ),
    );
  }

  static const _backStyle = TextStyle(
    color: LafleurColors.pink,
    fontSize: 15,
    fontWeight: FontWeight.w700,
  );
}

/// Petit bouton gris de la barre du haut (⚙︎, ⋯).
class HeaderButton extends StatelessWidget {
  const HeaderButton({
    super.key,
    required this.icon,
    this.onTap,
    this.color = const Color(0xFFBBBBBB),
    this.size = 20,
  });
  final IconData icon;
  final VoidCallback? onTap;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => IconButton(
    onPressed: onTap,
    icon: Icon(icon, size: size, color: color),
  );
}

/// Écran du téléphone : barre du haut, contenu, mini-lecteur en bas ([mini]).
class PhoneScaffold extends StatelessWidget {
  const PhoneScaffold({
    super.key,
    required this.header,
    required this.body,
    this.mini = true,
  });
  final Widget header;
  final Widget body;
  final bool mini;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      backgroundColor: LafleurColors.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            header,
            Expanded(
              child: MediaQuery.removePadding(
                context: context,
                removeBottom: true,
                child: body,
              ),
            ),
            if (mini) const MiniPlayer(),
            SizedBox(height: bottom), // barre d'accueil d'iOS
          ],
        ),
      ),
    );
  }
}
