import 'package:flutter/material.dart';

import '../../app_scope.dart';
import 'album_screen.dart';
import 'home_screen.dart';
import 'phone_shell.dart';

/// Artistes ou Genres sur le téléphone : la liste des noms, toucher un nom ouvre ses morceaux.
class NamesScreen extends StatelessWidget {
  const NamesScreen({
    super.key,
    required this.title,
    required this.names,
    this.artists = false,
  });
  final String title;
  final Stream<List<(String, int)>> names; // nom, nombre de morceaux
  final bool artists;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.strings;
    return PhoneScaffold(
      header: PhoneHeader(back: s.home),
      body: StreamBuilder<List<(String, int)>>(
        stream: names,
        builder: (context, snap) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
          children: [
            PhoneSection(title.toUpperCase()),
            for (final (name, _) in snap.data ?? const <(String, int)>[])
              PhoneItem(
                label: name.isEmpty ? s.unknownArtist : name,
                onTap: () => pushPhone(
                  context,
                  AlbumScreen(
                    back: title,
                    label: artists ? s.artistHeader : s.genreLabel,
                    title: name.isEmpty ? s.unknownArtist : name,
                    artist: artists ? name : null,
                    tracks: artists
                        ? app.library.artistTracks(name)
                        : app.library.genreTracks(name),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
