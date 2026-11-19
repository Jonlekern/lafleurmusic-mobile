import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../library/models.dart';
import '../../settings.dart';
import '../cover_image.dart';
import '../track_menu.dart';
import 'album_screen.dart';
import 'home_screen.dart';
import 'phone_shell.dart';

/// Albums sur le téléphone (maquette 13, écran B) : « Écoutés récemment » (les 10 derniers
/// albums joués, caché s'il n'y en a aucun), puis les pochettes triées par Nom, Artiste,
/// Ajout récent ou Plus écouté. Le tri choisi est gardé dans les réglages.
class AlbumsScreen extends StatefulWidget {
  const AlbumsScreen({super.key});
  @override
  State<AlbumsScreen> createState() => _AlbumsScreenState();
}

class _AlbumsScreenState extends State<AlbumsScreen> {
  AlbumSort? _sort;
  Stream<List<Album>>? _albums;
  Stream<List<Album>>? _recent;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = AppScope.of(context);
    _recent ??= app.library.recentAlbums();
    _pick(app.settings?.albumSort ?? _sort ?? AlbumSort.name);
  }

  void _pick(AlbumSort sort) {
    if (_sort == sort && _albums != null) return;
    _sort = sort;
    _albums = AppScope.of(context).library.albums(sort: sort);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.strings;
    return PhoneScaffold(
      header: PhoneHeader(back: s.home),
      body: StreamBuilder<List<Album>>(
        stream: _recent,
        builder: (context, recent) => StreamBuilder<List<Album>>(
          stream: _albums,
          builder: (context, albums) {
            final list = albums.data ?? const <Album>[];
            // CustomScrollView: only the tiles on screen are built (thousands of albums)
            return CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  sliver: SliverList.list(
                    children: [
                      if (recent.data?.isNotEmpty ?? false) ...[
                        PhoneSection(s.recentlyPlayed),
                        SizedBox(
                          height: 84 + 4 + 20,
                          child: ListView.separated(
                            key: const Key('recent-albums'),
                            scrollDirection: Axis.horizontal,
                            itemCount: recent.data!.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(width: 10),
                            itemBuilder: (_, i) =>
                                _Tile(recent.data![i], size: 84),
                          ),
                        ),
                      ],
                      PhoneSection(s.playlists),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final v in AlbumSort.values)
                            PhoneChip(
                              s.albumSort(v),
                              key: Key('sort-${v.name}'),
                              on: v == _sort,
                              onTap: () {
                                setState(() => _pick(v));
                                app.settings?.albumSort = v;
                                app.saveSettings?.call();
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                    ],
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  sliver: SliverLayoutBuilder(
                    builder: (context, c) {
                      final size = (c.crossAxisExtent - 20) / 3;
                      return SliverGrid.builder(
                        key: const Key('album-grid'),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          mainAxisExtent:
                              size + 4 + 16, // cover, gap, one line of name
                        ),
                        itemCount: list.length,
                        itemBuilder: (_, i) => _Tile(list[i], size: size),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Une pochette et son nom ; toucher ouvre l'album (fusionné), appui long = la feuille du bas.
class _Tile extends StatelessWidget {
  const _Tile(this.album, {required this.size});
  final Album album;
  final double size;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final name = album.name.isEmpty ? app.strings.unknownArtist : album.name;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => openAlbum(context, album.name, album.key),
      onLongPress: () => showTrackSheet(
        context,
        title: name,
        album: true,
        tracks: () => app.library.albumTracks(album.key).first,
      ),
      child: SizedBox(
        width: size,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            CoverImage(trackPath: album.coverTrackPath, size: size, radius: 6),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
