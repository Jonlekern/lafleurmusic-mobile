import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../library/models.dart';
import '../settings.dart';
import '../theme/colors.dart';
import 'cover_image.dart';
import 'keep_actions.dart' show onIphone;
import 'phone/accounts_screen.dart';
import 'phone/on_device_screen.dart';
import 'phone/phone_shell.dart' show pushPhone;
import 'phone/playlist_screen.dart';
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
    this.tablet = false,
  });
  final bool tablet; // tablette : Comptes, Sur mon iPad, playlists du serveur, appui long = Garder / Retirer
  final LibraryView view;
  final String? album; // [Album.key] de l'album choisi
  final void Function(Album album) onAlbum;
  final void Function(LibraryView view) onView;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.strings;
    return Container(
      width: 240,
      decoration: BoxDecoration(
        color: context.colors.panel,
        border: Border(right: BorderSide(color: context.colors.line)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 18, 12, 12),
      child: StreamBuilder<List<Album>>(
        stream: app.library.albums(),
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
              if (tablet) ...[
                // les copies gardées (sans téléchargeur : rien à montrer) et les comptes
                _Item(
                  icon: Icons.download_done_rounded,
                  label: s.onDevice(onIphone, tablet: true),
                  onTap: app.downloader == null
                      ? null
                      : () => pushPhone(context, const OnDeviceScreen()),
                ),
                _Item(
                  icon: Icons.manage_accounts_rounded,
                  label: s.accountsBack,
                  onTap: () => pushPhone(context, const AccountsScreen()),
                ),
              ],
              _Head(s.playlists),
              for (final a in albums)
                GestureDetector(
                  // clic droit : Lire ensuite / Ajouter à la file pour tout l'album
                  onSecondaryTapUp: (d) => showTracksMenu(
                    context,
                    d.globalPosition,
                    () => app.library.albumTracks(a.key).first,
                  ),
                  child: _Item(
                    leading: CoverImage(trackPath: a.coverTrackPath, size: 26),
                    label: a.name.isEmpty ? s.unknownArtist : a.name,
                    selected: view == LibraryView.album && a.key == album,
                    onTap: () => onAlbum(a),
                    // tablette : appui long → Lire ensuite / Ajouter / Garder / Retirer
                    onLongPress: tablet && app.downloader != null
                        ? () => showTrackSheet(
                            context,
                            title: a.name,
                            album: true,
                            tracks: () => app.library.albumTracks(a.key).first,
                          )
                        : null,
                  ),
                ),
              if (tablet) const _ServerPlaylists(),
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
      style: TextStyle(
        color: context.colors.sub,
        fontSize: 11,
        letterSpacing: 0.9,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _Item extends StatelessWidget {
  const _Item({
    super.key,
    this.icon,
    this.leading,
    required this.label,
    this.selected = false,
    this.onTap,
    this.onLongPress,
    this.tag,
  });
  final String? tag; // le compte, en petit
  final VoidCallback? onLongPress;
  final IconData? icon;
  final Widget? leading;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

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
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? context.colors.pink : null,
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
              if (tag != null) ...[
                const SizedBox(width: 6),
                Text(
                  tag!,
                  style: TextStyle(
                    color: selected ? context.colors.ink : context.colors.sub,
                    fontSize: 11,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// « PLAYLISTS DU SERVEUR » (« PLAYLISTS » avec celles du téléphone, plan 9) sous les albums
/// de la tablette (comme l'Accueil du téléphone) : mosaïque et nom, le compte en petit en
/// mode Tout / Perso. Rien quand aucun compte n'en a.
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
            _Head(
              lists.any((p) => p.onPhone)
                  ? app.strings.allPlaylists
                  : app.strings.serverPlaylists,
            ),
            for (final p in lists)
              _Item(
                key: ValueKey('playlist-${p.accountId}-${p.id}'),
                leading: PlaylistCover(
                  ref: p.ref,
                  tracks: p.covers,
                  size: 26,
                  radius: 4,
                  stamp: p,
                ),
                label: p.name,
                tag: tagged ? playlistPlace(app.strings, p) : null,
                onTap: () => openPlaylist(context, p),
                onLongPress: app.downloader == null
                    ? null
                    : () => showPlaylistSheet(context, p),
              ),
          ],
        );
      },
    );
  }
}
