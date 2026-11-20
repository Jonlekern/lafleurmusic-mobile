import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../library/library_view.dart';
import '../../library/merge.dart';
import '../../library/models.dart';
import '../../player/player.dart';
import '../../settings.dart';
import '../../sources/accounts.dart';
import '../../theme/colors.dart';
import '../cover_image.dart';
import '../coverflow_screen.dart';
import '../track_menu.dart';
import 'accounts_screen.dart';
import 'album_screen.dart';
import 'display_choice.dart';
import 'names_screen.dart';
import 'no_music.dart';
import 'on_device_screen.dart';
import 'albums_screen.dart';
import 'phone_shell.dart';
import 'playlist_screen.dart';

/// Accueil du téléphone = la barre de côté du Mac (maquette 1, écran 1) : comptes, recherche, bibliothèque,
/// albums. L'album du morceau en cours est en rose.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _query = '';
  Stream<List<Account>>? _accounts; // abonnés une fois, pas à chaque image
  Stream<bool>? _anyTrack;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_anyTrack != null) return;
    final app = AppScope.of(context);
    _accounts = app.accounts?.watch();
    _anyTrack = app.library.anyTrack();
  }

  @override
  Widget build(BuildContext context) {
    // sans compte ni morceau : où poser ses fichiers (maquette 16, écran B) ; dès qu'il y en a, l'Accueil habituel
    final accounts = _accounts;
    if (accounts == null) return _home(context);
    return StreamBuilder<List<Account>>(
      stream: accounts,
      builder: (context, a) {
        final list = a.data;
        if (list == null) return ColoredBox(color: context.colors.bg);
        // un compte : l'Accueil habituel
        if (list.isNotEmpty) {
          return _home(context);
        }
        return StreamBuilder<bool>(
          stream: _anyTrack,
          builder: (context, t) {
            final any = t.data;
            if (any == null) return ColoredBox(color: context.colors.bg);
            return any
                ? _home(context)
                : PhoneScaffold(
                    header: PhoneHeader(
                      trailing: HeaderButton(
                        icon: Icons.settings_rounded,
                        size: 16,
                        onTap: () => pushPhone(context, const AccountsScreen()),
                      ),
                    ),
                    body: const NoMusicBody(),
                  );
          },
        );
      },
    );
  }

  Widget _home(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.strings;
    void open(Widget screen) => pushPhone(context, screen);
    final searching = _query.trim().isNotEmpty;
    return PhoneScaffold(
      header: PhoneHeader(
        status: const _OfflineLabel(),
        trailing: HeaderButton(
          icon: Icons.settings_rounded,
          size: 16,
          onTap: () => open(const AccountsScreen()),
        ),
      ),
      // tirer la liste vers le bas : synchronise tous les comptes
      body: RefreshIndicator(
        color: context.colors.pink,
        backgroundColor: context.colors.bar,
        onRefresh: () => app.accountService?.syncAll() ?? Future.value(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          children: [
            const _AccountChips(),
            const SizedBox(height: 10),
            TextField(
              onChanged: (v) => setState(() => _query = v),
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: s.search,
                hintStyle: TextStyle(
                  color: context.colors.textDim,
                  fontSize: 14,
                ),
                isDense: true,
                filled: true,
                fillColor: context.colors.bar,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 11,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            if (searching)
              FutureBuilder<List<Track>>(
                key: ValueKey(_query),
                future: app.library.search(_query),
                builder: (_, snap) => Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: PhoneTrackRows(
                    tracks: snap.data ?? const [],
                    numbered: false,
                  ),
                ),
              )
            else ...[
              PhoneSection(s.library),
              PhoneItem(
                label: s.coverFlow,
                onTap: () => openCoverflow(
                  context,
                  // Cover Flow se ferme lui-même, puis l'album s'ouvre
                  onOpen: (a) => WidgetsBinding.instance.addPostFrameCallback(
                    (_) => context.mounted
                        ? openAlbum(context, a.name, a.key)
                        : null,
                  ),
                ),
              ),
              PhoneItem(
                label: s.songs,
                onTap: () => open(
                  AlbumScreen(
                    back: s.home,
                    label: s.library,
                    title: s.songs,
                    tracks: app.library.allTracks(),
                  ),
                ),
              ),
              PhoneItem(
                label: s.albums,
                onTap: () => open(const AlbumsScreen()),
              ),
              PhoneItem(
                label: s.artists,
                onTap: () => open(
                  NamesScreen(
                    title: s.artists,
                    names: app.library.artists(),
                    artists: true,
                  ),
                ),
              ),
              PhoneItem(
                label: s.genres,
                onTap: () => open(
                  NamesScreen(title: s.genres, names: app.library.genres()),
                ),
              ),
              PhoneItem(
                label: s.top100,
                onTap: () => open(
                  AlbumScreen(
                    back: s.home,
                    label: s.topLabel,
                    title: s.mostPlayed,
                    tracks: app.library
                        .top(100)
                        .map((l) => [for (final (t, _) in l) t]),
                    empty: s.topEmpty,
                  ),
                ),
              ),
              // les copies gardées sur le téléphone (sans téléchargeur : rien à montrer)
              PhoneItem(
                label: s.onDevice(defaultTargetPlatform == TargetPlatform.iOS),
                onTap: app.downloader == null
                    ? null
                    : () => open(const OnDeviceScreen()),
              ),
              // le titre ouvre aussi l'écran Albums (tri, écoutés récemment), comme la ligne Albums
              PhoneSection(
                s.playlists,
                onTap: () => open(const AlbumsScreen()),
              ),
              StreamBuilder<List<Album>>(
                stream: app.library.albums(),
                builder: (context, albums) => StreamBuilder<Set<String>>(
                  stream: app.downloader == null
                      ? null
                      : app.library.keptAlbums(),
                  builder: (context, keptSnap) => StreamBuilder<PlayerState>(
                    stream: app.player.state,
                    initialData: app.player.current,
                    builder: (context, st) {
                      final now = st.data?.track;
                      final playing = now == null ? null : albumKeyOf(now);
                      final kept = keptSnap.data ?? const <String>{};
                      return Column(
                        children: [
                          for (final a in albums.data ?? const <Album>[])
                            PhoneItem(
                              kept: kept.contains(a.key),
                              leading: CoverImage(
                                trackPath: a.coverTrackPath,
                                size: 30,
                              ),
                              label: a.name.isEmpty ? s.unknownArtist : a.name,
                              selected: a.key == playing,
                              onTap: () => openAlbum(context, a.name, a.key),
                              onLongPress: () => showTrackSheet(
                                context,
                                title: a.name,
                                album: true,
                                tracks: () =>
                                    app.library.albumTracks(a.key).first,
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
              const _ServerPlaylists(),
            ],
          ],
        ),
      ),
    );
  }
}

/// « PLAYLISTS DU SERVEUR » (« PLAYLISTS » avec celles du téléphone, plan 9) sous les albums
/// (maquette 7, écran 10) : mosaïque, nom, ⬇ rose si gardée, le compte en petit en mode
/// Tout / Perso. Rien quand aucun compte n'en a.
class _ServerPlaylists extends StatelessWidget {
  const _ServerPlaylists();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return StreamBuilder<List<ServerPlaylist>>(
      stream: app.library.playlists(),
      builder: (context, snap) {
        final lists = snap.data ?? const <ServerPlaylist>[];
        if (lists.isEmpty) return const SizedBox.shrink();
        // le compte en mode Tout / Perso ; une playlist du téléphone : « Sur mon iPhone »,
        // seulement à côté de playlists de serveur
        final tagged =
            app.settings?.displayMode != DisplayMode.one &&
            lists.any((p) => !p.onPhone);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PhoneSection(
              lists.any((p) => p.onPhone)
                  ? app.strings.allPlaylists
                  : app.strings.serverPlaylists,
            ),
            for (final p in lists)
              PhoneItem(
                key: ValueKey('playlist-${p.accountId}-${p.id}'),
                kept: p.kept,
                tag: tagged ? playlistPlace(app.strings, p) : null,
                leading: PlaylistCover(
                  ref: p.ref,
                  tracks: p.covers,
                  size: 30,
                  radius: 4,
                  stamp: p,
                ),
                label: p.name,
                onTap: () => openPlaylist(context, p),
                onLongPress: () => showPlaylistSheet(context, p),
              ),
          ],
        );
      },
    );
  }
}

/// « Hors ligne » à gauche de la barre du haut quand aucun serveur n'a répondu.
class _OfflineLabel extends StatelessWidget {
  const _OfflineLabel();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final service = app.accountService;
    if (service == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: service,
      builder: (_, _) => service.offline
          ? Text(
              app.strings.offlineLabel,
              style: TextStyle(
                color: context.colors.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            )
          : const SizedBox.shrink(),
    );
  }
}

/// Puces des comptes (maquette 1) : « Tout ▾ » (ouvre Tout / Perso), puis une puce par compte
/// (= « Un compte »). La puce du mode en cours est cerclée de rose. Toujours visibles, même
/// avec un seul compte.
class _AccountChips extends StatefulWidget {
  const _AccountChips();

  @override
  State<_AccountChips> createState() => _AccountChipsState();
}

class _AccountChipsState extends State<_AccountChips> {
  final _first = GlobalKey();

  Future<void> _chooseGroup(List<Account> list) async {
    final app = AppScope.of(context);
    final s = app.strings;
    final box = _first.currentContext?.findRenderObject();
    final overlay = Overlay.of(context).context.findRenderObject();
    if (box is! RenderBox || overlay is! RenderBox) return;
    final pos = RelativeRect.fromRect(
      Rect.fromPoints(
        box.localToGlobal(Offset(0, box.size.height), ancestor: overlay),
        box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );
    final mode = app.settings?.displayMode;
    final picked = await showMenu<DisplayMode>(
      context: context,
      position: pos,
      color: context.colors.bar,
      items: [
        for (final (m, label) in [
          (DisplayMode.all, s.allAccounts),
          (DisplayMode.custom, s.customDisplay),
        ])
          PopupMenuItem(
            value: m,
            child: Text(
              label,
              style: TextStyle(
                color: mode == m ? context.colors.pink : context.colors.text,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
      ],
    );
    if (picked == null || !mounted) return;
    app.chooseDisplay(picked, order: list);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final accounts = app.accounts;
    if (accounts == null) return const SizedBox.shrink();
    return StreamBuilder<List<Account>>(
      stream: accounts.watch(),
      builder: (_, snap) {
        final list = snap.data ?? const <Account>[];
        if (list.isEmpty) return const SizedBox.shrink();
        final settings = app.settings;
        final mode = settings?.displayMode ?? DisplayMode.all;
        final shown = settings == null
            ? const <String>{}
            : LibraryView.visibleOf([for (final a in list) a.id], settings);
        return ListenableBuilder(
          // l'écran Comptes peut changer le mode pendant que l'Accueil est dessous
          listenable: app.libraryView?.revision ?? const _Never(),
          builder: (_, _) => Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              PhoneChip(
                mode == DisplayMode.custom
                    ? app.strings.customDisplay
                    : app.strings.allAccounts,
                key: _first,
                on: mode != DisplayMode.one,
                menu: true,
                onTap: () => _chooseGroup(list),
              ),
              for (final a in list)
                PhoneChip(
                  a.name,
                  key: ValueKey('chip-${a.id}'),
                  on: mode == DisplayMode.one && shown.contains(a.id),
                  onTap: () {
                    app.chooseDisplay(DisplayMode.one, account: a.id);
                    setState(() {});
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Never implements Listenable {
  const _Never();
  @override
  void addListener(VoidCallback listener) {}
  @override
  void removeListener(VoidCallback listener) {}
}

class PhoneChip extends StatelessWidget {
  const PhoneChip(
    this.label, {
    super.key,
    this.on = false,
    this.menu = false,
    this.onTap,
  });
  final String label;
  final bool on;
  final bool menu; // ▾ : ouvre un choix
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final fg = on ? context.colors.pink : context.colors.text;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.fromLTRB(12, 6, menu ? 8 : 12, 6),
        decoration: BoxDecoration(
          border: Border.all(
            color: on ? context.colors.pink : context.colors.border,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: fg,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (menu) Icon(Icons.arrow_drop_down_rounded, size: 16, color: fg),
          ],
        ),
      ),
    );
  }
}

/// Titre de section (BIBLIOTHÈQUE, ALBUMS).
class PhoneSection extends StatelessWidget {
  const PhoneSection(this.text, {super.key, this.onTap});
  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
      child: Text(
        text,
        style: TextStyle(
          color: context.colors.textMuted,
          fontSize: 11,
          letterSpacing: 1,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}

/// Ligne de l'Accueil : gros texte gras, › à droite ; rose quand elle est choisie.
class PhoneItem extends StatelessWidget {
  const PhoneItem({
    super.key,
    required this.label,
    this.leading,
    this.selected = false,
    this.kept = false,
    this.tag,
    this.onTap,
    this.onLongPress,
  });
  final bool kept; // ⬇ rose : tout l'album est sur le téléphone
  final String?
  tag; // en petit après le nom (le compte d'une playlist du serveur)
  final String label;
  final Widget? leading;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? context.colors.ink : context.colors.text;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: 12,
            vertical: leading != null ? 11 : 11,
          ),
          decoration: BoxDecoration(
            color: selected ? context.colors.pink : null,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 12)],
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: fg,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (kept) ...[
                      const SizedBox(width: 6),
                      Icon(
                        Icons.arrow_downward_rounded,
                        size: 14,
                        color: selected
                            ? context.colors.ink
                            : context.colors.pink,
                      ),
                    ],
                    if (tag != null) ...[
                      const SizedBox(width: 10),
                      Text(
                        tag!,
                        maxLines: 1,
                        style: TextStyle(
                          color: selected
                              ? context.colors.ink
                              : context.colors.textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: selected ? context.colors.ink : context.colors.textFaint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
