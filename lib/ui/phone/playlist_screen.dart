import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../l10n/strings.dart';
import '../../library/db.dart' show OfflineRow;
import '../../library/models.dart';
import '../../player/player.dart';
import '../../theme/colors.dart';
import '../../theme/widgets.dart';
import '../cover_mosaic.dart';
import '../keep_actions.dart';
import '../tablet.dart';
import '../track_menu.dart';
import 'album_screen.dart';
import 'phone_shell.dart';

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

/// Une playlist du serveur (maquette 7, écran 11) : comme l'écran Album, « PLAYLIST · compte »,
/// les morceaux dans l'ordre du serveur (un morceau peut revenir deux fois), « artiste · album »
/// sous chaque titre ; un morceau absent de son compte est grisé. Lecture seule.
class PlaylistScreen extends StatelessWidget {
  const PlaylistScreen({super.key, required this.playlist});
  final ServerPlaylist playlist;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.strings;
    final p = playlist;
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
                  CoverMosaic(tracks: present, size: 120),
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
              Row(
                children: [
                  PillButton(
                    label: s.play,
                    icon: Icons.play_arrow_rounded,
                    primary: true,
                    onPressed: present.isEmpty
                        ? null
                        : () => _play(context, present),
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
                    _KeepPlaylistPill(playlist: p, tracks: present),
                  ],
                ],
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
