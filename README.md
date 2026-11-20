# LAFLEURMUSIC for phones

An iPod-style music player for Android and iPhone, in the LAFLEURSTUDIO style.
It plays the music from your own server and keeps a copy of your favourites on the phone.
The phone sibling of [LAFLEURMUSIC for desktop](https://github.com/Jonlekern/lafleurmusic-desktop).

**Status:** early work in progress. Plan 1 (listen to your server), plan 3 (several accounts merged, server playlists, Cover Flow, tablets), plan 4 (Jellyfin), plan 5 (Plex), plan 6 (Classic mode: an iPod-style menu with a click wheel, chosen in Settings), plan 8 (queue and library) and plan 9 (editable playlists) are done. Plan 2 (offline) is done except the "On my iPhone" settings screen (space limit, folder choice): the engine supports both, the screen is coming.

What works now:

- **Your server:** any Subsonic server, Navidrome included, Jellyfin or Plex. Add an account (address, user,
  password), test it, and the library is copied to the phone: albums, artists, genres, covers, Top 100.
- **Jellyfin:** sign-in with name and password (the app keeps the access token and signs in again by
  itself when the server drops it), music libraries, covers, playlists, streaming, downloads of the
  original file and listens sent back.
- **Plex:** sign-in with a code typed on plex.tv/link (no password goes through the app), the server's
  best address chosen again when the network changes, music libraries, covers, playlists, streaming,
  downloads of the original file and listens sent back. Plex doesn't accept the date of a listen sent
  later: a listen made offline counts as played when it is sent, not when it was heard.
- **Streaming** straight from the server, with custom HTTP headers for servers behind a proxy
  (Cloudflare Access and the like), crossfade, equalizer, equal volume (ReplayGain from the server),
  lock-screen controls and play counts sent back to the server.
- **Accounts:** add, edit, reorder and remove; the phone tells when a server is out of reach.
- **Several accounts, one library:** show one account, all of them, or a choice, Subsonic, Jellyfin and Plex
  mixed. The same album on two accounts is listed once and played from the best source (a copy on the phone, then the accounts in
  your order). A listen is counted on the account that played the song, and play counts are merged.
- **Server playlists:** shown under the albums. Keeping one keeps its songs and writes an
  `.m3u8` file under `Playlists/` in the LAFLEURMUSIC folder; the app only ever removes the files it wrote.
- **Editable playlists:** "Add to a playlist" in a song's menu ticks one or
  more playlists or makes a new one, with a warning when a song is already in it. A playlist screen has
  Add, Edit (rename, remove, move, delete, cover) and Sort. On a Subsonic (Navidrome), Jellyfin or Plex
  server the change is written on the server, which stays the source of truth; a server or a playlist
  that refuses writes stays read-only, with a clear message.
- **Playlists on the phone:** a playlist can live on the phone only ("On my iPhone"), with songs from any
  account and files placed by hand. Keeping it writes its `.m3u8` too, and the file follows every edit.
  Nothing is sent to a server unless you pick that server as the place.
- **No server needed:** the first screen has "Just the music on my iPhone". The app then starts with an
  empty Home that says where to put files (Files app › LAFLEURMUSIC) and offers to choose another folder or
  add an account later. Songs, queue, playlists and Classic mode all work with files only.
- **Cover Flow** when the phone is turned sideways, and **tablets** (iPad, Android) get the columns of the
  desktop app side by side (both done).
- **Queue:** swipe a song to the right to add it to the queue (a bubble offers Undo and View queue); to the
  left to play it next. "Clear" in Up Next removes only what you added, after asking; the rest of the album
  stays. Files placed by hand work the same way.
- **Albums:** the Albums row on Home (or the ALBUMS title) opens the Albums screen: the last albums you played, and a sort
  by name, artist, recently added or most played, which the app remembers. "Go to album" and "Go to artist"
  are at the top of the Now Playing ⋯ menu (phone only).
- **Offline:** keep songs or albums on the phone ("Keep on my iPhone / phone") as real
  files, filed as Artist/Album with tags and cover. They play from the copy when the server is out of
  reach; what isn't on the phone is greyed out. A download queue resumes after an interruption and
  respects a space limit (10 GB for now).
- **Your folder:** the copies go to Files → On My iPhone → LAFLEURMUSIC (iPhone) or Music/LAFLEURMUSIC
  (Android). Choosing another folder (iCloud Drive included) and moving the copies there is built into the
  engine; its screen is coming.
- **Top 100 at home:** your most played songs are kept on the phone by themselves, only on Wi-Fi with
  your server answering.
- **Listens made offline** are queued and sent to the server, with their original date, when it is back
  (Plex has no date: see above).
- **Files placed by hand** in the LAFLEURMUSIC folder show up in the library.
- **Builds** for iPhone and Android.

What comes next: the "On my iPhone" screen.

## Supported servers

- Servers that speak the Subsonic API: Navidrome, Gonic, Airsonic-Advanced, Subsonic and compatible servers.
- Jellyfin 10.9 and 10.10 (checked in CI against a real Jellyfin 10.10).
- Plex Media Server (checked against a fake plex.tv and a fake server only: no real Plex account in CI).

## Build from source

Flutter 3.47 or later. Xcode for iOS, Android Studio (or the Android SDK) for Android.

```bash
flutter pub get
flutter test                                                   # goldens: --tags golden, on macOS
flutter test integration_test/offline_test.dart -d <phone>     # end to end against a fake server
flutter test integration_test/accounts_test.dart -d <phone>    # fake Navidrome, Jellyfin and Plex, merged library
flutter test integration_test/queue_library_test.dart -d <phone>  # queue, Clear, Albums sort (local files)
flutter test integration_test/playlists_phone_test.dart -d <phone>   # no account: a phone playlist and its .m3u8
flutter test integration_test/playlists_server_test.dart -d <phone>  # fake Navidrome: create, add, no duplicate, sort
flutter build apk --debug                                      # Android
flutter build ios --simulator --debug --no-codesign            # iOS simulator
```

## License

MIT — see [LICENSE](LICENSE). LAFLEURSTUDIO logos and brand assets are not covered by the MIT License.
Third-party components and their licenses: [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
