# Task 5 report: Playlists du serveur

Status: DONE_WITH_CONCERNS (concerns at the end)

## What

- **Source**: `SourcePlaylist{id, name, songIds}` and `MusicSource.playlists()` (`source.dart`). Subsonic: `getPlaylists`, then `getPlaylist` for each one; songs in server order with duplicates kept. Every request goes through `_call`, so the account headers go with it. `_CancellableSource` forwards the call.
- **Sync** (`sync.dart`): only after a complete album sync, `_storePlaylists` calls `playlists()` and `LibraryDb.replacePlaylists` swaps that account's `Playlists`/`PlaylistItems` in one transaction. Items are `subsonic://<acc>/<songId>`, so they keep their own account's paths. If the playlists can't be read, or the album sync is incomplete, the old playlists stay. A playlist failure does not make the sync incomplete.
- **DB** (`db.dart`): `replacePlaylists`, `playlistsOf`, `playlistPaths`, `playlistName`, `watchPlaylists({accounts})`, `watchPlaylistItems`, `doneCopies`, `anyKept`, `keptPlaylistRows`/`watchKeptPlaylists`/`addKeptPlaylist`/`setKeptPlaylist`/`dropKeptPlaylist`, and `deleteAccountPlaylists` (called from `Accounts.remove`).
  - `watchPlaylists` returns `ServerPlaylist` (`models.dart`). Order: accounts in the order of the Accounts screen, then the server's order. A removed account's playlists never show. `accounts` filters them (the display mode, through `LibraryView.playlists()`).
  - The ⬇ flag (`kept`) needs two things: the playlist is in `KeptPlaylists`, and every present song has a finished copy, its own or a twin's.
- **m3u8** (`lib/offline/m3u.dart`):
  - `buildM3u8` writes `#EXTM3U`, then `#EXTINF:<s>,<artist> - <title>` and the path for each song. Line breaks inside titles are flattened.
  - `PlaylistFiles.refresh()` (one at a time) goes through `KeptPlaylists`. For each one it lists, in playlist order and with duplicates repeated, the songs whose finished copy (own or twin) exists on disk. Paths are `../<filePath>`, relative to `<root>/Playlists/`.
  - The file is written atomically: first `Name.lafleur-part.m3u8` (the existing part-file convention, already swept at launch), then renamed. It is only rewritten when the content changed, and then announced (`device.announce`, i.e. MediaStore on Android).
  - Name: `safeName(name).m3u8`, made unique by `uniquePath` against files on disk, `.part` files and the other records (case-insensitive). The name is stored in `KeptPlaylists.fileName` and kept on later rewrites.
  - No finished copy yet: no file (an existing one of ours is removed and `fileName` reset to `''`), and the record stays.
  - No copy at all, finished or queued (own or twin): the file of ours and the record are removed.
  - A playlist the server no longer lists is left as it is.
  - Deletion only ever touches `<root>/Playlists/<recorded fileName>` with a `.m3u8` extension (Q3). The `Playlists` folder is removed only when empty.
  - `remove(acc,id)`, `leave(fromRoot)` (folder move) and `forgetFiles()` (old folder unreachable: its files are no longer ours, nothing is deleted).
- **Downloader** (`downloader.dart`):
  - `keepPlaylist(acc,id)` keeps the present songs once each (user reason), then records the playlist and refreshes.
  - `playlistSongsToForget` and `forgetPlaylist(acc,id)`: the file and record go first, then `forget(paths, byUser: true)`.
  - Refresh happens after each `markOfflineDone`, at the end of every `forget` (including Top 100 eviction), in `resumeAtLaunch`, and after `moveRoot` (`leave(from)` then refresh in the new folder). `adoptRoot` calls `forgetFiles`. Refresh errors never stop the queue.
- **UI**:
  - Home: a « PLAYLISTS DU SERVEUR » section under ALBUMS (hidden when empty). Each row has a 2×2 mosaic (`CoverMosaic`, 30 pt), the name, a pink ⬇ when kept, and the account name in small type in Tout/Perso mode. That small label is a new `tag` on `PhoneItem`. Tap opens the playlist; long-press opens the sheet.
  - `playlist_screen.dart` is the album screen layout with « PLAYLIST · <COMPTE> », « N morceaux · M min », Lecture / Aléatoire / ⬇, and rows numbered in playlist order with « artiste · album » under each title (new `sub` on `PhoneTrackRow`).
    - Duplicates get their own row, keyed by index.
    - A song that isn't playable shows « artiste · pas sur l'iPhone » greyed, as on the album screen.
    - A song absent from its account (no track row) is a greyed « Morceau absent / absent de <compte> » row: no time, no menu, no swipe (`menu: false`).
    - Lecture and a row tap play the present songs, duplicate included (the row tap starts at its index among them).
    - ⬇ calls `keepPlaylist`. The « … » sheet and the Home long-press use `showTrackSheet` with the new `kept`/`onKeep`/`onRemove` hooks: Garder keeps the whole playlist, Retirer asks the Task 2c dialog (counting `playlistSongsToForget`) and then calls `forgetPlaylist`.
  - `keepWith` was factored out of `keepTracks` (same messages).
