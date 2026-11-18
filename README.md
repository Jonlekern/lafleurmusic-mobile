# LAFLEURMUSIC for phones

An iPod-style music player for Android and iPhone, in the LAFLEURSTUDIO style.
It plays the music from your own server and keeps a copy of your favourites on the phone.
The phone sibling of [LAFLEURMUSIC for desktop](https://github.com/Jonlekern/lafleurmusic-desktop).

**Status:** early work in progress (0.1.0), phones held upright.

What works now:

- **Your server:** any Subsonic server, Navidrome included. Add an account (address, user, password),
  test it, and the library is copied to the phone: albums, artists, genres, covers, Top 100.
- **Streaming** straight from the server, with custom HTTP headers for servers behind a proxy
  (Cloudflare Access and the like), crossfade, equalizer, equal volume (ReplayGain from the server),
  lock-screen controls and play counts sent back to the server.
- **Accounts:** add, edit, reorder and remove; the phone tells when a server is out of reach.
- **Builds** for iPhone and Android.

What comes next: offline listening (a copy of your favourites on the phone), several accounts merged
into one library, Cover Flow when the phone is turned sideways, then Jellyfin and Plex.

## Supported servers

Servers that speak the Subsonic API: Navidrome, Gonic, Airsonic-Advanced, Subsonic and compatible servers.

## Build from source

Flutter 3.47 or later. Xcode for iOS, Android Studio (or the Android SDK) for Android.

```bash
flutter pub get
flutter test                                                   # goldens: --tags golden, on macOS
flutter build apk --debug                                      # Android
flutter build ios --simulator --debug --no-codesign            # iOS simulator
```

## License

MIT — see [LICENSE](LICENSE). LAFLEURSTUDIO logos and brand assets are not covered by the MIT License.
Third-party components and their licenses: [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
