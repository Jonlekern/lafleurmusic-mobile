import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../library/models.dart';
import '../player/player.dart';
import '../theme/colors.dart';
import '../theme/widgets.dart';
import 'cover_image.dart';
import 'cover_mosaic.dart';
import 'track_menu.dart';
import 'format.dart';

/// En-tête de playlist + liste des morceaux (maquette 2). Un clic = jouer à partir de ce morceau.
class TrackList extends StatelessWidget {
  const TrackList({
    super.key,
    required this.title,
    required this.tracks,
    this.showHeader = true,
    this.onPlay,
    this.isAlbum = false,
    this.label,
    this.headerImage,
    this.albumColumn = false,
  });
  final Widget? headerImage; // à la place de la pochette (photo d'artiste)
  final bool albumColumn; // page d'artiste : colonne ALBUM au lieu d'ARTISTE
  final String? label; // au-dessus du titre ; null = ALBUM
  final bool
  isAlbum; // vue d'un album : sa pochette en en-tête (sinon une mosaïque)
  final String title;
  final VoidCallback? onPlay; // ex. rendre le clavier au lecteur après un clic
  final List<Track> tracks;
  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.strings;
    final minutes = tracks.fold<int>(0, (m, t) => m + t.durationMs) ~/ 60000;
    return Padding(
      padding: const EdgeInsets.fromLTRB(30, 26, 30, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showHeader)
            Padding(
              padding: const EdgeInsets.only(bottom: 26),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black,
                          blurRadius: 40,
                          offset: Offset(0, 12),
                        ),
                      ],
                      shape: headerImage != null
                          ? BoxShape.circle
                          : BoxShape.rectangle,
                      borderRadius: headerImage != null
                          ? null
                          : BorderRadius.circular(6),
                    ),
                    child: headerImage != null
                        ? headerImage!
                        : isAlbum
                        ? CoverImage(
                            trackPath: tracks.isEmpty
                                ? null
                                : tracks.first.path,
                            size: 190,
                            radius: 6,
                          )
                        : CoverMosaic(tracks: tracks, size: 190),
                  ),
                  const SizedBox(width: 26),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label ?? s.playlistLabel,
                          style: const TextStyle(
                            color: LafleurColors.sub,
                            fontSize: 12,
                            letterSpacing: 1,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 44,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${s.nSongs(tracks.length)} · ${s.minutes(minutes)}',
                          style: const TextStyle(
                            color: LafleurColors.sub,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            PillButton(
                              label: s.play,
                              icon: Icons.play_arrow_rounded,
                              primary: true,
                              onPressed: tracks.isEmpty
                                  ? null
                                  : () => app.player.playTracks(tracks, 0),
                            ),
                            const SizedBox(width: 12),
                            PillButton(
                              label: s.shuffle,
                              icon: Icons.shuffle_rounded,
                              onPressed: tracks.isEmpty
                                  ? null
                                  : () => app.player.playTracks(
                                      tracks,
                                      0,
                                      shuffle: true,
                                    ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          _Row(
            no: '#',
            title: s.title,
            artist: albumColumn ? s.albumHeader : s.artist,
            time: s.duration,
            head: true,
          ),
          Expanded(
            child: StreamBuilder<PlayerState>(
              stream: app.player.state,
              initialData: app.player.current,
              builder: (context, snap) {
                final playing = snap.data?.track?.path;
                return ListView.builder(
                  itemCount: tracks.length,
                  itemBuilder: (_, i) {
                    final t = tracks[i];
                    final row = _Row(
                      key: ValueKey(t.path),
                      no: '${t.trackNo ?? i + 1}',
                      title: t.title,
                      artist: albumColumn
                          ? t.album
                          : (t.artist.isEmpty ? s.unknownArtist : t.artist),
                      time: clock(Duration(milliseconds: t.durationMs)),
                      selected: t.path == playing,
                      missing: t.missing,
                      onTap: t.missing
                          ? null
                          : () {
                              onPlay?.call();
                              app.player.playTracks(tracks, i);
                            },
                    );
                    return TrackMenuArea(track: t, child: row);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    super.key,
    required this.no,
    required this.title,
    required this.artist,
    required this.time,
    this.head = false,
    this.selected = false,
    this.missing = false,
    this.onTap,
  });
  final String no, title, artist, time;
  final bool head, selected, missing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected
        ? LafleurColors.ink
        : (head ? LafleurColors.sub : const Color(0xFFDDDDDD));
    TextStyle st(bool bold) => TextStyle(
      color: fg,
      fontSize: head ? 12 : 14,
      letterSpacing: head ? 0.7 : 0,
      fontWeight: bold || head ? FontWeight.w700 : FontWeight.w400,
    );
    Widget cell(String text, TextStyle style) =>
        Text(text, overflow: TextOverflow.ellipsis, style: style);
    return Opacity(
      opacity: missing ? 0.35 : 1,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: selected ? LafleurColors.pink : null,
            borderRadius: head ? null : BorderRadius.circular(8),
            border: head
                ? const Border(bottom: BorderSide(color: LafleurColors.line))
                : null,
          ),
          child: Row(
            children: [
              SizedBox(
                width: 40,
                child: Text(
                  no,
                  style: st(false).copyWith(color: fg.withValues(alpha: 0.75)),
                ),
              ),
              Expanded(child: cell(title, st(true))),
              const SizedBox(width: 12),
              SizedBox(width: 260, child: cell(artist, st(false))),
              SizedBox(
                width: 70,
                child: Text(
                  time,
                  style: st(false).copyWith(color: fg.withValues(alpha: 0.75)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
