import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/library/db.dart';
import 'package:lafleurmusic/library/merge.dart';
import 'package:lafleurmusic/library/models.dart';

Track t({
  String path = 'p',
  String title = 'Song',
  String album = 'Album',
  int? no = 1,
  String account = 'a',
  String artist = 'x',
  String albumArtist = '',
}) => Track(
  path: path,
  accountId: account,
  title: title,
  artist: artist,
  albumArtist: albumArtist,
  album: album,
  trackNo: no,
  durationMs: 1000,
  hasCover: false,
  size: 1,
);

void main() {
  test('same song on two accounts gets the same key', () {
    expect(
      mergeKey(t(path: 'subsonic://a/1', account: 'a')),
      mergeKey(t(path: 'subsonic://b/9', account: 'b')),
    );
  });

  test('accents, case and edge spaces do not matter', () {
    expect(
      mergeKey(t(title: 'Été  ', album: 'Café Del Mar')),
      mergeKey(t(title: 'ete', album: 'cafe del mar')),
    );
  });

  test('Beyoncé and Beyonce, The  Album and the album: merged', () {
    expect(
      mergeKey(t(albumArtist: 'Beyoncé', album: 'The  Album')),
      mergeKey(t(albumArtist: 'Beyonce', album: 'the album')),
    );
    expect(mergeKey(t(title: ' Un   deux ')), mergeKey(t(title: 'un deux')));
  });

  test('same album name by two artists is not merged', () {
    expect(
      mergeKey(t(albumArtist: 'Alice')),
      isNot(mergeKey(t(albumArtist: 'Bob'))),
    );
  });

  test('without album artist the track artist is used', () {
    expect(mergeKey(t(artist: 'Beyoncé')), mergeKey(t(albumArtist: 'beyonce')));
    expect(mergeKey(t(artist: 'Alice')), isNot(mergeKey(t(artist: 'Bob'))));
  });

  test('another title, album or number gives another key', () {
    final base = mergeKey(t());
    expect(mergeKey(t(title: 'Other')), isNot(base));
    expect(mergeKey(t(album: 'Other')), isNot(base));
    expect(mergeKey(t(no: 2)), isNot(base));
    expect(mergeKey(t(no: null)), isNot(base));
  });

  test('the key is artist, album, title and number split by NUL, number may be empty', () {
    expect(mergeKey(t(no: 7)), 'x\u0000album\u0000song\u00007');
    expect(mergeKey(t(no: null)), 'x\u0000album\u0000song\u0000');
  });

  test('fields cannot slide into each other', () {
    expect(
      mergeKey(t(album: 'ab', title: 'c')),
      isNot(mergeKey(t(album: 'a', title: 'bc'))),
    );
  });

  test('upsertTracks fills the merge key column', () async {
    final db = LibraryDb(NativeDatabase.memory());
    addTearDown(db.close);
    final a = t(path: 'subsonic://a/1', account: 'a', title: 'Été');
    await db.upsertTracks([a]);
    final row = await db.select(db.tracks).getSingle();
    expect(row.mergeKey, mergeKey(a));
    // an upsert on the same path refreshes it
    await db.upsertTracks([t(path: 'subsonic://a/1', title: 'Autre')]);
    expect(
      (await db.select(db.tracks).getSingle()).mergeKey,
      mergeKey(t(title: 'Autre')),
    );
  });
}
