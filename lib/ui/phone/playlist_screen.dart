import 'dart:io';

import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../l10n/strings.dart';
import '../../library/db.dart' show OfflineRow;
import '../../library/models.dart';
import '../../library/playlist_store.dart';
import '../../player/player.dart';
import '../../theme/colors.dart';
import '../../theme/widgets.dart';
import '../cover_mosaic.dart';
import '../keep_actions.dart';
import '../tablet.dart';
import '../track_menu.dart';
import 'add_to_playlist_sheet.dart' show askDuplicate, askQuestion;
import 'album_screen.dart';
import 'phone_shell.dart';
import 'playlist_edit_screen.dart';

/// Où vit la playlist, là où celles des serveurs montrent leur compte : « Sur mon iPhone »
/// (Android : « Sur mon téléphone ») pour une playlist du téléphone (plan 9).
String playlistPlace(Strings s, ServerPlaylist p) =>
    p.onPhone ? s.onDevice(onIphone, tablet: onTablet) : p.accountName;

/// Ouvre une playlist du serveur ou du téléphone (depuis l'Accueil : retour « ‹ Accueil »).
Future<void> openPlaylist(BuildContext context, ServerPlaylist p) =>
    pushPhone(context, PlaylistScreen(playlist: p));

/// « Garder » toute la playlist : ses morceaux et son `.m3u8`.
Future<bool> keepPlaylist(BuildContext context, ServerPlaylist p) =>
    keepWith(context, (d) => d.keepPlaylist(p.accountId, p.id));

/// « Retirer » la playlist du téléphone, après la question (maquette 10) : son `.m3u8` et ses
/// morceaux qui ne sont gardés pour aucune autre raison (album, autre playlist, le morceau
/// lui-même : règle Q13). Rien à effacer : pas de question, un mot le dit.
Future<void> forgetPlaylist(BuildContext context, ServerPlaylist p) async {
  final app = AppScope.of(context);
  final d = app.downloader;
  if (d == null) return;
  final paths = await d.playlistSongsToForget(p.accountId, p.id);
  if (!context.mounted) return;
  if (paths.isEmpty) {
    say(ScaffoldMessenger.of(context), app.strings.stillKeptElsewhere);
  } else if (!await confirmRemoval(context, name: p.name, paths: paths)) {
    return;
  }
  await d.forgetPlaylist(p.accountId, p.id);
}

/// Appui long sur une playlist, ou « … » de son écran : la feuille du bas, qui garde ou retire
/// la playlist entière.
Future<void> showPlaylistSheet(BuildContext context, ServerPlaylist p) async {
  final app = AppScope.of(context);
  final recorded = (await app.db.watchKeptPlaylists().first).contains((
    p.accountId,
    p.id,
  ));
  final tracks = [
    for (final (_, t)
        in await app.db.watchPlaylistItems(p.accountId, p.id).first)
      ?t,
  ];
  final rows = await app.db.watchOfflineWithTwins().first;
  // gardée = notée et chacun de ses morceaux gardé (un morceau ajouté sur le serveur, pas
  // encore en file : « Garder » de nouveau)
  final kept = recorded && tracks.where(isRemote).every((t) => isKept(t, rows));
  if (!context.mounted) return;
  await showTrackSheet(
    context,
    title: p.name,
    tracks: () async => tracks,
    kept: kept,
    onKeep: () async {
      if (context.mounted) await keepPlaylist(context, p);
    },
    onRemove: () async {
      if (context.mounted) await forgetPlaylist(context, p);
    },
  );
}

/// Une playlist (maquette 7, écran 11) : comme l'écran Album, « PLAYLIST · compte », les
/// morceaux dans l'ordre (un morceau peut revenir deux fois), « artiste · album » sous chaque
/// titre ; un morceau absent de son compte est grisé. Quand elle peut changer (une playlist
/// du téléphone, ou d'un serveur qui le permet : plan 9, maquette 15, écran D) : « Ajouter »,
/// « Modifier », « Trier » et la lecture ; sinon Lecture, Aléatoire, ⬇.
class PlaylistScreen extends StatefulWidget {
  const PlaylistScreen({super.key, required this.playlist});
  final ServerPlaylist playlist;

