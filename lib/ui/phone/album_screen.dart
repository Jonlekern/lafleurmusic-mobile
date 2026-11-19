import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../library/db.dart' show OfflineRow;
import '../../library/models.dart';
import '../../player/player.dart';
import '../../theme/colors.dart';
import '../../theme/widgets.dart';
import '../artist_avatar.dart';
import '../cover_image.dart';
import '../cover_mosaic.dart';
import '../format.dart';
import '../../offline/downloader.dart' show KeepOrigin;
import '../keep_actions.dart';
import '../track_menu.dart';
import 'phone_shell.dart';

/// Ouvre l'album [key] ([Album.key]), nommé [album] (depuis l'Accueil : retour « ‹ Albums »).
Future<void> openAlbum(BuildContext context, String album, String key) {
  final app = AppScope.of(context);
  final s = app.strings;
  return pushPhone(
    context,
    AlbumScreen(
      back: s.albumsBack,
      label: s.playlistLabel,
      title: album.isEmpty ? s.unknownArtist : album,
      tracks: app.library.albumTracks(key),
      isAlbum: true,
    ),
  );
}

/// Album, et toute liste de morceaux (Morceaux, artiste, genre, Top 100) : la colonne du milieu du Mac
/// (maquette 1, écran 2). Toucher une ligne joue la liste à partir d'elle ; glisser à gauche = Lire ensuite ;
/// appui long = feuille du bas.
class AlbumScreen extends StatelessWidget {
  const AlbumScreen({
    super.key,
    required this.back,
    required this.label,
    required this.title,
    required this.tracks,
    this.isAlbum = false,
    this.artist,
    this.empty,
  });
  final String back; // texte du retour
  final String label; // ALBUM, ARTISTE, GENRE…
  final String title;
  final Stream<List<Track>> tracks;
  final bool isAlbum; // sa pochette (sinon une mosaïque)
  final String? artist; // page d'artiste : sa photo ronde
  final String? empty; // texte d'une liste vide

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.strings;
    return StreamBuilder<List<Track>>(
      stream: tracks,
      builder: (context, snap) {
        final list = snap.data ?? const <Track>[];
        final minutes = list.fold<int>(0, (m, t) => m + t.durationMs) ~/ 60000;
        final art = artist != null
            ? ArtistAvatar(name: artist!, size: 120)
            : isAlbum
            ? CoverImage(
                trackPath: list.isEmpty ? null : list.first.path,
                size: 120,
                radius: 6,
              )
            : CoverMosaic(tracks: list, size: 120);
        return PhoneScaffold(
          header: PhoneHeader(
            back: back,
            trailing: HeaderButton(
              icon: Icons.more_horiz_rounded,
              onTap: list.isEmpty
                  ? null
                  : () => showTrackSheet(
                      context,
                      title: title,
                      album: isAlbum,
                      tracks: () async => list,
                    ),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  art,
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: const TextStyle(
                            color: Color(0xFF999999),
                            fontSize: 11,
                            letterSpacing: 0.9,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          title,
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
                          '${s.nSongs(list.length)} · ${s.minutes(minutes)}',
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
                    onPressed: list.isEmpty ? null : () => _play(context, list),
                  ),
                  const SizedBox(width: 8),
                  PillButton(
                    label: s.shuffle,
                    icon: Icons.shuffle_rounded,
                    onPressed: list.isEmpty
                        ? null
                        : () => _play(context, list, shuffle: true),
                  ),
                  if (app.downloader != null && list.any(isRemote)) ...[
                    const SizedBox(width: 8),
                    _KeepPill(tracks: list, album: isAlbum),
                  ],
                ],
              ),
              const SizedBox(height: 14),
              if (snap.hasData && list.isEmpty && empty != null)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    empty!,
                    style: const TextStyle(color: LafleurColors.sub),
                  ),
                ),
              PhoneTrackRows(tracks: list),
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
    say(ScaffoldMessenger.of(context), app.strings.nothingOffline(onIphone));
    return;
  }
  app.player.playTracks(list, 0, shuffle: shuffle);
}

