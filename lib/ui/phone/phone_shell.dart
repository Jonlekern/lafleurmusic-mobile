import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../app_scope.dart';
import '../../library/merge.dart';
import '../../library/models.dart';
import '../../sources/accounts.dart';
import '../../theme/colors.dart';
import '../classic/classic_shell.dart';
import '../coverflow_screen.dart';
import '../library_screen.dart';
import '../tablet.dart';
import 'account_form.dart';
import 'album_screen.dart';
import 'home_screen.dart';
import 'mini_player.dart';
import 'now_screen.dart';

/// Téléphone : la vue téléphone ; tablette (Android, iOS, plus petit côté ≥ 600 px) et ordinateur : les colonnes du Mac.
class AdaptiveHome extends StatefulWidget {
  const AdaptiveHome({super.key, this.debugStart, this.debugScreens});
  final String? debugStart; // voir [PhoneShell.debugStart]
  final List<Widget> Function()? debugScreens; // voir [PhoneShell.debugScreens]

  /// Android et iOS : le téléphone, sauf sur une tablette (plus petit côté ≥ 600 px : [isTablet], toutes
  /// orientations, debout comme couchée). Mac, Windows, Linux : les colonnes, sauf fenêtre étroite (< 900 px).
  static bool isPhone(Size size, [TargetPlatform? platform]) {
    final p = platform ?? defaultTargetPlatform;
    return isMobilePlatform(p) ? !isTablet(size, p) : size.width < 900;
  }

  @override
  State<AdaptiveHome> createState() => _AdaptiveHomeState();
}

class _AdaptiveHomeState extends State<AdaptiveHome> {
  bool? _tablet;
  ValueNotifier<bool>? _classic;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final classic = AppScope.of(context).classicMode;
    if (identical(classic, _classic)) return;
    _classic?.removeListener(_modeChanged);
    _classic = classic?..addListener(_modeChanged);
  }

  /// Retour au mode normal : il n'a pas de volume, celui de l'appli revient à fond
  /// (la molette du Mode Classic a pu le baisser).
  void _modeChanged() {
    if (_classic?.value ?? true) return;
    final player = AppScope.of(context).player;
    if (player.volume != 100) player.setVolume(100);
  }

  @override
  void dispose() {
    _classic?.removeListener(_modeChanged);
    setTabletMode(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final tablet = isTablet(size, defaultTargetPlatform);
    // une seule source (la fenêtre) pour la disposition, les textes et les orientations ; en vue partagée,
    // une fenêtre étroite redevient un téléphone et ses orientations reviennent
    setTabletMode(tablet);
    if (tablet != _tablet) {
      final first = _tablet == null;
      _tablet = tablet;
      if (tablet || !first) {
        if (isMobilePlatform(defaultTargetPlatform)) {
          SystemChrome.setPreferredOrientations(
            tablet ? DeviceOrientation.values : mobileOrientations,
          );
        }
      }
    }
    if (!AdaptiveHome.isPhone(size)) return const LibraryScreen();
    // le réglage Mode Classic remplace la vue téléphone, à chaud (le lecteur ne change pas)
    final classic = AppScope.of(context).classicMode ?? _normalMode;
    return ValueListenableBuilder<bool>(
      valueListenable: classic,
      builder: (_, on, _) => on
          ? ClassicShell(
              debugStart: widget.debugStart,
              debugScreens: widget.debugScreens,
            )
          : PhoneShell(
              debugStart: widget.debugStart,
              debugScreens: widget.debugScreens,
            ),
    );
  }
}

/// Téléphone debout (maquette 1) : les colonnes du Mac empilées. Accueil → Album / Morceaux / Artistes /
/// Genres / Top 100 → En cours. Retour : glisser depuis le bord gauche, ou le bouton retour d'Android.
class PhoneShell extends StatefulWidget {
  const PhoneShell({
    super.key,
    this.debugStart,
    this.debugScreens,
    this.home = const HomeScreen(),
  });

  /// Le premier écran : l'Accueil, ou le menu du Mode Classic.
  final Widget home;

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
  StreamSubscription<List<Album>>? _albumsSub;
  List<Album> _albums = const [];

  // Cover Flow couché : l'écran du dessus (En cours reste debout), l'album ouvert en dernier, et
  // « Ouvrir l'album » depuis le Cover Flow (l'album s'affiche couché jusqu'au retour ou au redressement)
  late final _routes = _RouteWatcher(_routesChanged);
  bool _suppressFlow = false;
  int _suppressDepth = 0;
  String? _lastAlbumKey;
  bool _lockedUpright = false;

  static bool get _mobile => isMobilePlatform(defaultTargetPlatform);

