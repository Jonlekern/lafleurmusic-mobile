# LAFLEURMUSIC for phones

An iPod-style music player for Android and iPhone, in the LAFLEURSTUDIO style.
It plays the music from your own server and keeps a copy of your favourites on the phone.
The phone sibling of [LAFLEURMUSIC for desktop](https://github.com/Jonlekern/lafleurmusic-desktop).

**Status:** early work in progress. Plan 1 (listen to your server), plan 3 (several accounts merged, server playlists, Cover Flow, tablets), plan 4 (Jellyfin) and plan 8 (queue and library) are done. Plan 2 (offline) is done except the "On my iPhone" settings screen (space limit, folder choice): the engine supports both, the screen is coming.

What works now:

- **Your server:** any Subsonic server, Navidrome included, or Jellyfin. Add an account (address, user,
  password), test it, and the library is copied to the phone: albums, artists, genres, covers, Top 100.
- **Jellyfin:** sign-in with name and password (the app keeps the access token and signs in again by
  itself when the server drops it), music libraries, covers, playlists, streaming, downloads of the
  original file and listens sent back.
- **Streaming** straight from the server, with custom HTTP headers for servers behind a proxy
  (Cloudflare Access and the like), crossfade, equalizer, equal volume (ReplayGain from the server),
  lock-screen controls and play counts sent back to the server.
- **Accounts:** add, edit, reorder and remove; the phone tells when a server is out of reach.
- **Several accounts, one library:** show one account, all of them, or a choice, Subsonic and Jellyfin
  mixed. The same album on two accounts is listed once and played from the best source (a copy on the phone, then the accounts in
  your order). A listen is counted on the account that played the song, and play counts are merged.
- **Server playlists:** shown under the albums, read-only. Keeping one keeps its songs and writes an
  `.m3u8` file under `Playlists/` in the LAFLEURMUSIC folder; the app only ever removes the files it wrote.
- **Cover Flow** when the phone is turned sideways, and **tablets** (iPad, Android) get the columns of the
  desktop app side by side (both done).
- **Queue:** swipe a song to the right to add it to the queue (a bubble offers Undo and View queue); to the
  left to play it next. "Clear" in Up Next removes only what you added, after asking; the rest of the album
  stays. Files placed by hand work the same way.
- **Albums:** tap the ALBUMS title on Home for the Albums screen: the last albums you played, and a sort
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
- **Listens made offline** are queued and sent to the server, with their original date, when it is back.
- **Files placed by hand** in the LAFLEURMUSIC folder show up in the library.
- **Builds** for iPhone and Android.

What comes next: the "On my iPhone" screen, then Plex.

## Supported servers

- Servers that speak the Subsonic API: Navidrome, Gonic, Airsonic-Advanced, Subsonic and compatible servers.
- Jellyfin 10.9 and 10.10 (checked in CI against a real Jellyfin 10.10).

## Build from source

Flutter 3.47 or later. Xcode for iOS, Android Studio (or the Android SDK) for Android.

```bash
flutter pub get
flutter test                                                   # goldens: --tags golden, on macOS
flutter test integration_test/offline_test.dart -d <phone>     # end to end against a fake server
flutter test integration_test/accounts_test.dart -d <phone>    # fake Navidrome and Jellyfin, merged library
flutter test integration_test/queue_library_test.dart -d <phone>  # queue, Clear, Albums sort (local files)
flutter build apk --debug                                      # Android
flutter build ios --simulator --debug --no-codesign            # iOS simulator
```

## License

MIT — see [LICENSE](LICENSE). LAFLEURSTUDIO logos and brand assets are not covered by the MIT License.
Third-party components and their licenses: [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
