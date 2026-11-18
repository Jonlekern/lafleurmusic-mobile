import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../library/models.dart';
import '../../player/player.dart';
import '../../sources/accounts.dart';
import '../../theme/colors.dart';
import '../cover_image.dart';
import '../coverflow_screen.dart';
import '../track_menu.dart';
import 'album_screen.dart';
import 'names_screen.dart';
import 'phone_shell.dart';

/// Accueil du téléphone = la barre de côté du Mac (maquette 1, écran 1) : comptes, recherche, bibliothèque,
/// albums. L'album du morceau en cours est en rose.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.strings;
    void open(Widget screen) => pushPhone(context, screen);
    final searching = _query.trim().isNotEmpty;
    return PhoneScaffold(
      header: const PhoneHeader(
        // réglages et comptes : écrans de la tâche 9
        trailing: HeaderButton(icon: Icons.settings_rounded, size: 16),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        children: [
          const _AccountChips(),
          const SizedBox(height: 10),
          TextField(
            onChanged: (v) => setState(() => _query = v),
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              hintText: s.search,
              hintStyle: const TextStyle(
                color: Color(0xFF888888),
                fontSize: 14,
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
          if (searching)
            FutureBuilder<List<Track>>(
              key: ValueKey(_query),
              future: app.db.search(_query),
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
                  (_) => context.mounted ? openAlbum(context, a) : null,
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
                  tracks: app.db.watchAllTracks(),
                ),
              ),
            ),
            PhoneItem(
              label: s.artists,
              onTap: () => open(
                NamesScreen(
                  title: s.artists,
                  names: app.db.watchArtists(),
                  artists: true,
                ),
              ),
            ),
            PhoneItem(
              label: s.genres,
              onTap: () => open(
                NamesScreen(title: s.genres, names: app.db.watchGenres()),
              ),
            ),
            PhoneItem(
              label: s.top100,
              onTap: () => open(
                AlbumScreen(
                  back: s.home,
                  label: s.topLabel,
                  title: s.mostPlayed,
                  tracks: app.db
                      .watchTop(100)
                      .map((l) => [for (final (t, _) in l) t]),
                  empty: s.topEmpty,
                ),
              ),
            ),
            // morceaux gardés sur le téléphone : plan 2 (pour l'instant ne fait rien)
            PhoneItem(
              label: s.onDevice(defaultTargetPlatform == TargetPlatform.iOS),
            ),
            PhoneSection(s.playlists),
            StreamBuilder<List<Album>>(
              stream: app.db.watchAlbums(),
              builder: (context, albums) => StreamBuilder<PlayerState>(
                stream: app.player.state,
                initialData: app.player.current,
                builder: (context, st) {
                  final playing = st.data?.track?.album;
                  return Column(
                    children: [
                      for (final a in albums.data ?? const <Album>[])
                        PhoneItem(
                          leading: CoverImage(
                            trackPath: a.coverTrackPath,
                            size: 30,
                          ),
                          label: a.name.isEmpty ? s.unknownArtist : a.name,
                          selected: a.name == playing,
                          onTap: () => openAlbum(context, a.name),
                          onLongPress: () => showTrackSheet(
                            context,
                            title: a.name,
                            tracks: () => app.db.watchAlbumTracks(a.name).first,
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Puces des comptes : « Tout » (choisi), puis un par compte. Le tri par compte vient plus tard.
class _AccountChips extends StatelessWidget {
  const _AccountChips();

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
        return Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _Chip(app.strings.allAccounts, on: true),
            for (final a in list) _Chip(a.name),
          ],
        );
      },
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.label, {this.on = false});
  final String label;
  final bool on;

  @override
  Widget build(BuildContext context) {
    final fg = on ? LafleurColors.pink : LafleurColors.text;
    return Container(
      padding: EdgeInsets.fromLTRB(12, 6, on ? 8 : 12, 6),
      decoration: BoxDecoration(
        border: Border.all(
          color: on ? LafleurColors.pink : const Color(0xFF444444),
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
          if (on) Icon(Icons.arrow_drop_down_rounded, size: 16, color: fg),
        ],
      ),
    );
  }
}

/// Titre de section (BIBLIOTHÈQUE, ALBUMS).
class PhoneSection extends StatelessWidget {
  const PhoneSection(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
    child: Text(
      text,
      style: const TextStyle(
        color: Color(0xFF999999),
        fontSize: 11,
        letterSpacing: 1,
        fontWeight: FontWeight.w700,
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
    this.onTap,
    this.onLongPress,
  });
  final String label;
  final Widget? leading;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? LafleurColors.ink : LafleurColors.text;
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
            color: selected ? LafleurColors.pink : null,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 12)],
              Expanded(
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
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: selected ? LafleurColors.ink : const Color(0xFF666666),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