  void _routesChanged() {
    final top = _routes.topNamed;
    final key = top?.name == 'album' ? top?.arguments : null;
    if (key is String) _lastAlbumKey = key;
    if (_suppressFlow && _routes.depth < _suppressDepth) _suppressFlow = false;
    // En cours reste dessiné debout : le téléphone ne se couche pas pendant qu'on y est
    final now = top?.name == 'now';
    if (_mobile && now != _lockedUpright) {
      _lockedUpright = now;
      SystemChrome.setPreferredOrientations(
        now ? uprightOnly : mobileOrientations,
      );
    }
    // (appelé pendant que le navigateur se construit : on redessine après)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void initState() {
    super.initState();
    final start = widget.debugStart;
    if (start != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _nav.currentContext;
        if (ctx == null) return;
        final playing = AppScope.of(ctx).player.current.track;
        if (start == 'album' && playing != null) {
          openAlbum(ctx, playing.album, albumKeyOf(playing));
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
    _albumsSub?.cancel();
    if (_mobile && _lockedUpright) {
      SystemChrome.setPreferredOrientations(mobileOrientations);
    }
    super.dispose();
  }

  void _openFromFlow(Album a) {
    final ctx = _nav.currentContext;
    if (ctx == null) return;
    setState(() {
      _suppressFlow = true;
      _suppressDepth = _routes.depth + 1;
    });
    openAlbum(ctx, a.name, a.key);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final landscape = _mobile && size.width > size.height;
    // les albums ne sont suivis qu'à partir du premier passage couché
    if (landscape) {
      _albumsSub ??= AppScope.of(context).library.albums().listen((a) {
        if (mounted) setState(() => _albums = a);
      });
    }
    if (!landscape) _suppressFlow = false;
    final onNow = _routes.topNamed?.name == 'now';
    final flow = landscape && !onNow && !_suppressFlow && _albums.isNotEmpty;
    final nav = NavigatorPopHandler<Object?>(
      // le Cover Flow est posé sur les écrans cachés : retour ne doit pas les défaire sans qu'on le voie
      // (au pied de la pile, retour quitte l'appli comme d'habitude)
      enabled: !flow,
      onPopWithResult: (_) {
        // (le Cover Flow couvre les écrans : on ne les défait pas sans qu'on le voie)
        if (!flow) _nav.currentState?.maybePop();
      },
      child: Navigator(
        key: _nav,
        observers: [_routes],
        onGenerateRoute: (_) =>
            CupertinoPageRoute<void>(builder: (_) => _Start(home: widget.home)),
      ),
    );
    final app = AppScope.of(context);
    final now = app.player.current.track;
    final key = now != null ? albumKeyOf(now) : _lastAlbumKey;
    final i = _albums.indexWhere((a) => a.key == key);
    // le Cover Flow se pose sur l'écran ; dessous, le navigateur reste où il était
    return PopScope(
      canPop: !flow || _routes.depth <= 1,
      child: Stack(
        children: [
          Positioned.fill(child: nav),
          if (flow)
            Positioned.fill(
              child: CoverflowScreen(
                phone: true,
                albums: _albums,
                initial: i < 0 ? 0 : i,
                onOpen: _openFromFlow,
              ),
            ),
        ],
      ),
    );
  }
}

/// Sans réglage (tests, démo) : le mode normal.
final _normalMode = ValueNotifier<bool>(false);

/// Suit les écrans empilés : leur nombre, et le premier écran nommé en partant du dessus (les feuilles et
/// boîtes de dialogue n'ont pas de nom : En cours reste En cours dessous).
class _RouteWatcher extends NavigatorObserver {
  _RouteWatcher(this._changed);
  final VoidCallback _changed;
  final _stack = <Route<dynamic>>[];

  int get depth => _stack.length;
  RouteSettings? get topNamed => _stack.reversed
      .map((r) => r.settings)
      .where((r) => r.name != null)
      .firstOrNull;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.add(route);
    _changed();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.remove(route);
    _changed();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final i = oldRoute == null ? -1 : _stack.indexOf(oldRoute);
    if (i >= 0 && newRoute != null) {
      _stack[i] = newRoute;
    } else if (newRoute != null) {
      _stack.add(newRoute);
    }
    _changed();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.remove(route);
    _changed();
  }
}

/// Premier écran : l'Accueil ; sur un téléphone sans aucun compte, « Ajouter un compte » (premier lancement),
/// remplacé par l'Accueil dès que le compte est enregistré.
class _Start extends StatefulWidget {
  const _Start({required this.home});
  final Widget home;

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
    if (stream == null) return widget.home;
    return StreamBuilder<List<Account>>(
      stream: stream,
      builder: (_, snap) {
        final list = snap.data;
        if (list == null) return const ColoredBox(color: LafleurColors.bg);
        return list.isEmpty
            ? const AccountFormScreen(first: true)
            : widget.home;
      },
    );
  }
}

/// Ouvre un écran du téléphone : glisse depuis la droite, retour en glissant depuis le bord gauche.
Future<void> pushPhone(
  BuildContext context,
  Widget screen, {
  RouteSettings? settings,
}) => Navigator.of(context)
    .push(CupertinoPageRoute<void>(settings: settings, builder: (_) => screen));

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
