import 'package:flutter/material.dart';

import '../app_scope.dart';
import 'track_menu.dart';
import '../theme/colors.dart';
import 'artist_avatar.dart';

/// Vue Artistes (maquettes 6a et 6c) : grille de photos rondes ou liste, au choix (retenu).
class ArtistBrowser extends StatelessWidget {
  const ArtistBrowser({super.key, required this.names, required this.onPick});
  final Stream<List<(String, int)>> names;
  final void Function(String name) onPick;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.strings;
    final grid = app.artistGrid ?? ValueNotifier(true);
    return ValueListenableBuilder<bool>(
      valueListenable: grid,
      builder: (context, isGrid, _) => Padding(
        padding: const EdgeInsets.fromLTRB(30, 26, 30, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    s.artists,
                    style: const TextStyle(
                      fontSize: 44,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                _Toggle(
                  left: s.gridView,
                  right: s.listView,
                  leftOn: isGrid,
                  onChanged: (g) => grid.value = g,
                ),
              ],
            ),
            const SizedBox(height: 22),
            Expanded(
              child: StreamBuilder<List<(String, int)>>(
                stream: names,
                builder: (_, snap) {
                  final list = snap.data ?? const <(String, int)>[];
                  return isGrid
                      ? GridView.builder(
                          key: const Key('artist-grid'),
                          gridDelegate:
                              const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 172,
                                mainAxisExtent: 228,
                                crossAxisSpacing: 18,
                              ),
                          itemCount: list.length,
                          itemBuilder: (_, i) => GestureDetector(
                            onSecondaryTapUp: (d) => showTracksMenu(
                              context,
                              d.globalPosition,
                              () => app.library.artistTracks(list[i].$1).first,
                            ),
                            child: _Cell(
                              name: list[i].$1,
                              count: s.nSongs(list[i].$2),
                              onTap: () => onPick(list[i].$1),
                            ),
                          ),
                        )
                      : ListView.builder(
                          key: const Key('artist-list'),
                          itemCount: list.length,
                          itemBuilder: (_, i) => GestureDetector(
                            onSecondaryTapUp: (d) => showTracksMenu(
                              context,
                              d.globalPosition,
                              () => app.library.artistTracks(list[i].$1).first,
                            ),
                            child: _Line(
                              name: list[i].$1,
                              count: s.nSongs(list[i].$2),
                              onTap: () => onPick(list[i].$1),
                            ),
                          ),
                        );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const _name = TextStyle(fontWeight: FontWeight.w700, fontSize: 15);
const _count = TextStyle(color: LafleurColors.sub, fontSize: 13);

class _Cell extends StatelessWidget {
  const _Cell({required this.name, required this.count, required this.onTap});
  final String name, count;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(10),
    onTap: onTap,
    child: Column(
      children: [
        const SizedBox(height: 4),
        ArtistAvatar(name: name, size: 150),
        const SizedBox(height: 12),
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: _name,
        ),
        const SizedBox(height: 4),
        Text(count, style: _count),
      ],
    ),
  );
}

class _Line extends StatelessWidget {
  const _Line({required this.name, required this.count, required this.onTap});
  final String name, count;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(8),
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          ArtistAvatar(name: name, size: 44),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _name,
            ),
          ),
          Text(count, style: _count.copyWith(fontSize: 14)),
        ],
      ),
    ),
  );
}

/// Bouton à deux choix (Grille / Liste), le choix en rose.
class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.left,
    required this.right,
    required this.leftOn,
    required this.onChanged,
  });
  final String left, right;
  final bool leftOn;
  final void Function(bool left) onChanged;

  Widget _part(String label, IconData icon, bool on, bool isLeft) => InkWell(
    onTap: () => onChanged(isLeft),
    child: Container(
      color: on ? LafleurColors.pink : null,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 15, color: on ? Colors.black : LafleurColors.text),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: on ? Colors.black : LafleurColors.text,
            ),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      border: Border.all(color: const Color(0xFF444444)),
      borderRadius: BorderRadius.circular(20),
    ),
    clipBehavior: Clip.antiAlias,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _part(left, Icons.grid_view_rounded, leftOn, true),
        _part(right, Icons.view_list_rounded, !leftOn, false),
      ],
    ),
  );
}
