# LAFLEURMUSIC for phones

An iPod-style music player for Android and iPhone, in the LAFLEURSTUDIO style.
It plays the music from your own server and keeps a copy of your favourites on the phone.
The phone sibling of [LAFLEURMUSIC for desktop](https://github.com/Jonlekern/lafleurmusic-desktop).

**Status:** early work in progress. Plan 1 (listen to your server) and plan 3 (several accounts merged, server playlists, Cover Flow, tablets) are done. Plan 2 (offline) is done except the "On my iPhone" settings screen (space limit, folder choice): the engine supports both, the screen is coming.

What works now:

- **Your server:** any Subsonic server, Navidrome included. Add an account (address, user, password),
  test it, and the library is copied to the phone: albums, artists, genres, covers, Top 100.
- **Streaming** straight from the server, with custom HTTP headers for servers behind a proxy
  (Cloudflare Access and the like), crossfade, equalizer, equal volume (ReplayGain from the server),
  lock-screen controls and play counts sent back to the server.
- **Accounts:** add, edit, reorder and remove; the phone tells when a server is out of reach.
- **Several accounts, one library:** show one account, all of them, or a choice. The same album on two
  accounts is listed once and played from the best source (a copy on the phone, then the accounts in
  your order). A listen is counted on the account that played the song, and play counts are merged.
- **Server playlists:** shown under the albums, read-only. Keeping one keeps its songs and writes an
  `.m3u8` file under `Playlists/` in the LAFLEURMUSIC folder; the app only ever removes the files it wrote.
- **Cover Flow** when the phone is turned sideways, and **tablets** (iPad, Android) get the columns of the
  desktop app side by side.
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

What comes next: the "On my iPhone" screen, then Jellyfin and Plex.

## Supported servers

Servers that speak the Subsonic API: Navidrome, Gonic, Airsonic-Advanced, Subsonic and compatible servers.

## Build from source

Flutter 3.47 or later. Xcode for iOS, Android Studio (or the Android SDK) for Android.

```bash
flutter pub get
flutter test                                                   # goldens: --tags golden, on macOS
flutter test integration_test/offline_test.dart -d <phone>     # end to end against a fake server
flutter test integration_test/accounts_test.dart -d <phone>    # two fake servers, merged library
flutter build apk --debug                                      # Android
flutter build ios --simulator --debug --no-codesign            # iOS simulator
```

## License

MIT — see [LICENSE](LICENSE). LAFLEURSTUDIO logos and brand assets are not covered by the MIT License.
Third-party components and their licenses: [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
