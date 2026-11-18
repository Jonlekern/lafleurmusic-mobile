# LAFLEURMUSIC for phones

An iPod-style music player for Android and iPhone, in the LAFLEURSTUDIO style.
It plays the music from your own server and keeps a copy of your favourites on the phone.
The phone sibling of [LAFLEURMUSIC for desktop](https://github.com/Jonlekern/lafleurmusic-desktop).

**Status:** early work in progress (0.1.0). This first step is the desktop app slimmed down for phones;
the server connection and the phone screens come next.

## Supported servers

Servers that speak the Subsonic API: Navidrome, Gonic, Airsonic-Advanced, Subsonic and compatible servers.

## Build from source

Flutter 3.47 or later. Xcode for iOS, Android Studio (or the Android SDK) for Android.

```bash
flutter pub get
flutter test
flutter build apk --debug                                      # Android
flutter build ios --simulator --debug --no-codesign            # iOS simulator
```

## License

MIT — see [LICENSE](LICENSE). LAFLEURSTUDIO logos and brand assets are not covered by the MIT License.
Third-party components and their licenses: [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
