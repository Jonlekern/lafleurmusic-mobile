import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../app_scope.dart';
import '../library/merge.dart';
import '../library/models.dart';
import '../theme/colors.dart';
import '../theme/widgets.dart';
import 'now_panel.dart';
import 'player_bar.dart';
import 'artist_avatar.dart';
import 'artist_browser.dart';
import 'name_list.dart';
import 'sidebar.dart';
import 'top_screen.dart';
import 'track_list.dart';

/// Vue en colonnes (maquette 2).
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  LibraryView _view = LibraryView.album;
  String? _album; // [Album.key] de l'album choisi
  String _albumName = '';
  String? _name; // artiste ou genre choisi
  String _query = '';
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  final _keys = FocusNode();
  StreamSubscription<String>? _skipped;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = AppScope.of(context);
    _skipped ??= app.player.skipped.listen((path) {
      if (!mounted) return;
      // morceau du serveur : son titre (le chemin n'est qu'une clé subsonic://)
      final title =
          app.player.queue?.order
              .where((t) => t.path == path)
              .firstOrNull
              ?.title ??
          p.basename(path);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: LafleurColors.bar,
          content: Text(
            app.strings.unreadableSkipped(title),
            style: const TextStyle(color: LafleurColors.text),
          ),
        ),
      );
    });
  }

  @override
  void dispose() {
    _skipped?.cancel();
    _search.dispose();
    _searchFocus.dispose();
    _keys.dispose();
    super.dispose();
  }

  // un champ de texte a le clavier (recherche, titre, nom de playlist) : les touches lui reviennent
  bool get _typing =>
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<EditableText>() !=
      null;

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent || _typing) {
      return KeyEventResult.ignored;
    }
    final player = AppScope.of(context).player;
    final cmd =
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed;
    if (cmd && e.logicalKey == LogicalKeyboardKey.keyF) {
      _searchFocus.requestFocus();
    } else if (e.logicalKey == LogicalKeyboardKey.space) {
      player.toggle();
    } else if (e.logicalKey == LogicalKeyboardKey.arrowRight) {
      player.next();
    } else if (e.logicalKey == LogicalKeyboardKey.arrowLeft) {
      player.previous();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  Stream<List<Track>> _tracks(AppScope app) {
    if (_query.trim().isNotEmpty) {
      return Stream.fromFuture(app.library.search(_query));
    }
    return switch (_view) {
      LibraryView.songs => app.library.allTracks(),
      LibraryView.album =>
        _album == null ? const Stream.empty() : _albumTracks(app, _album!),
      LibraryView.artists => app.library.artistTracks(_name ?? ''),
      LibraryView.genres => app.library.genreTracks(_name ?? ''),
      LibraryView.top => const Stream.empty(), // TopScreen lit le Top lui-même
    };
  }

  // morceaux affichés : si la playlist se vide parce qu'ils ont changé d'album (renommer, Réparer, annuler),
  // la vue les suit sous leur nouveau nom
  List<String> _shown = const [];

  Stream<List<Track>> _albumTracks(AppScope app, String album) async* {
    await for (final list in app.library.albumTracks(album)) {
      if (list.isEmpty && _shown.isNotEmpty) {
        final moved = await app.db.trackByPath(_shown.first);
        if (moved != null && albumMergeKey(moved) != album) {
          if (mounted) {
            setState(() {
              _album = albumMergeKey(moved);
              _albumName = moved.album;
            });
          }
          return;
        }
      }
      _shown = [for (final t in list) t.path];
      yield list;
    }
  }

  bool get _artistPage => _view == LibraryView.artists && _name != null;

  String _label(AppScope app) {
    final s = app.strings;
    if (_query.trim().isNotEmpty) return s.searchLabel;
    return switch (_view) {
      LibraryView.songs => s.library,
      LibraryView.album => s.playlistLabel,
      LibraryView.artists => s.artistHeader,
      LibraryView.genres => s.genreLabel,
      LibraryView.top => s.topLabel,
    };
  }

  String _title(AppScope app) {
    final s = app.strings;
    if (_query.trim().isNotEmpty) return '« ${_query.trim()} »';
    return switch (_view) {
      LibraryView.songs => s.songs,
      LibraryView.album => _albumName.isEmpty ? s.unknownArtist : _albumName,
      LibraryView.artists || LibraryView.genres => _name ?? '',
      LibraryView.top => s.mostPlayed,
    };
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.strings;
    return Focus(
      focusNode: _keys,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        body: Column(
          children: [
            TitleBar(
              trailing: SizedBox(
                width: 260,
                height: 30,
                child: TextField(
                  key: const Key('search'),
                  controller: _search,
                  focusNode: _searchFocus,
                  style: const TextStyle(fontSize: 13),
                  onChanged: (v) => setState(() => _query = v),
                  onSubmitted: (_) => _keys.requestFocus(),
                  decoration: InputDecoration(
                    hintText: s.search,
                    hintStyle: const TextStyle(
                      color: LafleurColors.sub,
                      fontSize: 13,
                    ),
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      size: 16,
                      color: LafleurColors.sub,
                    ),
                    isDense: true,
                    filled: true,
                    fillColor: const Color(0xFF0F0F0F),
                    contentPadding: EdgeInsets.zero,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: LafleurColors.line),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: LafleurColors.line),
                    ),
                  ),
                ),
              ),
            ),
            StreamBuilder<bool>(
              stream: app.db.watchAnyMissing(),
              builder: (_, snap) => snap.data == true
                  ? Container(
                      width: double.infinity,
                      color: const Color(0xFF2A1A2A),
                      padding: const EdgeInsets.symmetric(
                        vertical: 8,
                        horizontal: 18,
                      ),
                      child: Text(
                        s.nasMissing,
                        style: const TextStyle(
                          color: LafleurColors.pink,
                          fontSize: 13,
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            Expanded(
              child: Row(
                children: [
                  StreamBuilder<List<Album>>(
                    stream: app.library.albums(),
                    builder: (_, snap) {
                      final albums = snap.data ?? const <Album>[];
                      if (_album == null && albums.isNotEmpty) {
                        WidgetsBinding.instance.addPostFrameCallback(
                          (_) => mounted
                              ? setState(() {
                                  _album = albums.first.key;
                                  _albumName = albums.first.name;
                                })
                              : null,
                        );
                      }
                      return Sidebar(
                        view: _view,
                        album: _album,
                        onAlbum: (a) => setState(() {
                          _name = null;
                          _keys.requestFocus();
                          _view = LibraryView.album;
                          _album = a.key;
                          _albumName = a.name;
                          _shown = const [];
                          _query = '';
                          _search.clear();
                        }),
                        onView: (v) => setState(() {
                          _name = null;
                          _keys.requestFocus();
                          _view = v;
                          _query = '';
                          _search.clear();
                        }),
                      );
                    },
                  ),
                  Expanded(
                    child: _view == LibraryView.top && _query.trim().isEmpty
                        ? TopScreen(onPlay: _keys.requestFocus)
                        : (_view == LibraryView.artists ||
                                  _view == LibraryView.genres) &&
                              _name == null &&
                              _query.trim().isEmpty
                        ? (_view == LibraryView.artists
                              ? ArtistBrowser(
                                  names: app.library.artists(),
                                  onPick: (n) => setState(() => _name = n),
                                )
                              : NameList(
                                  names: app.library.genres(),
                                  title: s.genres,
                                  onPick: (n) => setState(() => _name = n),
                                ))
                        : StreamBuilder<List<Track>>(
                            key: ValueKey('$_view-$_album-$_name-$_query'),
                            stream: _tracks(app),
                            builder: (_, snap) => TrackList(
                              title: _title(app),
                              label: _label(app),
                              headerImage: _artistPage
                                  ? ArtistAvatar(name: _name!, size: 190)
                                  : null,
                              albumColumn: _artistPage,
                              tracks: snap.data ?? const [],
                              onPlay: _keys.requestFocus,
                              isAlbum:
                                  _view == LibraryView.album &&
                                  _query.trim().isEmpty,
                            ),
                          ),
                  ),
                  const NowPanel(),
                ],
              ),
            ),
            const PlayerBar(),
          ],
        ),
      ),
    );
  }
}
