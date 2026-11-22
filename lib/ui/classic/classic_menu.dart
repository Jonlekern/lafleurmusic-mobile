import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../l10n/strings.dart';
import '../../library/merge.dart';
import '../../library/models.dart';
import '../../player/player.dart';
import '../../theme/colors.dart';
import '../keep_actions.dart' show onIphone, say;
import '../phone/accounts_screen.dart';
import '../phone/on_device_screen.dart';
import '../phone/phone_shell.dart';
import '../tablet.dart';
import '../update_sheet.dart';
import '../../update/update_service.dart';
import 'classic_coverflow.dart';
import 'classic_frame.dart';
import 'classic_now.dart';
import 'click_wheel.dart';

// Maquette 6 A (maquettes/src/6-molette.html, .ipodscr) ; couleurs : context.classicColors
const _rowHeight = 37.0; // padding 9 + une ligne de texte de 15 px
const _titleHeight = 19.0; // une ligne de 11 px + 6 dessous
const _screenPad = 8.0; // en haut et en bas de l'écran

/// Mode Classic (maquette 6 A) : l'écran façon iPod en haut (titre de la liste, ▶︎ et pile, lignes,
/// la ligne choisie en rose), la molette en bas. Tourner déplace la ligne choisie, le rond du
/// milieu l'ouvre, MENU remonte d'un niveau ; ⏮ ⏭ ▶︎❙❙ commandent le lecteur. Un toucher sur une
/// ligne la choisit et l'ouvre. Les listes sont celles du mode normal (mêmes requêtes).
class ClassicMenu extends StatefulWidget {
  const ClassicMenu({super.key, this.controller});

  /// Pour la vue téléphone, dont le Cover Flow couché est posé sur le menu.
  final ClassicMenuController? controller;

  @override
  State<ClassicMenu> createState() => _ClassicMenuState();
}

/// Le lien entre la vue téléphone et le menu : couché, le Cover Flow est posé sur le menu,
/// qui n'est pas fait d'écrans empilés (ses niveaux ne sont pas des routes).
class ClassicMenuController {
  /// Vrai à la racine (MUSIQUE) : il n'y a rien à remonter.
  final atRoot = ValueNotifier<bool>(true);
  _ClassicMenuState? _menu;

  /// Un album ouvert depuis le Cover Flow couché : le menu l'ouvre comme une liste, à la place
  /// de l'écran ouvert depuis le menu (on le voit en relevant le téléphone).
  void openAlbum(Album album) => _menu?._openFromFlow(album);

  void dispose() => atRoot.dispose();
}

/// Un niveau de menu : sa liste, la ligne choisie et où la liste était défilée. Les textes
/// sont relus à chaque image ([Strings] : la langue peut changer).
class _Level {
  _Level(this.title, {this.chevron = true, this.empty, this.flow = false});
  final String Function(Strings s) title;
  // maquette 18 : le Cover Flow dans l'écran (des albums), pas des lignes
  final bool flow;
  final bool chevron; // › : la ligne ouvre une autre liste
  // texte d'une liste vide (comme le mode normal), sinon rien
  final String Function(Strings s)? empty;
  int count = 0;
  bool loaded = false;
  String Function(Strings s, int i) label = _blank;
  // estompée, sans toucher possible (morceau absent, ligne sans effet), comme le mode normal
  bool Function(int i) dim = _no;
  // grisée : pas sur le téléphone, rien à jouer hors ligne (PhoneTrackRow `playable`)
  bool Function(int i) playable = _yes;
  // l'élément de la ligne, pour le retrouver
  Object? Function(int i) key = _none;
  // l'élément de la ligne lui-même (les albums du Cover Flow)
  Object? Function(int i) item = _none;
  // pour « artiste · pas sur le téléphone »
  String Function(int i) artist = _empty;
  void Function(int i)? choose;
  final playableCache = <String, bool>{};
  int selected = 0;
  double offset = 0;
  StreamSubscription<Object?>? sub;

