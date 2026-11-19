import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../library/models.dart';
import '../../theme/colors.dart';
import '../coverflow_screen.dart';
import '../keep_actions.dart' show onIphone, say;
import '../phone/accounts_screen.dart';
import '../phone/now_screen.dart';
import '../phone/on_device_screen.dart';
import '../phone/phone_shell.dart';
import '../tablet.dart';
import 'click_wheel.dart';

// Maquette 6 A (maquettes/src/6-molette.html, .ipodscr)
const _screenBg = Color(0xFF111111);
const _titleColor = Color(0xFF999999);
const _screenHeight = 300.0;
const _rowHeight = 37.0; // padding 9 + une ligne de texte de 15 px
const _titleHeight = 19.0; // une ligne de 11 px + 6 dessous
const _screenPad = 8.0; // en haut et en bas de l'écran
const _gap = 34.0; // entre l'écran et la molette
const _top = 14.0; // sous la barre du haut

/// Mode Classic (maquette 6 A) : l'écran façon iPod en haut (titre de la liste, ▶︎ et pile, lignes,
/// la ligne choisie en rose), la molette en bas. Tourner déplace la ligne choisie, le rond du
/// milieu l'ouvre, MENU remonte d'un niveau ; ⏮ ⏭ ▶︎❙❙ commandent le lecteur. Un toucher sur une
/// ligne la choisit et l'ouvre. Les listes sont celles du mode normal (mêmes requêtes).
class ClassicMenu extends StatefulWidget {
  const ClassicMenu({super.key});

  @override
  State<ClassicMenu> createState() => _ClassicMenuState();
}

/// Un niveau de menu : sa liste, la ligne choisie et où la liste était défilée.
class _Level {
  _Level(this.title, {this.chevron = true, this.empty});
  final String title;
  final bool chevron; // › : la ligne ouvre une autre liste
  final String?
  empty; // texte d'une liste vide (comme le mode normal), sinon rien
  int count = 0;
  bool loaded = false;
  String Function(int i) label = _blank;
  bool Function(int i) dim = _never; // grisée : rien à jouer (morceau absent)
  void Function(int i)? choose;
  int selected = 0;
  double offset = 0;
  StreamSubscription<Object?>? sub;

  static String _blank(int _) => '';
  static bool _never(int _) => false;
}

class _ClassicMenuState extends State<ClassicMenu> {
  final _levels = <_Level>[];
  var _scroll = ScrollController(keepScrollOffset: false);

