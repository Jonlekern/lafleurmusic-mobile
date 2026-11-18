import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../library/models.dart';
import '../theme/colors.dart';
import 'cover_image.dart';
import 'track_menu.dart';
import 'coverflow_screen.dart';

enum LibraryView { album, songs, artists, genres, top }

/// Barre latérale (maquette 2) : bibliothèque, playlists (= albums), outils.
class Sidebar extends StatelessWidget {
  const Sidebar({
    super.key,
    required this.view,
    required this.album,
    required this.onAlbum,
    required this.onView,
  });
  final LibraryView view;
  final String? album;
  final void Function(String album) onAlbum;
  final void Function(LibraryView view) onView;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.strings;
    return Container(
      width: 240,
      decoration: const BoxDecoration(
        color: LafleurColors.panel,
        border: Border(right: BorderSide(color: LafleurColors.line)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 18, 12, 12),
      child: StreamBuilder<List<Album>>(
        stream: app.db.watchAlbums(),
        builder: (context, snap) {
          final albums = snap.data ?? const <Album>[];
          return ListView(
            children: [
              _Head(s.library),
              _Item(
                icon: Icons.view_carousel_rounded,
                label: s.coverFlow,
                onTap: () => openCoverflow(context, onOpen: onAlbum),
              ),
              _Item(
                icon: Icons.music_note_rounded,
                label: s.songs,
                selected: view == LibraryView.songs,
                onTap: () => onView(LibraryView.songs),
              ),
              _Item(
                icon: Icons.person_rounded,
                label: s.artists,
                selected: view == LibraryView.artists,
                onTap: () => onView(LibraryView.artists),
              ),
              _Item(
                icon: Icons.album_rounded,
                label: s.genres,
                selected: view == LibraryView.genres,
                onTap: () => onView(LibraryView.genres),
              ),
              _Item(
                icon: Icons.star_rounded,
                label: s.top100,
                selected: view == LibraryView.top,
                onTap: () => onView(LibraryView.top),
              ),
              _Head(s.playlists),
              for (final a in albums)
                GestureDetector(
                  // clic droit : Lire ensuite / Ajouter à la file pour tout l'album
                  onSecondaryTapUp: (d) => showTracksMenu(
                    context,
                    d.globalPosition,
                    () => app.db.watchAlbumTracks(a.name).first,
                  ),
                  child: _Item(
                    leading: CoverImage(trackPath: a.coverTrackPath, size: 26),
                    label: a.name.isEmpty ? s.unknownArtist : a.name,
                    selected: view == LibraryView.album && a.name == album,
                    onTap: () => onAlbum(a.name),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Head extends StatelessWidget {
  const _Head(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(10, 14, 10, 8),
    child: Text(
      text,
      style: const TextStyle(
        color: LafleurColors.sub,
        fontSize: 11,
        letterSpacing: 0.9,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _Item extends StatelessWidget {
  const _Item({
    this.icon,
    this.leading,
    required this.label,
    this.selected = false,
    this.onTap,
  });
  final IconData? icon;
  final Widget? leading;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? LafleurColors.ink : LafleurColors.text;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? LafleurColors.pink : null,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              if (leading != null)
                leading!
              else if (icon != null)
                Icon(icon, size: 16, color: fg),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: fg,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
