import 'dart:async';

import 'package:flutter/foundation.dart' show ValueNotifier, setEquals;

import '../settings.dart';
import 'db.dart';
import 'models.dart';

/// The library as the screens show it: the accounts of the display mode (one, all, or the
/// ones checked) plus the files on the phone, the same song on several accounts once
/// (see [LibraryDb.watchAllTracks]). A screen never knows which account a row comes from.
/// Lists follow the accounts (added, removed, reordered) and [settingsChanged].
class LibraryView {
  /// Without [settings]: every account, merged (tests, the Mac).
  LibraryView(this.db, {this.settings}) {
    if (settings != null) {
      _sub = db.watchAccountIds().listen((ids) {
        _order = ids;
        _emit();
      });
    }
  }

  /// The view used when the app gives none: every account, one per database.
  static LibraryView of(LibraryDb db) => _plain[db] ??= LibraryView(db);
  static final _plain = Expando<LibraryView>();

  final LibraryDb db;
  final AppSettings? settings;
  StreamSubscription<List<String>>? _sub;
  List<String> _order = const [];
  Set<String>? _last;
  final _visible = StreamController<Set<String>>.broadcast();

  /// The accounts shown, given the accounts in the order of the accounts screen.
  /// One: the chosen one (the first if none or gone). Custom: the checked ones.
  static Set<String> visibleOf(List<String> order, AppSettings s) =>
      switch (s.displayMode) {
        DisplayMode.all => {...order},
        DisplayMode.one =>
          order.contains(s.oneAccount)
              ? {s.oneAccount!}
              : {if (order.isNotEmpty) order.first},
        DisplayMode.custom => {
          for (final id in order)
            if (s.customAccounts.contains(id)) id,
        },
      };

  /// The accounts shown now (without settings: none is filtered, this stays empty).
  Set<String> get visibleAccounts {
    final s = settings;
    return s == null ? const {} : visibleOf(_order, s);
  }

  /// Counts the display changes: widgets showing the mode (chips, settings) listen to it.
  final revision = ValueNotifier<int>(0);

  /// The display mode or its accounts changed: every list shown follows.
  void settingsChanged() {
    revision.value++;
    _emit();
  }

  void _emit() {
    if (_sub == null) return;
    final v = visibleAccounts;
    final last = _last;
    if (last != null && setEquals(last, v)) return;
    _last = v;
    _visible.add(v);
  }

  /// [query] for the accounts shown, run again whenever they change.
  Stream<T> _follow<T>(Stream<T> Function(Set<String>? accounts) query) {
    if (settings == null) return query(null);
    StreamSubscription<T>? inner;
    StreamSubscription<Set<String>>? outer;
    late final StreamController<T> out;
    void use(Set<String> v) {
      inner?.cancel();
      inner = query(v).listen(out.add, onError: out.addError);
    }

    out = StreamController<T>(
      onListen: () {
        outer = _visible.stream.listen(use);
        final last = _last;
        if (last != null) use(last);
      },
      onCancel: () async {
        await inner?.cancel();
        await outer?.cancel();
      },
    );
    return out.stream;
  }

  Future<Set<String>?> _now() async {
    if (settings == null) return null;
    return _last ?? await _visible.stream.first;
  }

  Stream<List<Album>> albums({AlbumSort sort = AlbumSort.name}) =>
      _follow((a) => db.watchAlbums(accounts: a, sort: sort));

  /// The albums last played (at most [limit], the newest first), one per merged album.
  Stream<List<Album>> recentAlbums({int limit = 10}) =>
      _follow((a) => db.watchRecentAlbums(limit, accounts: a));

  /// The songs of album [key] ([Album.key]).
  Stream<List<Track>> albumTracks(String key) =>
      _follow((a) => db.watchAlbumTracks(key, accounts: a));

  /// [Album.key] of the albums kept whole on the phone.
  Stream<Set<String>> keptAlbums() =>
      _follow((a) => db.watchKeptAlbums(accounts: a));

  Stream<List<Track>> allTracks() =>
      _follow((a) => db.watchAllTracks(accounts: a));

  Future<List<Track>> search(String q) async =>
      db.search(q, accounts: await _now());

  /// The server playlists of the accounts shown (never merged across accounts), then the
  /// phone's (plan 9), shown whatever the accounts: [LibraryDb.watchPlaylists].
  Stream<List<ServerPlaylist>> playlists() =>
      _follow((a) => db.watchPlaylists(accounts: a));

  Stream<List<(String, int)>> artists() =>
      _follow((a) => db.watchArtists(accounts: a));

  Stream<List<(String, int)>> genres() =>
      _follow((a) => db.watchGenres(accounts: a));

  Stream<List<Track>> artistTracks(String artist) =>
      _follow((a) => db.watchArtistTracks(artist, accounts: a));

  Stream<List<Track>> genreTracks(String genre) =>
      _follow((a) => db.watchGenreTracks(genre, accounts: a));

  /// The Top 100 of the accounts shown: one rank per song, the listens of its twins added
  /// up (see [LibraryDb.watchTop]).
  Stream<List<(Track, int)>> top(int limit) =>
      _follow((a) => db.watchTop(limit, accounts: a));

  Future<void> dispose() async {
    await _sub?.cancel();
    await _visible.close();
    revision.dispose();
  }
}