  static String _blank(Strings _, int _) => '';
  static bool _no(int _) => false;
  static bool _yes(int _) => true;
  static Object? _none(int _) => null;
  static String _empty(int _) => '';
}

class _ClassicMenuState extends State<ClassicMenu> {
  final _levels = <_Level>[];
  var _scroll = ScrollController(keepScrollOffset: false);
  Listenable? _service;
  StreamSubscription<PlayerState>? _playing;
  bool _idle = false; // rien en cours : « En cours » est estompé
  // maquette 19 : « Mise à jour » en haut de la racine tant qu'une nouvelle version existe
  ValueListenable<UpdateInfo?>? _update;
  int Function() _rootCount = () => 0;

  _Level get _current => _levels.last;

  @override
  void initState() {
    super.initState();
    widget.controller?._menu = this;
  }

  @override
  void didUpdateWidget(ClassicMenu old) {
    super.didUpdateWidget(old);
    if (identical(old.controller, widget.controller)) return;
    if (identical(old.controller?._menu, this)) old.controller?._menu = null;
    widget.controller
      ?.._menu = this
      ..atRoot.value = _levels.length < 2;
  }

  void _syncRoot() => widget.controller?.atRoot.value = _levels.length < 2;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_playing == null) {
      final player = AppScope.of(context).player;
      _idle = player.current.track == null;
      _playing = player.state.listen((st) {
        final idle = st.track == null;
        if (mounted && idle != _idle) setState(() => _idle = idle);
      });
    }
    if (_levels.isEmpty) {
      _update = AppScope.of(context).update?.available;
      _update?.addListener(_updateChanged);
      _levels.add(_root());
    }
    // copies ou comptes changés : « jouable ? » se relit (comme PhoneTrackRows)
    if (_service == null) {
      _service = AppScope.of(context).accountService;
      _service?.addListener(_accountsChanged);
    }
  }

  @override
  void dispose() {
    _service?.removeListener(_accountsChanged);
    _update?.removeListener(_updateChanged);
    _playing?.cancel();
    final c = widget.controller;
    if (c != null && identical(c._menu, this)) c._menu = null;
    for (final l in _levels) {
      l.sub?.cancel();
    }
    _scroll.dispose();
    super.dispose();
  }

  void _accountsChanged() {
    if (!mounted) return;
    setState(() {
      for (final l in _levels) {
        l.playableCache.clear();
      }
    });
  }

  /// La ligne « Mise à jour » arrive ou part : la racine garde la même ligne choisie.
  void _updateChanged() {
    if (!mounted || _levels.isEmpty) return;
    final root = _levels.first;
    final n = _rootCount();
    if (n == root.count) return;
    setState(() {
      root.selected = (root.selected + n - root.count).clamp(0, n - 1);
      root.count = n;
    });
    if (identical(root, _current)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && identical(root, _current)) _reveal();
      });
    }
  }

  // ---- niveaux

  _Level _root() {
    final app = AppScope.of(context);
    final lib = app.library;
    String name(Strings s, String n) => n.isEmpty ? s.unknownArtist : n;
    void openNow() => openClassicNow(context);
    final base = <(String Function(Strings), VoidCallback?)>[
      ((s) => s.coverFlow, () => _push(_coverflow())),
      (
        (s) => s.artists,
        () => _push(
          _list<(String, int)>(
            (s) => s.artists,
            lib.artists(),
            label: (s, a) => name(s, a.$1),
            key: (a) => a.$1,
            choose: (l, i) => _push(
              _tracks((s) => name(s, l[i].$1), lib.artistTracks(l[i].$1)),
            ),
          ),
        ),
      ),
      (
        (s) => s.albumsBack,
        () => _push(
          _list<Album>(
            (s) => s.albumsBack,
            lib.albums(),
            label: (s, a) => name(s, a.name),
            key: (a) => a.key,
            choose: (l, i) => _push(_album(l[i])),
          ),
        ),
      ),
      ((s) => s.songs, () => _push(_tracks((s) => s.songs, lib.allTracks()))),
      (
        (s) => s.classicPlaylists,
        () => _push(
          _list<ServerPlaylist>(
            (s) => s.classicPlaylists,
            lib.playlists(),
            label: (_, p) => p.name,
            key: (p) => (p.accountId, p.id),
            choose: (l, i) => _push(_playlist(l[i])),
          ),
        ),
      ),
      (
        (s) => s.top100,
        () => _push(
          _tracks(
            (s) => s.top100,
            lib.top(100).map((l) => [for (final (t, _) in l) t]),
            empty: (s) => s.topEmpty,
          ),
        ),
      ),
      // les copies gardées sur le téléphone (sans téléchargeur : rien à montrer)
      (
        (s) => s.onDevice(defaultTargetPlatform == TargetPlatform.iOS),
        app.downloader == null
            ? null
            : () => pushPhone(context, const OnDeviceScreen()),
      ),
      ((s) => s.classicNowPlaying, openNow),
      (
        (s) => s.classicSettings,
        () => pushPhone(context, const AccountsScreen()),
      ),
    ];
    // une nouvelle version (non écartée) : « Mise à jour » en premier, qui ouvre la feuille
    final update = _update;
    List<(String Function(Strings), VoidCallback?)> rows() => [
      if (update?.value case final info?)
        ((s) => s.classicUpdate, () => showUpdateSheet(context, info)),
      ...base,
    ];
    _rootCount = () => rows().length;
    // sans effet : sans téléchargeur, ou « En cours » quand rien n'est en cours
    bool off(int i) {
      final r = rows()[i];
      return r.$2 == null || (_idle && r.$2 == openNow);
    }

    return _Level((s) => s.classicMusic)
      ..loaded = true
      ..count = rows().length
      ..label = ((s, i) => rows()[i].$1(s))
      ..dim = off
      ..choose = ((i) => off(i) ? null : rows()[i].$2?.call());
  }

  /// Une liste qui suit [stream] (les mêmes flux que le mode normal). Quand la liste change,
  /// la ligne choisie reste sur le même élément ([key]) ; s'il a disparu, au même rang.
  _Level _list<T>(
    String Function(Strings s) title,
    Stream<List<T>> stream, {
    required String Function(Strings s, T item) label,
    required Object? Function(T item) key,
    required void Function(List<T> items, int i) choose,
    bool Function(T item)? dim,
    bool Function(_Level level, T item)? playable,
    String Function(T item)? artist,
    bool chevron = true,
    String Function(Strings s)? empty,
    int Function(List<T> items)? start,
    bool flow = false,
  }) {
    final level = _Level(title, chevron: chevron, empty: empty, flow: flow);
    // [start] : sur la première liste non vide (une liste vide d'abord ne le perd pas)
    var started = start == null;
    level.sub = stream.listen((items) {
      if (!mounted) return;
      final was = level.loaded && level.count > 0
          ? level.key(level.selected)
          : null;
      setState(() {
        var at = !started && items.isNotEmpty
            ? start!(items)
            : math.min(level.selected, math.max(0, items.length - 1));
        if (items.isNotEmpty) started = true;
        if (was != null) {
          // le plus proche de l'ancien rang (un morceau peut revenir deux fois dans une playlist)
          var best = -1;
          for (var j = 0; j < items.length; j++) {
            if (key(items[j]) != was) continue;
            if (best < 0 ||
                (j - level.selected).abs() < (best - level.selected).abs()) {
              best = j;
            }
          }
          if (best >= 0) at = best;
        }
        level
          ..loaded = true
          ..count = items.length
          ..label = ((s, i) => label(s, items[i]))
          ..key = ((i) => key(items[i]))
          ..item = ((i) => items[i])
          ..dim = dim == null ? _Level._no : ((i) => dim(items[i]))
          ..playable = playable == null
              ? _Level._yes
              : ((i) => playable(level, items[i]))
          ..artist = artist == null ? _Level._empty : ((i) => artist(items[i]))
          ..choose = ((i) => choose(items, i))
          ..selected = at;
        level.playableCache.clear();
      });
      // après la mise en page de la nouvelle liste
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && identical(level, _current)) _reveal();
      });
    });
    return level;
  }

  /// Jouable maintenant ? Lu une fois par morceau et par liste (« jouable ? » lit le disque).
  bool _playableNow(_Level level, Track t) =>
      level.playableCache[t.path] ??= context
          .getInheritedWidgetOfExactType<AppScope>()!
          .playableNow(t); // appelé pendant la mise en page de la liste

  /// Des morceaux : choisir joue la liste à partir de celui-là, comme le mode normal.
  _Level _tracks(
    String Function(Strings s) title,
    Stream<List<Track>> tracks, {
    String Function(Strings s)? empty,
  }) => _list<Track>(
    title,
    tracks,
    label: (_, t) => t.title,
    key: (t) => t.path,
    dim: (t) => t.missing,
    playable: _playableNow,
    artist: (t) => t.artist,
    choose: _playFrom,
    chevron: false,
    empty: empty,
  );

  _Level _album(Album a) => _tracks(
    (s) => a.name.isEmpty ? s.unknownArtist : a.name,
    AppScope.of(context).library.albumTracks(a.key),
  );

  /// Une playlist du serveur : dans l'ordre du serveur, un morceau absent de son compte grisé.
  _Level _playlist(ServerPlaylist p) {
    final app = AppScope.of(context);
    return _list<(String, Track?)>(
      (_) => p.name,
      app.db.watchPlaylistItems(p.accountId, p.id),
      label: (s, item) => item.$2?.title ?? s.missingSong,
      key: (item) => item.$1,
      dim: (item) => item.$2 == null || item.$2!.missing,
      playable: (level, item) =>
          item.$2 == null || _playableNow(level, item.$2!),
      artist: (item) => item.$2?.artist ?? '',
      chevron: false,
      choose: (items, i) {
        if (items[i].$2 == null) return;
        final present = [for (final (_, t) in items) ?t];
        final at = items.take(i).where((it) => it.$2 != null).length;
        _playFrom(present, at);
      },
    );
  }

  void _playFrom(List<Track> list, int i) {
    final app = AppScope.of(context);
    final t = list[i];
    if (t.missing) return;
    if (!app.playableNow(t)) {
      say(
        ScaffoldMessenger.of(context),
        app.strings.nothingOffline(onIphone, tablet: onTablet),
      );
      return;
    }
    app.player.playTracks(list, i);
    // comme l'iPod : le morceau choisi s'ouvre dans En cours ; MENU revient à la liste
    openClassicNow(context);
  }

  /// Couché, « Ouvrir l'album » du Cover Flow : l'écran ouvert depuis le menu se ferme, l'album
  /// s'ouvre dans le menu (comme la ligne Cover Flow).
  void _openFromFlow(Album a) {
    if (!mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
    _push(_album(a));
  }

  /// Maquette 18 : le Cover Flow dans l'écran, la molette dessous. Il part de l'album en cours
  /// (sinon du premier) ; tourner change d'album, le milieu ouvre l'album dans le menu (MENU y
  /// revient), ▶︎❙❙ joue l'album.
  _Level _coverflow() {
    final app = AppScope.of(context);
    final now = app.player.current.track;
    final playing = now == null ? null : albumKeyOf(now);
    return _list<Album>(
      (s) => s.coverFlow,
      app.library.albums(),
      label: (s, a) => a.name.isEmpty ? s.unknownArtist : a.name,
      key: (a) => a.key,
      choose: (l, i) => _push(_album(l[i])),
      start: (l) => math.max(0, l.indexWhere((a) => a.key == playing)),
      flow: true,
      empty: (s) => s.noMusicYet, // comme le mode normal sans musique
    );
  }

  /// ▶︎❙❙ dans le Cover Flow : l'album choisi depuis le début, seulement les morceaux jouables
  /// maintenant ; aucun : « rien à jouer hors ligne », comme une ligne de morceau ([_playFrom]).
  Future<void> _playAlbum() async {
    final l = _current;
    if (!l.flow || l.count == 0) return;
    final album = l.item(l.selected)! as Album;
    final app = AppScope.of(context);
    final tracks = await app.library.albumTracks(album.key).first;
    if (!mounted) return;
    final ok = [
      for (final t in tracks)
        if (!t.missing && app.playableNow(t)) t,
    ];
    if (ok.isEmpty) {
      say(
        ScaffoldMessenger.of(context),
        app.strings.nothingOffline(onIphone, tablet: onTablet),
      );
      return;
    }
    await app.player.playTracks(ok, 0);
  }

  // ---- navigation

  /// Une nouvelle liste défilée de [offset] ; l'ancienne se défait après l'image.
  void _swapScroll(double offset) {
    final old = _scroll;
    _scroll = ScrollController(
      initialScrollOffset: offset,
      keepScrollOffset: false,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
  }

  void _push(_Level level) {
    setState(() {
      _current.offset = _scroll.hasClients ? _scroll.offset : 0;
      _levels.add(level);
      _swapScroll(0);
    });
    _syncRoot();
  }

  /// MENU : un niveau plus haut ; à la racine, rien.
  void _back() {
    if (_levels.length < 2) return;
    setState(() {
      _levels.removeLast().sub?.cancel();
      _swapScroll(_current.offset);
    });
    _syncRoot();
  }

  void _rotate(int steps) {
    final l = _current;
    if (l.count == 0) return;
    final next = (l.selected + steps).clamp(0, l.count - 1);
    if (next == l.selected) return;
    setState(() => l.selected = next);
    _reveal();
  }

  /// La ligne choisie reste à l'écran : la liste défile juste ce qu'il faut.
  void _reveal() {
    if (!_scroll.hasClients) return;
    final p = _scroll.position;
    final top = _current.selected * _rowHeight;
    if (top < p.pixels) {
      _scroll.jumpTo(top);
    } else if (top + _rowHeight > p.pixels + p.viewportDimension) {
      _scroll.jumpTo(top + _rowHeight - p.viewportDimension);
    }
  }

  void _select() {
    final l = _current;
    if (l.count == 0) return;
    l.choose?.call(l.selected);
  }

  void _tap(int i) {
    setState(() => _current.selected = i);
    _select();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final player = app.player;
    final level = _current;
    // lecteur d'écran : la ligne choisie, et celle d'un cran plus loin
    String? wheelValue(int step) => level.count > 0
        ? level.label(
            app.strings,
            (level.selected + step).clamp(0, level.count - 1),
          )
        : null;
    return PopScope(
      // retour d'Android : comme MENU, tant qu'on n'est pas à la racine
      canPop: _levels.length < 2,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: ClassicFrame(
        screen: _Screen(
          strings: app.strings,
          level: level,
          scroll: _scroll,
          onTap: _tap,
          onMove: _rotate,
          onOpen: _select,
        ),
        // l'arc rose suit le morceau : seule la molette se redessine à chaque position
        wheel: PlayerProgress(
          player: player,
          builder: (_, progress) => ClickWheel(
            onRotate: _rotate,
            onSelect: _select,
            onMenu: _back,
            onPrevious: player.previous,
            onNext: player.next,
            onPlayPause: level.flow ? _playAlbum : player.toggle,
            semanticLabel: app.strings.wheel,
            semanticValue: wheelValue(0),
            semanticIncreasedValue: wheelValue(1),
            semanticDecreasedValue: wheelValue(-1),
            progress: progress,
          ),
        ),
      ),
    );
  }
}

/// L'écran du haut : le titre, ▶︎ et la pile, les lignes.
class _Screen extends StatelessWidget {
  const _Screen({
    required this.strings,
    required this.level,
    required this.scroll,
    required this.onTap,
    required this.onMove,
    required this.onOpen,
  });
  final Strings strings;
  final _Level level;
  final ScrollController scroll;
  final void Function(int i) onTap;
  final void Function(int steps) onMove;
  final VoidCallback
  onOpen; // la pochette du milieu touchée : comme le bouton du milieu

  @override
  Widget build(BuildContext context) {
    final l = level;
    final classic = context.classicColors;
    return Container(
      clipBehavior: Clip.hardEdge,
      padding: const EdgeInsets.symmetric(vertical: _screenPad),
      decoration: BoxDecoration(
        color: classic.screen,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: _titleHeight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l.title(strings).toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: classic.title,
                        fontSize: 11,
                        letterSpacing: 1,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ExcludeSemantics(
                    child: CustomPaint(
                      size: const Size(35, 10),
                      painter: _StatusPainter(classic.title),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: l.loaded && l.count == 0 && l.empty != null
                ? Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 9,
                    ),
                    child: Text(
                      l.empty!(strings),
                      style: TextStyle(color: context.colors.sub),
                    ),
                  )
                : l.flow
                ? ClassicCoverflow(
                    count: l.count,
                    index: l.selected,
                    album: (i) => l.item(i)! as Album,
                    onMove: onMove,
                    onOpen: onOpen,
                  )
                : ListView.builder(
                    key: ObjectKey(l),
                    controller: scroll,
                    padding: EdgeInsets.zero,
                    itemExtent: _rowHeight,
                    itemCount: l.count,
                    itemBuilder: (_, i) {
                      final dim = l.dim(i);
                      final playable = l.playable(i);
                      final artist = l.artist(i);
                      return ClassicRow(
                        label: l.label(strings, i),
                        selected: i == l.selected,
                        chevron: l.chevron,
                        dim: dim,
                        playable: playable,
                        // comme le sous-titre de PhoneTrackRow, dit avant de toucher
                        hint: playable
                            ? null
                            : strings.notOnDevice(
                                artist.isEmpty ? strings.unknownArtist : artist,
                                onIphone,
                                tablet: onTablet,
                              ),
                        // comme le mode normal : une ligne sans effet ne se touche pas
                        onTap: dim ? null : () => onTap(i),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// Une ligne de l'écran : le texte, › si elle ouvre une liste ; en rose quand elle est choisie.
class ClassicRow extends StatelessWidget {
  const ClassicRow({
    super.key,
    required this.label,
    this.selected = false,
    this.chevron = true,
    this.dim = false,
    this.playable = true,
    this.hint,
    this.onTap,
  });
  final String label;
  final bool selected;
  final bool chevron;
  final bool
  dim; // morceau absent, ligne sans effet (comme le mode normal : estompée)
  final bool
  playable; // faux : grisée, pas sur le téléphone (comme PhoneTrackRow)
  // lecteur d'écran seulement (« artiste · pas sur le téléphone »)
  final String? hint;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      color: selected
          ? context.colors.ink
          : playable
          ? context.colors.text
          : context.classicColors.notOnPhone,
      fontSize: 15,
      fontWeight: FontWeight.w700,
    );
    return Semantics(
      // une ligne sans effet n'est pas un bouton (comme le mode normal)
      button: onTap != null,
      selected: selected,
      hint: hint,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Opacity(
          opacity: dim ? 0.35 : 1,
          child: Container(
            color: selected ? context.colors.pink : null,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: style,
                  ),
                ),
                if (chevron) ...[
                  const SizedBox(width: 8),
                  ExcludeSemantics(child: Text('›', style: style)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// « ▶︎ ▮▮▮ » à droite du titre (maquette 6 A) : un triangle et la pile en trois barres.
class _StatusPainter extends CustomPainter {
  const _StatusPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final ink = Paint()..color = color;
    canvas.drawPath(
      Path()
        ..moveTo(0, 0)
        ..lineTo(9, 5)
        ..lineTo(0, 10)
        ..close(),
      ink,
    );
    for (var i = 0; i < 3; i++) {
      canvas.drawRect(Rect.fromLTWH(16 + i * 7.5, 3, 3.5, 7), ink);
    }
  }

  @override
  bool shouldRepaint(_StatusPainter old) => old.color != color;
}
