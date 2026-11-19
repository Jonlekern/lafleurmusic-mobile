import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/library/db.dart';
import 'package:lafleurmusic/library/merge.dart';
import 'package:lafleurmusic/library/models.dart';

Track t(
  String path, {
  String title = 'x',
  String artist = 'a',
  String album = 'A',
  int? no,
  String genre = '',
}) => Track(
  path: path,
  folderId: 1,
  title: title,
  artist: artist,
  album: album,
  genre: genre,
  trackNo: no,
  durationMs: 1000,
  hasCover: true,
  mtime: 1,
  size: 1,
);

/// [Album.key] of a local album (no album artist) named [name].
String albumKey(String name) => albumMergeKey(
  Track(
    path: '',
    title: '',
    artist: '',
    album: name,
    durationMs: 0,
    hasCover: false,
    size: 0,
  ),
);

void main() {
  late LibraryDb db;
  setUp(() => db = LibraryDb(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('albums triés sans tenir compte des accents ni de la casse', () async {
    await db.upsertTrack(t('/m/1.flac', album: 'Funk'));
    await db.upsertTrack(t('/m/2.flac', album: 'Été'));
    await db.upsertTrack(t('/m/3.flac', album: 'dub'));
    await db.upsertTrack(t('/m/4.flac', album: 'Funk'));
    final albums = await db.watchAlbums().first;
    expect(albums.map((a) => a.name), ['dub', 'Été', 'Funk']);
    expect(albums.last.trackCount, 2);
    expect(albums.last.durationMs, 2000);
  });

  test('morceaux d’un album par numéro, sans numéro à la fin', () async {
    await db.upsertTrack(t('/m/b.flac', title: 'B', no: 2));
    await db.upsertTrack(t('/m/z.flac', title: 'Z'));
    await db.upsertTrack(t('/m/a.flac', title: 'A', no: 1));
    final tracks = await db.watchAlbumTracks(albumKey('A')).first;
    expect(tracks.map((x) => x.title), ['A', 'B', 'Z']);
  });

  test('upsert remplace le même chemin', () async {
    await db.upsertTrack(t('/m/a.flac', title: 'old'));
    await db.upsertTrack(t('/m/a.flac', title: 'new'));
    final tracks = await db.watchAlbumTracks(albumKey('A')).first;
    expect(tracks.single.title, 'new');
  });

  test('recherche dans titre, artiste et album', () async {
    await db.upsertTrack(t('/m/1.flac', title: 'Lafleur Surf'));
    await db.upsertTrack(t('/m/2.flac', artist: 'Surfers'));
    await db.upsertTrack(t('/m/3.flac', album: 'Surf Tape'));
    await db.upsertTrack(t('/m/4.flac', title: 'Autre'));
    expect((await db.search('surf')).length, 3);
  });

  test('dossier absent : pistes gardées et marquées', () async {
    await db.upsertTrack(t('/nas/1.flac'));
    await db.markMissing(1, true);
    final tracks = await db.watchAlbumTracks(albumKey('A')).first;
    expect(tracks.single.missing, true);
  });

  test(
    'artistes et genres triés sans accents, avec le nombre de morceaux',
    () async {
      await db.upsertTrack(t('/m/1.flac', artist: 'Zoé', genre: 'Rock'));
      await db.upsertTrack(t('/m/2.flac', artist: 'Émile', genre: 'Électro'));
      await db.upsertTrack(t('/m/3.flac', artist: 'Zoé', genre: 'Rock'));
      expect(await db.watchArtists().first, [('Émile', 1), ('Zoé', 2)]);
      expect(await db.watchGenres().first, [('Électro', 1), ('Rock', 2)]);
      expect((await db.watchArtistTracks('Zoé').first).length, 2);
      expect(
        (await db.watchGenreTracks('Électro').first).single.artist,
        'Émile',
      );
    },
  );
}
