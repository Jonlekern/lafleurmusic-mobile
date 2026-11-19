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
}) => Track(
  path: path,
  accountId: account,
  title: title,
  artist: 'x',
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

  test('another title, album or number gives another key', () {
    final base = mergeKey(t());
    expect(mergeKey(t(title: 'Other')), isNot(base));
    expect(mergeKey(t(album: 'Other')), isNot(base));
    expect(mergeKey(t(no: 2)), isNot(base));
    expect(mergeKey(t(no: null)), isNot(base));
  });

  test(
    'the key is album, title and number split by NUL, number may be empty',
    () {
      expect(mergeKey(t(no: 7)), 'album\u0000song\u00007');
      expect(mergeKey(t(no: null)), 'album\u0000song\u0000');
    },
  );

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
