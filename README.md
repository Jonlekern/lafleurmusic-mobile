# LAFLEURMUSIC for phones

An iPod-style music player for Android and iPhone, in the LAFLEURSTUDIO style.
It plays the music from your own server and keeps a copy of your favourites on the phone.
The phone sibling of [LAFLEURMUSIC for desktop](https://github.com/Jonlekern/lafleurmusic-desktop).

**Status:** early work in progress (0.1.0), phones held upright. Plans 1 (listen to your server) and 2 (offline) are done.

What works now:

- **Your server:** any Subsonic server, Navidrome included. Add an account (address, user, password),
  test it, and the library is copied to the phone: albums, artists, genres, covers, Top 100.
- **Streaming** straight from the server, with custom HTTP headers for servers behind a proxy
  (Cloudflare Access and the like), crossfade, equalizer, equal volume (ReplayGain from the server),
  lock-screen controls and play counts sent back to the server.
- **Accounts:** add, edit, reorder and remove; the phone tells when a server is out of reach.
- **Offline:** keep songs, albums or playlists on the phone ("Keep on my iPhone / phone") as real
  files, filed as Artist/Album with tags and cover. They play from the copy when the server is out of
  reach; what isn't on the phone is greyed out. A download queue resumes after an interruption and
  respects a space limit you can change.
- **Your folder:** the copies go to Files → On My iPhone → LAFLEURMUSIC (iPhone) or Music/LAFLEURMUSIC
  (Android), or to a folder you choose, iCloud Drive included. Moving the folder moves the copies.
- **Top 100 at home:** your most played songs are kept on the phone by themselves, only on Wi-Fi with
  your server answering.
- **Listens made offline** are queued and sent to the server, with their original date, when it is back.
- **Files placed by hand** in the LAFLEURMUSIC folder show up in the library.
- **Builds** for iPhone and Android.

What comes next: several accounts merged into one library, Cover Flow when the phone is turned
sideways, then Jellyfin and Plex.

## Supported servers

Servers that speak the Subsonic API: Navidrome, Gonic, Airsonic-Advanced, Subsonic and compatible servers.

## Build from source

Flutter 3.47 or later. Xcode for iOS, Android Studio (or the Android SDK) for Android.

```bash
flutter pub get
flutter test                                                   # goldens: --tags golden, on macOS
flutter test integration_test/offline_test.dart -d <phone>     # end to end against a fake server
flutter build apk --debug                                      # Android
flutter build ios --simulator --debug --no-codesign            # iOS simulator
```

## License

MIT — see [LICENSE](LICENSE). LAFLEURSTUDIO logos and brand assets are not covered by the MIT License.
Third-party components and their licenses: [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