- **Strings**: `serverPlaylists`, `playlistOf`, `artistAlbum`, `missingSong`, `notOnAccount`.
- **Demo / fixtures**: `seedPlaylistDemo` (Soirée with Ocean Drive twice, Night Swim not on the phone and one absent song; Running kept; Chill du dimanche on Jellyfin). `LAFLEUR_DEMO_SCREEN=playlists|playlist`. `pumpKeep(addAccount:)`. `DemoDownloader` records `keepPlaylist`/`forgetPlaylist`.

### « Retirer » rule chosen
Retirer on a playlist removes its m3u8 and forgets its songs (user removal: twins too, and they are blocked from the Top 100), **except songs, or twins of songs, that belong to another kept playlist**. Songs kept on their own or through an album keep are not tracked separately (Offline has only a reason), so they are removed like an album removal. This is the same behaviour as the Task 2c album dialog, and the dialog appears first.

## TDD evidence
- `subsonic_test.dart` playlists group: written first. `flutter test test/sources/subsonic_test.dart` failed to compile (« The method 'playlists' isn't defined for the type 'SubsonicSource' »), then `+48: All tests passed!` after the implementation.
- `sync_test.dart` server playlists group: written first. It failed at compile time (`playlistsOf` missing). The first green run after the implementation then failed 5 tests because records holding lists don't compare deeply; that was a test-side fix (lists instead of records). Final: `+25: All tests passed!`.
- `m3u_test.dart`: written before `m3u.dart`. I did not run it before the file existed, so I never saw it fail for the expected reason. After the implementation: `+12: All tests passed!`. It covers order, the duplicate twice, the absent song and the song without a copy left out, relative paths that resolve on disk, special characters (`:`/`/` → `_`, UTF-8, `#`, comma, newline), no temp file left, no rewrite when the content is the same, a twin's copy, queued-only, the last copy leaving, a name collision with a user file (that file is untouched), two playlists with the same name, a hand-placed .m3u8 untouched, folder unreachable, and `leave`.
- `downloader_test.dart` server playlists group: written after `keepPlaylist`/`forgetPlaylist`, so not test-first. Result: `+5`. It covers keep (each song once, the absent one skipped), per-song removal rewriting the file and the last one deleting it, Retirer protecting another kept playlist's songs, re-keep keeping the same file name, and moveRoot moving the m3u8.
- `test/ui/phone/playlist_screen_test.dart`: `+10`. Home section placement and order, tag in Tout and none in Un compte, ⬇ only on the kept playlist, long-press → Retirer → dialog → `forgetPlaylist`. Playlist screen (Review Focus 4): label, order, duplicate twice, absent greyed, Lecture plays 6 songs without the absent one, a tap on the 2nd « Ocean Drive » plays from index 5, the absent row does nothing, ⬇ → `keepPlaylist`, Android wording.

## Full suite
- `flutter analyze`: No issues found!
- `flutter test --exclude-tags golden`: `+731 ~3: All tests passed!` (no warnings or exceptions in the output).
- `flutter test --tags golden`: `+21: All tests passed!`. New goldens: `test/ui/goldens/phone-10.png` and `phone-11.png` (demo data), from `test/ui/playlist_golden_test.dart`. Existing goldens are unchanged.

## Simulator (demo mode, iPhone simulator)
- `shots/task-5-playlist.png`: screen 11, « Soirée ».
- `shots/task-5-home.png`: screen 10, Home scrolled to the playlists section (account names in small type, pink ⬇ on Running).

## Files
New: `lib/offline/m3u.dart`, `lib/ui/phone/playlist_screen.dart`, `test/offline/m3u_test.dart`, `test/ui/phone/playlist_screen_test.dart`, `test/ui/playlist_golden_test.dart`, `test/ui/goldens/phone-10.png`, `test/ui/goldens/phone-11.png`.
Modified: `lib/sources/source.dart`, `subsonic.dart`, `account_service.dart`, `accounts.dart`, `lib/library/sync.dart`, `db.dart`, `models.dart`, `library_view.dart`, `lib/offline/downloader.dart`, `lib/ui/phone/home_screen.dart`, `album_screen.dart`, `lib/ui/track_menu.dart`, `keep_actions.dart`, `lib/l10n/strings.dart`, `lib/demo/demo_app.dart`, `demo_offline.dart`, `test/sources/subsonic_test.dart`, `test/library/sync_test.dart`, `test/offline/downloader_test.dart`, `test/ui/keep_fixture.dart`.
No schema change: the Task 1 v4 tables are used as they are.

## Self-review
- Q3: the only deletion path for m3u8 files is `PlaylistFiles._delete`. It is called only with a `fileName` read from `KeptPlaylists`, it checks the path stays under `<root>/Playlists/` and ends in `.m3u8`, and it does nothing on an empty name. A user's file with the same name gets ` (2)` on our side and is never touched (tested). After `adoptRoot`, recorded names are cleared, so a file of the same name in the new folder is never seen as ours.
- Plan-2 rule: songs still leave only through `Downloader.forget`. `forgetPlaylist` goes through it with `byUser`, after the Task 2c confirmation in the UI.
- Display mode: the Home section goes through `LibraryView.playlists()`, so hidden accounts' playlists are hidden. The playlist screen and m3u8 use twins for copies and playability (`playableNow` and the resolver already do).
- Duplicate rows use index keys. Both « Ocean Drive » rows turn pink while that song plays (the player has no notion of « the row I came from »).

## Concerns
1. **Visual details not in the mockup** (Johnny may want to see them):
   - The text of the absent-song row (« Morceau absent » / « absent de <compte> »).
   - The Home playlist rows are never pink as « playing ». The mockup's pink Soirée row looks like a selection; we don't know which playlist the current song came from.
   - The account name in the label is upper-cased, as in the mockup (« PLAYLIST · NAVIDROME »).
2. **Retirer rule**: songs kept individually or through an album before the playlist keep are removed with it, unless they are in another kept playlist. This is album-like and goes through the confirmation dialog.
3. **After a sync changes a kept playlist** (songs added or removed on the server), the new songs are not kept automatically. The m3u8 is refreshed at the next copy event or at launch, not right after the sync, because sync doesn't know the downloader.
4. **Absent songs** have no title: the PlaylistItems schema stores only paths, so they show as « Morceau absent ».
5. The goldens' and demo's « 33 min » and « 13:40 » for Nightcall come from the demo durations, not from the mockup's 27 min.
6. A few files I touched were not dart-format clean before this task (`db.dart`, `sync.dart`, `account_service.dart`, `sync_test.dart`). I kept their old formatting outside my changes.

## Fix round 1 (review of 24c3b7e; rulings Q10–Q12; item 3a waits for Johnny, unchanged)

1. **Failed copies keep the playlist kept** (`db.anyKept`): any offline row, own or twin, in any state (failed included). A playlist's record is dropped only when no row remains. After `adoptRoot` (`failDoneCopies`) the record stays with no file; « Réessayer » (`keep` of the failed songs) brings the .m3u8 back in the new folder.
2. **Q10**: `PlaylistFiles.refresh` deletes our file and the record when the playlist no longer exists, either because a complete sync dropped it or because its account was removed (`deleteAccountPlaylists`). Its songs stay kept. The trigger is `Downloader.followPlaylists()`, which subscribes to drift `tableUpdates` on `playlists` and calls `syncPlaylists()` (serialized). It is wired in `main.dart`.
3. **Q11**: `forget(..., block: false)`. `forgetPlaylist` still removes twins (`byUser`) but adds no AutoKeepBlocks. `DemoDownloader.forget` gained the parameter.
4. **Q12**: `replacePlaylists` notes the songs a kept playlist gains (new song paths not in its old item list, kept playlists only, only when that playlist's songs were read). `syncPlaylists` takes them (`takeAddedToKept`), calls `keep` with reason user, then refreshes the m3u8. Songs the user had removed individually are not re-kept, because only additions count.
   - The sheet's kept state (`showPlaylistSheet`) is now recorded AND every present song kept. A recorded playlist with a song that isn't kept shows « Garder », which keeps the rest. The ⬇ pill already used both conditions.
   - Limitation: the « added » notes live in memory. If the app is killed between a sync and the handler, which runs right after, the next sync won't see those songs as new.
5. **Minor fixes**:
   - The part file is deleted if its write or rename fails.
   - The download loop marks the playlists dirty and refreshes once at the end of the run, not after every file.
   - `_storePlaylists` catches `Exception` only. Syncing test fakes that relied on `noSuchMethod` got a `playlists()` override (`_CountingSource`, `GatedSource`).
   - `SourcePlaylist.songIds` is nullable. When one `getPlaylist` fails with a SubsonicException, that playlist gets null and keeps its old songs while the others are replaced. A network error still keeps all the old ones.
   - Playlists and entries without an id are skipped (no more "null").

### Tests (all added in this round)
- downloader_test « server playlists »: failed copies after adoptRoot then retry → m3u8 in the new folder; Q10 sync removal (file and record gone, songs still done); Q10 account removal; Q11 no block and the Top 100 re-keeps; Q12 the gained song is kept (user), the one the user removed is not re-kept, and the m3u8 lists 2 and 4.
- sync_test: one unreadable playlist keeps its old songs; gained songs are noted once and only for kept playlists.
- subsonic_test: one failing `getPlaylist` gives null songs, the others read, id-less entries are skipped.
- playlist_screen_test: recorded playlist with a song not kept → the sheet shows « Garder sur mon iPhone », which calls `keepPlaylist`.
- Mutation check: putting back the old `anyKept` and `blockAutoKeep(byUser)` makes the failed-copies test and the Q11 test fail (`+8 -2`). The fixes then turn them green.

### Runs
- `flutter analyze`: No issues found!
- `flutter test --exclude-tags golden`: `+740 ~3: All tests passed!` (no warning or exception lines).
- `flutter test --tags golden`: `+21: All tests passed!`

## Fix round 2 (Johnny's 3a answer « 1 », ruling Q13, re-review minors)

### A. Keep origins (Q13)
- **Schema** (still v4): a new `KeepOrigins(trackPath, origin)` table, primary key on both, data class `KeepOriginRow`. It is created in `onCreate` (createAll) and in the `from < 4` step, which then runs `INSERT OR IGNORE … SELECT track_path, 'song' FROM offline WHERE reason = 'user'`, so 0.2.0 user copies count as kept for themselves. `db.g.dart` was regenerated. The v1/v2/v3→v4 migration tests pass; the v3 test now also checks the `song` origin.
- **DB**: `addOrigins`, `removeOrigin(origin, paths)` (works on the twin group), `clearOrigins(paths)`, `originsOf(path)` (the union over the group).
- **Downloader**:
  - `keep(..., origin: String Function(Track)?)` records an origin for user keeps only. A null origin records nothing (Top 100, « Réessayer »).
  - `KeepOrigin` gives `song`, `album:<albumKeyOf(t)>` and `playlist:<acc>/<id>`.
  - `toForgetFrom(origin, paths)` returns the paths with no other origin across the twin group. `forgetFrom(origin, paths, {block})` removes that origin, then forgets only those paths (`byUser`, twins included). `block` is true for albums and false for playlists (Q11).
  - `forget(byUser: true)` clears the origins of everything it removes, so removing a single song is unconditional.
  - `playlistSongsToForget` and `forgetPlaylist` now go through origins; this replaces the "other kept playlist" rule.
- **Who records which origin**:
  - Album: the album ⬇ pill (`isAlbum`), « Sélectionner » (screen 8), and the sheet when it holds an album (Home album long-press, album « … »; new `album:` flag on `showTrackSheet`).
  - Song: a single song's sheet, and the pills of the Songs, artist, genre and Top 100 lists.
  - Playlist: the playlist ⬇ and its sheet, plus songs a kept playlist gains.
- **Removals**:
  - Album via the sheet (`forgetAlbum`) or the « Sur mon iPhone » swipe/sheet (`_remove`): `forgetFrom(album origin)`. The confirmation dialog counts only `toForgetFrom`, i.e. what will really be deleted.
  - A single song via its sheet: `forgetTracks`, which is unconditional.
  - A playlist: `forgetFrom(playlist origin, block: false)`.
- `DemoDownloader` gained matching overrides (`origins`, `forgottenOrigins`; `forgetFrom` also records into `forgotten`, so the Task 2c tests are unchanged).

### B. Re-review minors
1. and 4. `syncPlaylists` is now a catch-up instead of the in-memory gained-songs note, which is removed (`takeAddedToKept` is gone). For each playlist still in KeptPlaylists, it keeps, with the playlist origin, every present song that has no offline row (own or twin, any state). It re-checks that the record still exists before keeping, so a Retirer in between wins. It runs on playlist-table changes (`followPlaylists`) and at launch (`resumeAtLaunch`), which covers gains seen by a sync just before the app was killed.
2. Songs blocked by `autoKeepBlockedFor` (removed one by one) are skipped.
3. The `anyKept` twin subquery excludes `account_id = 'local'`.

### Tests
- downloader_test « keep origins (Q13) »:
  - Album + playlist sharing songs 2 and 3: removing the playlist leaves 1, 2 and 3. Removing the album leaves 2, 3 and 4, blocks 1, and leaves the m3u8 at 3 lines.
  - Removing a single song removes it and clears its origins; a later playlist removal keeps 3 (album) and drops 4.
  - A twin's origin counts.
  - A Top 100 copy (no origin) goes with an album removal.
  - Launch catch-up keeps a gained song 5 with the playlist origin but not the blocked song 4.
  - A playlist that is not kept keeps nothing.
- db_migration_test: the v3 user copy gets origin `song`.
- playlist_screen_test: Home album long-press → Retirer → `forgetFrom` with an `album:` origin; the album ⬇ keeps with an `album:` origin.
- The round-1 tests still pass (Q10–Q12, failed copies).

### Runs
- `flutter analyze`: No issues found!
- `flutter test --exclude-tags golden`: `+748 ~3: All tests passed!` (0 warning or exception lines).
- `flutter test --tags golden`: `+21: All tests passed!`

### Notes
- An album removal blocks only the songs it really deletes. The songs that stay are not blocked, because they are still kept by something else.
- Origins attach to the row the user acted on. Lookups and removals use the twin group, so a change of representative row (account order) doesn't lose them.

## Fix round 3 (rulings Q14, Q15; N1–N6)

- **N1 / Q14 (« Sur mon iPhone » removes exactly what the row shows)**:
  - `_remove` again runs `confirmRemoval(k.paths)` (exact count, twins included) and then `forget(k.paths, byUser: true)`. That forget is unconditional, clears the origins and takes the twins too.
  - Kept and failed rows are now grouped by `albumKeyOf(t)` (albumMergeKey) instead of the album name, so two albums with the same name by different album artists are two rows.
- **N2 / Q15**: when Q10 drops a kept playlist, `db.renameOrigin('playlist:<acc>/<id>', 'song')` turns its origins into `song`. `KeepOrigin` moved to `lib/offline/keep_origin.dart` (re-exported by `downloader.dart`) so `m3u.dart` can use it.
- **N3**: when an album or playlist removal would delete nothing (`toForgetFrom` / `playlistSongsToForget` empty), there is no dialog. A SnackBar shows « Toujours gardé par un autre album ou une playlist. » / « Still kept by another album or playlist. » (`stillKeptElsewhere`), and only the origin is removed; the playlist's m3u8 goes too.
- **N4**: real tests for the `still` re-check (a `_Db` hook drops the record between the listing and the check), for the single-song path in playlist_screen_test, and for on-device `_remove`.
- **N5**: `syncPlaylists` and `forgetPlaylist` both run through `_playlistsSerial`, a chain on `_playlistsJob`, so they never interleave.
- **N6**: the catch-up uses one query, `db.keptPlaylistsMissing()`. It lists, per kept playlist, the present songs with no offline row (own or non-local twin, any state) that are not blocked (themselves or a twin), with their full track rows.
- **Pause**: the catch-up keeps with `unpause: false`, so a user Pause survives it.
- **Doc**: `forgetPlaylist` in playlist_screen.dart now describes the Q13 rule.
- **DemoDownloader**: has configurable `playlistSongs` and `fromOrigin` answers, and its `keep` takes `unpause`.

### Tests
- on_device_screen_test:
  - Q14: the row is removed whole even with `song` and `playlist` origins; the dialog says 2 songs; no origin-based removal is used.
  - Two « Twin » albums by Alpha and Beta show as two rows.
- playlist_screen_test:
  - N3 for a playlist (no dialog, SnackBar, `forgetPlaylist` still called) and for an album (SnackBar, album origin removed).
  - A single song from the Soirée sheet is removed as is, with no origin.
  - The existing « Retirer la playlist » test now sets `playlistSongs`.
- downloader_test:
  - The `still` re-check (record dropped in between → nothing kept).
  - Retirer and the catch-up run concurrently → song 5 not kept, 4 gone, record gone.
  - The catch-up keeps the Pause (song 5 queued, `userPaused` still true).
  - Q15: origins become `song`, and an album removal then no longer takes song 4.
- Mutation check: putting back name-based grouping fails the two-rows test, and dropping the `still` check fails the re-check test.

### Runs
- `flutter analyze`: No issues found!
- `flutter test --exclude-tags golden`: `+756 ~3: All tests passed!` (0 warning or exception lines).
- `flutter test --tags golden`: `+21: All tests passed!`