  _Level get _current => _levels.last;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_levels.isEmpty) _levels.add(_root());
  }

  @override
  void dispose() {
    for (final l in _levels) {
      l.sub?.cancel();
    }
    _scroll.dispose();
    super.dispose();
  }

  // ---- niveaux

  _Level _root() {
    final app = AppScope.of(context);
    final s = app.strings;
    final lib = app.library;
    final rows = <(String, VoidCallback?)>[
      (s.coverFlow, _openCoverflow),
      (
        s.artists,
        () => _push(
          _list<(String, int)>(
            s.artists,
            lib.artists(),
            label: (a) => a.$1.isEmpty ? s.unknownArtist : a.$1,
            choose: (l, i) => _push(
              _tracks(
                l[i].$1.isEmpty ? s.unknownArtist : l[i].$1,
                lib.artistTracks(l[i].$1),
              ),
            ),
          ),
        ),
      ),
      (
        s.albumsBack,
        () => _push(
          _list<Album>(
            s.albumsBack,
            lib.albums(),
            label: (a) => a.name.isEmpty ? s.unknownArtist : a.name,
            choose: (l, i) => _push(_album(l[i])),
          ),
        ),
      ),
      (s.songs, () => _push(_tracks(s.songs, lib.allTracks()))),
      (
        s.classicPlaylists,
        () => _push(
          _list<ServerPlaylist>(
            s.classicPlaylists,
            lib.playlists(),
            label: (p) => p.name,
            choose: (l, i) => _push(_playlist(l[i])),
          ),
        ),
      ),
      (
        s.top100,
        () => _push(
          _tracks(
            s.top100,
            lib.top(100).map((l) => [for (final (t, _) in l) t]),
            empty: s.topEmpty,
          ),
        ),
      ),
      // les copies gardées sur le téléphone (sans téléchargeur : rien à montrer)
      (
        s.onDevice(defaultTargetPlatform == TargetPlatform.iOS),
        app.downloader == null
            ? null
            : () => pushPhone(context, const OnDeviceScreen()),
      ),
      (s.classicNowPlaying, () => openNow(context)),
      (s.classicSettings, () => pushPhone(context, const AccountsScreen())),
    ];
    return _Level(s.classicMusic)
      ..loaded = true
      ..count = rows.length
      ..label = ((i) => rows[i].$1)
      ..choose = ((i) => rows[i].$2?.call());
  }

  /// Une liste qui suit [stream] (les mêmes flux que le mode normal).
  _Level _list<T>(
    String title,
    Stream<List<T>> stream, {
    required String Function(T) label,
    required void Function(List<T> items, int i) choose,
    bool Function(T)? dim,
    bool chevron = true,
    String? empty,
  }) {
    final level = _Level(title, chevron: chevron, empty: empty);
    level.sub = stream.listen((items) {
      if (!mounted) return;
      setState(() {
        level
          ..loaded = true
          ..count = items.length
          ..label = ((i) => label(items[i]))
          ..dim = dim == null ? ((_) => false) : ((i) => dim(items[i]))
          ..choose = ((i) => choose(items, i))
          ..selected = math.min(level.selected, math.max(0, items.length - 1));
      });
    });
    return level;
  }

  /// Des morceaux : choisir joue la liste à partir de celui-là, comme le mode normal.
  _Level _tracks(String title, Stream<List<Track>> tracks, {String? empty}) =>
      _list<Track>(
        title,
        tracks,
        label: (t) => t.title,
        dim: (t) => t.missing,
        choose: _playFrom,
        chevron: false,
        empty: empty,
      );

  _Level _album(Album a) => _tracks(
    a.name.isEmpty ? AppScope.of(context).strings.unknownArtist : a.name,
    AppScope.of(context).library.albumTracks(a.key),
  );

  /// Une playlist du serveur : dans l'ordre du serveur, un morceau absent de son compte grisé.
  _Level _playlist(ServerPlaylist p) {
    final app = AppScope.of(context);
    return _list<(String, Track?)>(
      p.name,
      app.db.watchPlaylistItems(p.accountId, p.id),
      label: (item) => item.$2?.title ?? app.strings.missingSong,
      dim: (item) => item.$2 == null || item.$2!.missing,
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
  }

  void _openCoverflow() => openCoverflow(
    context,
    // le Cover Flow se ferme lui-même, puis l'album s'ouvre dans le menu
    onOpen: (a) => WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _push(_album(a));
    }),
  );

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
  }

  /// MENU : un niveau plus haut ; à la racine, rien.
  void _back() {
    if (_levels.length < 2) return;
    setState(() {
      _levels.removeLast().sub?.cancel();
      _swapScroll(_current.offset);
    });
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
    final player = AppScope.of(context).player;
    final level = _current;
    return PopScope(
      // retour d'Android : comme MENU, tant qu'on n'est pas à la racine
      canPop: _levels.length < 2,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: LafleurColors.bg,
        body: SafeArea(
          child: Column(
            children: [
              const PhoneHeader(),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, c) {
                    // petit téléphone : tout se resserre au même rythme, rien ne déborde
                    const ideal = _top + _screenHeight + _gap + ClickWheel.size;
                    final k = math.min(1.0, c.maxHeight / (ideal + _top));
                    final wheel = math.min(ClickWheel.size * k, c.maxWidth);
                    return Column(
                      children: [
                        SizedBox(height: _top * k),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: SizedBox(
                            height: _screenHeight * k,
                            child: _Screen(
                              level: level,
                              scroll: _scroll,
                              onTap: _tap,
                            ),
                          ),
                        ),
                        SizedBox(height: _gap * k),
                        SizedBox.square(
                          dimension: wheel,
                          child: FittedBox(
                            child: ClickWheel(
                              onRotate: _rotate,
                              onSelect: _select,
                              onMenu: _back,
                              onPrevious: player.previous,
                              onNext: player.next,
                              onPlayPause: player.toggle,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// L'écran du haut : le titre, ▶︎ et la pile, les lignes.
class _Screen extends StatelessWidget {
  const _Screen({
    required this.level,
    required this.scroll,
    required this.onTap,
  });
  final _Level level;
  final ScrollController scroll;
  final void Function(int i) onTap;

  @override
  Widget build(BuildContext context) {
    final l = level;
    return Container(
      clipBehavior: Clip.hardEdge,
      padding: const EdgeInsets.symmetric(vertical: _screenPad),
      decoration: BoxDecoration(
        color: _screenBg,
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
                      l.title.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _titleColor,
                        fontSize: 11,
                        letterSpacing: 1,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const ExcludeSemantics(
                    child: CustomPaint(
                      size: Size(35, 10),
                      painter: _StatusPainter(),
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
                      l.empty!,
                      style: const TextStyle(color: LafleurColors.sub),
                    ),
                  )
                : ListView.builder(
                    key: ObjectKey(l),
                    controller: scroll,
                    padding: EdgeInsets.zero,
                    itemExtent: _rowHeight,
                    itemCount: l.count,
                    itemBuilder: (_, i) => ClassicRow(
                      label: l.label(i),
                      selected: i == l.selected,
                      chevron: l.chevron,
                      dim: l.dim(i),
                      onTap: () => onTap(i),
                    ),
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
    this.onTap,
  });
  final String label;
  final bool selected;
  final bool chevron;
  final bool dim; // morceau absent (comme le mode normal : estompé)
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      color: selected ? LafleurColors.ink : LafleurColors.text,
      fontSize: 15,
      fontWeight: FontWeight.w700,
    );
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Opacity(
          opacity: dim ? 0.35 : 1,
          child: Container(
            color: selected ? LafleurColors.pink : null,
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
  const _StatusPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final ink = Paint()..color = _titleColor;
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
  bool shouldRepaint(_StatusPainter old) => false;
}
