import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../library/models.dart';
import '../../player/player.dart';
import '../../theme/colors.dart';
import '../../theme/widgets.dart';
import '../artist_avatar.dart';
import '../cover_image.dart';
import '../cover_mosaic.dart';
import '../format.dart';
import '../track_menu.dart';
import 'phone_shell.dart';

/// Ouvre un album (depuis l'Accueil : retour « ‹ Albums »).
Future<void> openAlbum(BuildContext context, String album) {
  final app = AppScope.of(context);
  final s = app.strings;
  return pushPhone(
    context,
    AlbumScreen(
      back: s.albumsBack,
      label: s.playlistLabel,
      title: album.isEmpty ? s.unknownArtist : album,
      tracks: app.db.watchAlbumTracks(album),
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
                    onPressed: list.isEmpty
                        ? null
                        : () => app.player.playTracks(list, 0),
                  ),
                  const SizedBox(width: 8),
                  PillButton(
                    label: s.shuffle,
                    icon: Icons.shuffle_rounded,
                    onPressed: list.isEmpty
                        ? null
                        : () => app.player.playTracks(list, 0, shuffle: true),
                  ),
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

/// Lignes de morceaux du téléphone ; celle qui joue est en rose.
class PhoneTrackRows extends StatelessWidget {
  const PhoneTrackRows({super.key, required this.tracks, this.numbered = true});
  final List<Track> tracks;
  final bool numbered;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
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
                onTap: t.missing
                    ? null
                    : () => app.player.playTracks(tracks, i),
              ),
          ],
        );
      },
    );
  }
}

/// Une ligne : numéro, titre, artiste dessous, durée.
class PhoneTrackRow extends StatelessWidget {
  const PhoneTrackRow({
    super.key,
    required this.no,
    required this.track,
    this.selected = false,
    this.onTap,
  });
  final String no;
  final Track track;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context).strings;
    final t = track;
    final fg = selected ? LafleurColors.ink : LafleurColors.text;
    final dim = selected ? LafleurColors.ink : const Color(0xFFBBBBBB);
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
                  t.artist.isEmpty ? s.unknownArtist : t.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected
                        ? LafleurColors.ink
                        : const Color(0xFF999999),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            clock(Duration(milliseconds: t.durationMs)),
            style: TextStyle(color: dim, fontSize: 13),
          ),
        ],
      ),
    );
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