/// Le rond ⬇ à côté de Lecture / Aléatoire : garde la liste sur le téléphone, rose quand tout y est
/// (un toucher de plus dit comment la retirer : appui long sur un morceau).
class _KeepPill extends StatelessWidget {
  const _KeepPill({required this.tracks, required this.album});
  final List<Track> tracks;
  final bool album; // gardé avec son album, sinon chaque morceau pour lui-même

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final remote = tracks.where(isRemote).toList();
    return StreamBuilder<Map<String, OfflineRow>>(
      stream: app.db.watchOfflineWithTwins(),
      builder: (context, snap) {
        final kept = remote.every((t) => isKept(t, snap.data ?? const {}));
        return PillButton(
          icon: Icons.arrow_downward_rounded,
          iconColor: kept ? LafleurColors.pink : null,
          tooltip: kept ? null : app.strings.keepOnDevice(onIphone),
          onPressed: () => kept
              ? say(
                  ScaffoldMessenger.of(context),
                  app.strings.alreadyOnDevice(onIphone),
                )
              : keepTracks(
                  context,
                  remote,
                  origin: album ? KeepOrigin.albumOf : KeepOrigin.songOf,
                ),
        );
      },
    );
  }
}

/// Lignes de morceaux du téléphone ; celle qui joue est en rose.
class PhoneTrackRows extends StatelessWidget {
  const PhoneTrackRows({super.key, required this.tracks, this.numbered = true});
  final List<Track> tracks;
  final bool numbered;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    // « jouable ? » lit le disque : une fois par construction, et de nouveau quand les copies ou
    // les comptes changent (pas à chaque mise à jour du lecteur)
    return ListenableBuilder(
      listenable: app.accountService ?? _noChange,
      builder: (context, _) {
        final playable = {for (final t in tracks) t.path: app.playableNow(t)};
        return StreamBuilder<PlayerState>(
          stream: app.player.state,
          initialData: app.player.current,
          builder: (context, snap) {
            final playing = snap.data?.track?.path;
            return Column(
              children: [
                for (final (i, t) in tracks.indexed)
                  PhoneTrackRow(
                    key: ValueKey(t.path),
                    no: numbered ? '${t.trackNo ?? i + 1}' : '${i + 1}',
                    track: t,
                    selected: t.path == playing,
                    playable: playable[t.path]!,
                    onTap: t.missing
                        ? null
                        : playable[t.path]!
                        ? () => app.player.playTracks(tracks, i)
                        : () => say(
                            ScaffoldMessenger.of(context),
                            app.strings.nothingOffline(onIphone),
                          ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

/// Ne change jamais (pas de service de comptes).
final _noChange = ChangeNotifier();

/// Une ligne : numéro, titre, artiste dessous, durée.
class PhoneTrackRow extends StatelessWidget {
  const PhoneTrackRow({
    super.key,
    required this.no,
    required this.track,
    this.selected = false,
    this.playable = true,
    this.sub,
    this.menu = true,
    this.onTap,
  });
  final String no;
  final Track track;
  // sous le titre à la place de l'artiste (playlist : « artiste · album »)
  final String? sub;
  // faux : ni glisser ni appui long (morceau absent de son compte)
  final bool menu;
  final bool selected;
  final bool playable; // faux : grisée, « pas sur le téléphone »
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context).strings;
    final t = track;
    final grey = !playable && !selected;
    final fg = selected
        ? LafleurColors.ink
        : grey
        ? const Color(0xFF555555)
        : LafleurColors.text;
    final dim = selected
        ? LafleurColors.ink
        : grey
        ? const Color(0xFF444444)
        : const Color(0xFFBBBBBB);
    final artist = t.artist.isEmpty ? s.unknownArtist : t.artist;
    final row = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
      decoration: BoxDecoration(
        color: selected ? LafleurColors.pink : null,
        borderRadius: selected ? BorderRadius.circular(8) : null,
        border: selected
            ? null
            : const Border(bottom: BorderSide(color: Color(0xFF1E1E1E))),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            child: Text(
              no,
              style: TextStyle(
                color: dim,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: fg,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  playable ? sub ?? artist : s.notOnDevice(artist, onIphone),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected
                        ? LafleurColors.ink
                        : grey
                        ? const Color(0xFF444444)
                        : const Color(0xFF999999),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          // un morceau absent de son compte n'a pas de durée
          if (menu) ...[
            const SizedBox(width: 12),
            Text(
              clock(Duration(milliseconds: t.durationMs)),
              style: TextStyle(color: dim, fontSize: 13),
            ),
          ],
        ],
      ),
    );
    if (!menu) return Opacity(opacity: t.missing ? 0.35 : 1, child: row);
    return Opacity(
      opacity: t.missing ? 0.35 : 1,
      child: SwipeToPlayNext(
        track: t,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          onLongPress: () => showTrackSheet(
            context,
            title: t.title,
            sub: t.artist.isEmpty ? s.unknownArtist : t.artist,
            tracks: () async => [t],
          ),
          child: row,
        ),
      ),
    );
  }
}