  @override
  State<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends State<PlaylistScreen> {
  /// A server playlist: this account may change it (asked to its server when the screen
  /// opens); null while unknown (the edit buttons wait).
  bool? _serverOk;
  var _checked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_checked) return;
    _checked = true;
    if (!widget.playlist.onPhone) _check();
  }

  Future<void> _check() async {
    final store = AppScope.of(context).playlistStore;
    final p = widget.playlist;
    var ok = false;
    try {
      ok =
          await store.canWrite(p.accountId) && await store.checkEditable(p.ref);
    } on Object {
      ok = false;
    }
    if (mounted) setState(() => _serverOk = ok);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.strings;
    final store = app.playlistStore;
    final ref = widget.playlist.ref;
    // the name and cover follow a rename or a new cover; gone (deleted): as it was
    return StreamBuilder<List<ServerPlaylist>>(
      stream: app.db.watchPlaylists(),
      builder: (context, listSnap) {
        final p =
            listSnap.data?.where((l) => l.ref == ref).firstOrNull ??
            widget.playlist;
        return StreamBuilder<List<(String, Track?)>>(
          stream: app.db.watchPlaylistItems(p.accountId, p.id),
          builder: (context, snap) {
            final items = snap.data ?? const <(String, Track?)>[];
            final present = [for (final (_, t) in items) ?t];
            final minutes =
                present.fold<int>(0, (m, t) => m + t.durationMs) ~/ 60000;
            return PhoneScaffold(
              header: PhoneHeader(
                back: onTablet ? s.back : s.home,
                trailing: HeaderButton(
                  icon: Icons.more_horiz_rounded,
                  onTap: present.isEmpty
                      ? null
                      : () => showPlaylistSheet(context, p),
                ),
              ),
              body: ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      PlaylistCover(
                        ref: p.ref,
                        tracks: present,
                        size: 120,
                        stamp: listSnap.data,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              s.playlistOf(playlistPlace(s, p)),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF999999),
                                fontSize: 11,
                                letterSpacing: 0.9,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              p.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                                height: 1.15,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${s.nSongs(items.length)} · ${s.minutes(minutes)}',
                              style: const TextStyle(
                                color: Color(0xFF999999),
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ValueListenableBuilder<Set<PlaylistRef>>(
                    valueListenable: store.readOnlyPlaylists,
                    builder: (context, _, _) {
                      final editable =
                          (p.onPhone || _serverOk == true) &&
                          store.canEdit(p.ref);
                      return editable
                          ? _EditActions(
                              playlist: p,
                              items: items,
                              present: present,
                            )
                          : _PlayActions(playlist: p, present: present);
                    },
                  ),
                  const SizedBox(height: 14),
                  _Rows(
                    items: items,
                    accountName: p.onPhone ? null : p.accountName,
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// Lecture, Aléatoire, ⬇ (une playlist qui ne peut pas changer).
class _PlayActions extends StatelessWidget {
  const _PlayActions({required this.playlist, required this.present});
  final ServerPlaylist playlist;
  final List<Track> present;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.strings;
    return Row(
      children: [
        PillButton(
          label: s.play,
          icon: Icons.play_arrow_rounded,
          primary: true,
          onPressed: present.isEmpty ? null : () => _play(context, present),
        ),
        const SizedBox(width: 8),
        PillButton(
          label: s.shuffle,
          icon: Icons.shuffle_rounded,
          onPressed: present.isEmpty
              ? null
              : () => _play(context, present, shuffle: true),
        ),
        if (app.downloader != null && present.any(isRemote)) ...[
          const SizedBox(width: 8),
          _KeepPlaylistPill(playlist: playlist, tracks: present),
        ],
      ],
    );
  }
}

/// « Ajouter · Modifier · Trier » et ▶ (maquette 15, écran D).
class _EditActions extends StatelessWidget {
  const _EditActions({
    required this.playlist,
    required this.items,
    required this.present,
  });
  final ServerPlaylist playlist;
  final List<(String, Track?)> items;
  final List<Track> present;

  Future<void> _edit(BuildContext context) async {
    final r = await editPlaylist(context, playlist, items);
    if (!context.mounted) return;
    switch (r) {
      case PlaylistDeleted():
        Navigator.of(context).pop();
      case EditFailed(:final message):
        say(ScaffoldMessenger.of(context), message);
      case null:
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context).strings;
    return Row(
      children: [
        _Chip(
          key: const Key('plAdd'),
          icon: Icons.add_rounded,
          label: s.addSongs,
          onTap: () => pushPhone(context, AddSongsScreen(playlist: playlist)),
        ),
        const SizedBox(width: 8),
        _Chip(
          key: const Key('plEdit'),
          icon: Icons.edit_rounded,
          label: s.editPlaylist,
          onTap: () => _edit(context),
        ),
        const SizedBox(width: 8),
        _Chip(
          key: const Key('plSort'),
          icon: Icons.swap_vert_rounded,
          label: s.sortPlaylist,
          onTap: items.length < 2
              ? null
              : () => sortPlaylist(context, playlist, items),
        ),
        const Spacer(),
        Semantics(
          button: true,
          label: s.play,
          child: GestureDetector(
            key: const Key('plPlay'),
            onTap: present.isEmpty ? null : () => _play(context, present),
            child: Opacity(
              opacity: present.isEmpty ? 0.4 : 1,
              child: Container(
                width: 40,
                height: 36,
                decoration: BoxDecoration(
                  color: LafleurColors.pink,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  size: 20,
                  color: Color(0xFF111111),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: onTap == null ? 0.4 : 1,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFF444444)),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: LafleurColors.text),
            const SizedBox(width: 5),
            Text(
              label,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    ),
  );
}

/// La pochette d'une playlist : celle choisie (playlists du téléphone), sinon la mosaïque de
/// ses morceaux. Relue quand [stamp] change (une nouvelle liste des playlists).
class PlaylistCover extends StatefulWidget {
  const PlaylistCover({
    super.key,
    required this.ref,
    required this.tracks,
    required this.size,
    this.stamp,
  });
  final PlaylistRef ref;
  final List<Track> tracks;
  final double size;
  final Object? stamp;

  @override
  State<PlaylistCover> createState() => _PlaylistCoverState();
}

class _PlaylistCoverState extends State<PlaylistCover> {
  Future<File?>? _file;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _file ??= _load();
  }

  @override
  void didUpdateWidget(PlaylistCover old) {
    super.didUpdateWidget(old);
    if (old.ref != widget.ref || !identical(old.stamp, widget.stamp)) {
      _file = _load();
    }
  }

  Future<File?> _load() async {
    if (widget.ref is! PhonePlaylistRef) return null;
    try {
      final f = await AppScope.of(context).playlistStore.coverOf(widget.ref);
      return f != null && await f.exists() ? f : null;
    } on Object {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<File?>(
    future: _file,
    builder: (context, snap) {
      final f = snap.data;
      if (f == null) {
        return CoverMosaic(tracks: widget.tracks, size: widget.size);
      }
      return ClipRRect(
        key: const Key('chosenCover'),
        borderRadius: BorderRadius.circular(6),
        child: Image.file(
          f,
          width: widget.size,
          height: widget.size,
          fit: BoxFit.cover,
        ),
      );
    },
  );
}

/// « Trier » : par titre, artiste, album, ou l'ordre d'ajout inverse ; le nouvel ordre est
/// écrit dans la playlist (sur son serveur, après une question). Les morceaux absents vont
/// à la fin, dans leur ordre.
Future<void> sortPlaylist(
  BuildContext context,
  ServerPlaylist p,
  List<(String, Track?)> items,
) async {
  final app = AppScope.of(context);
  final s = app.strings;
  final by = await showModalBottomSheet<PlaylistSort>(
    context: context,
    useRootNavigator: true,
    backgroundColor: const Color(0xFF232323),
    barrierColor: Colors.black.withValues(alpha: 0.5),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      side: BorderSide(color: Color(0xFF3A3A3A)),
    ),
    builder: (ctx) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 5,
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF555555),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
              child: Text(
                s.sortBy,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            for (final (by, label) in [
              (PlaylistSort.title, s.sortTitle),
              (PlaylistSort.artist, s.sortArtist),
              (PlaylistSort.album, s.sortAlbum),
              (PlaylistSort.reverse, s.sortReverseAdded),
            ])
              InkWell(
                key: Key('sort-${by.name}'),
                borderRadius: BorderRadius.circular(8),
                onTap: () => Navigator.of(ctx).pop(by),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  child: Text(label, style: const TextStyle(fontSize: 16)),
                ),
              ),
          ],
        ),
      ),
    ),
  );
  if (by == null || !context.mounted) return;
  final order = sortOrder(items, by);
  if (order.indexed.every((e) => e.$1 == e.$2)) return; // already in that order
  if (!p.onPhone) {
    final yes = await askQuestion(
      context,
      title: s.sortServerQuestion(p.name),
      body: s.sortServerExplain(p.accountName),
      yes: s.sortPlaylist,
      no: s.cancel,
    );
    if (!yes || !context.mounted) return;
  }
  final messenger = ScaffoldMessenger.of(context);
  try {
    await app.playlistStore.reorder(p.ref, order);
  } on PlaylistWriteException catch (e) {
    say(messenger, s.playlistProblem(e.problem));
  } on Object {
    say(messenger, s.playlistProblem(PlaylistProblem.failed));
  }
}

/// How « Trier » orders a playlist.
enum PlaylistSort { title, artist, album, reverse }

/// The positions of [items] in the order [by] gives (what [PlaylistStore.reorder] takes):
/// absent songs last, in their order; equal ones keep theirs.
List<int> sortOrder(List<(String, Track?)> items, PlaylistSort by) {
  final idx = [for (var i = 0; i < items.length; i++) i];
  if (by == PlaylistSort.reverse) return idx.reversed.toList();
  int cmp(int a, int b) {
    final ta = items[a].$2, tb = items[b].$2;
    if (ta == null || tb == null) {
      if (ta == null && tb == null) return a.compareTo(b);
      return ta == null ? 1 : -1;
    }
    final keys = switch (by) {
      PlaylistSort.title => [(ta.title, tb.title)],
      PlaylistSort.artist => [(ta.artist, tb.artist), (ta.album, tb.album)],
      PlaylistSort.album => [(ta.album, tb.album)],
      PlaylistSort.reverse => const <(String, String)>[],
    };
    for (final (x, y) in keys) {
      final c = sortKey(x).compareTo(sortKey(y));
      if (c != 0) return c;
    }
    if (by != PlaylistSort.title) {
      final c = (ta.disc ?? 0).compareTo(tb.disc ?? 0);
      if (c != 0) return c;
      final n = (ta.trackNo ?? 0).compareTo(tb.trackNo ?? 0);
      if (n != 0) return n;
      final t = sortKey(ta.title).compareTo(sortKey(tb.title));
      if (t != 0) return t;
    }
    return a.compareTo(b);
  }

  return idx..sort(cmp);
}

/// « Ajouter » (maquette 15, écran D) : chercher dans ta musique ; toucher un morceau l'ajoute
/// à la fin de la playlist. Déjà dedans : « Déjà dans « Nom » », « Ignorer » par défaut.
class AddSongsScreen extends StatefulWidget {
  const AddSongsScreen({super.key, required this.playlist});
  final ServerPlaylist playlist;
  @override
  State<AddSongsScreen> createState() => _AddSongsScreenState();
}

class _AddSongsScreenState extends State<AddSongsScreen> {
  String _query = '';
  var _busy = false;

  Future<void> _add(Track t) async {
    if (_busy) return;
    final app = AppScope.of(context);
    final s = app.strings;
    final store = app.playlistStore;
    final p = widget.playlist;
    final messenger = ScaffoldMessenger.of(context);
    _busy = true;
    try {
      final dups = await store.duplicatesIn(p.ref, [t.path]);
      var anyway = false;
      if (dups.isNotEmpty) {
        if (!mounted) return;
        anyway = await askDuplicate(
          context,
          name: p.name,
          tracks: [t],
          dups: dups,
        );
        if (!anyway) return;
      }
      final n = await store.add(p.ref, [t.path], allowDuplicates: anyway);
      if (n > 0) say(messenger, s.addedTo(p.name));
    } on PlaylistWriteException catch (e) {
      say(messenger, s.playlistProblem(e.problem));
    } on Object {
      say(messenger, s.playlistProblem(PlaylistProblem.failed));
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.strings;
    final q = _query.trim();
    return PhoneScaffold(
      header: PhoneHeader(back: widget.playlist.name),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        children: [
          TextField(
            key: const Key('addSongsSearch'),
            autofocus: true,
            onChanged: (v) => setState(() => _query = v),
            cursorColor: LafleurColors.pink,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              hintText: s.searchYourMusic,
              hintStyle: const TextStyle(
                color: Color(0xFF888888),
                fontSize: 14,
              ),
              prefixIcon: const Icon(
                Icons.search_rounded,
                size: 18,
                color: Color(0xFF888888),
              ),
              isDense: true,
              filled: true,
              fillColor: LafleurColors.bar,
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
          if (q.isNotEmpty)
            FutureBuilder<List<Track>>(
              key: ValueKey(q),
              future: app.library.search(q),
              builder: (context, snap) => Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Column(
                  children: [
                    for (final t in snap.data ?? const <Track>[])
                      if (!t.missing)
                        GestureDetector(
                          key: ValueKey('addSong-${t.path}'),
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _add(t),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 11,
                            ),
                            decoration: const BoxDecoration(
                              border: Border(
                                bottom: BorderSide(color: Color(0xFF1E1E1E)),
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        t.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        s.artistAlbum(
                                          t.artist.isEmpty
                                              ? s.unknownArtist
                                              : t.artist,
                                          t.album,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Color(0xFF999999),
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                const Icon(
                                  Icons.add_circle_outline_rounded,
                                  size: 22,
                                  color: LafleurColors.pink,
                                ),
                              ],
                            ),
                          ),
                        ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Lecture / Aléatoire : rien de jouable hors ligne → le dire au lieu de ne rien faire.
void _play(BuildContext context, List<Track> list, {bool shuffle = false}) {
  final app = AppScope.of(context);
  if (!list.any(app.playableNow)) {
    say(
      ScaffoldMessenger.of(context),
      app.strings.nothingOffline(onIphone, tablet: onTablet),
    );
    return;
  }
  app.player.playTracks(list, 0, shuffle: shuffle);
}

/// Le rond ⬇ : garde toute la playlist ; rose quand elle est gardée et que tout y est (un toucher
/// de plus dit comment la retirer).
class _KeepPlaylistPill extends StatelessWidget {
  const _KeepPlaylistPill({required this.playlist, required this.tracks});
  final ServerPlaylist playlist;
  final List<Track> tracks;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final remote = tracks.where(isRemote).toList();
    return StreamBuilder<Set<(String, String)>>(
      stream: app.db.watchKeptPlaylists(),
      builder: (context, keptSnap) => StreamBuilder<Map<String, OfflineRow>>(
        stream: app.db.watchOfflineWithTwins(),
        builder: (context, snap) {
          final recorded = (keptSnap.data ?? const {}).contains((
            playlist.accountId,
            playlist.id,
          ));
          final kept =
              recorded && remote.every((t) => isKept(t, snap.data ?? const {}));
          return PillButton(
            icon: Icons.arrow_downward_rounded,
            iconColor: kept ? LafleurColors.pink : null,
            tooltip: kept
                ? null
                : app.strings.keepOnDevice(onIphone, tablet: onTablet),
            onPressed: () => kept
                ? say(
                    ScaffoldMessenger.of(context),
                    app.strings.alreadyOnDevice(onIphone, tablet: onTablet),
                  )
                : keepPlaylist(context, playlist),
          );
        },
      ),
    );
  }
}

final _never = ChangeNotifier();

/// Les lignes, dans l'ordre de la playlist : un doublon est une ligne de plus, un absent est
/// grisé (rien à jouer). Toucher une ligne joue la playlist à partir d'elle.
class _Rows extends StatelessWidget {
  const _Rows({required this.items, required this.accountName});
  final List<(String, Track?)> items;

  /// Le compte de la playlist ; null pour une playlist du téléphone (un absent : sans sous-titre).
  final String? accountName;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.strings;
    final present = [for (final (_, t) in items) ?t];
    return ListenableBuilder(
      listenable: app.accountService ?? _never,
      builder: (context, _) {
        final playable = {for (final t in present) t.path: app.playableNow(t)};
        return StreamBuilder<PlayerState>(
          stream: app.player.state,
          initialData: app.player.current,
          builder: (context, snap) {
            final playing = snap.data?.track?.path;
            var k = 0; // rang dans la liste jouée (sans les absents)
            return Column(
              children: [
                for (final (i, (path, t)) in items.indexed)
                  if (t == null)
                    PhoneTrackRow(
                      key: ValueKey('item-$i'),
                      no: '${i + 1}',
                      track: Track(
                        path: path,
                        title: s.missingSong,
                        artist: '',
                        album: '',
                        durationMs: 0,
                        hasCover: false,
                        size: 0,
                        missing: true,
                      ),
                      sub: accountName == null
                          ? null
                          : s.notOnAccount(accountName!),
                      menu: false,
                    )
                  else
                    () {
                      final at = k++;
                      final ok = playable[t.path]!;
                      return PhoneTrackRow(
                        key: ValueKey('item-$i'),
                        no: '${i + 1}',
                        track: t,
                        selected: t.path == playing,
                        playable: ok,
                        sub: s.artistAlbum(
                          t.artist.isEmpty ? s.unknownArtist : t.artist,
                          t.album,
                        ),
                        onTap: t.missing
                            ? null
                            : ok
                            ? () => app.player.playTracks(present, at)
                            : () => say(
                                ScaffoldMessenger.of(context),
                                s.nothingOffline(onIphone, tablet: onTablet),
                              ),
                      );
                    }(),
              ],
            );
          },
        );
      },
    );
  }
}
