# Puffer

A music player for iOS and Android for Subsonic and OpenSubsonic servers (Navidrome, Gonic, Airsonic-Advanced, …). The interface follows Plexamp, downloads follow Apple Music, and multi-room playback goes through [Music Assistant](https://music-assistant.io).

The app is in early development.

| Home | Now playing | Recently played | Search | Track menu |
| --- | --- | --- | --- | --- |
| <img src="docs/screenshots/home-dark.webp" width="200"> | <img src="docs/screenshots/now-playing-dark.webp" width="200"> | <img src="docs/screenshots/recently-played-dark.webp" width="200"> | <img src="docs/screenshots/search-dark.webp" width="200"> | <img src="docs/screenshots/track-menu-dark.webp" width="200"> |
| <img src="docs/screenshots/home-light.webp" width="200"> | <img src="docs/screenshots/now-playing-light.webp" width="200"> | <img src="docs/screenshots/recently-played-light.webp" width="200"> | <img src="docs/screenshots/search-light.webp" width="200"> | <img src="docs/screenshots/track-menu-light.webp" width="200"> |

## Features

### Library and playback

- Home has shelves for recently played, recently added and most played albums, recent playlists, favourites, downloads and Discover (random albums). A person chooses which shelves it shows and in what order.
- The library lists playlists, artists, albums, genres and songs. Search finds artists, albums and songs.
- The now-playing view fills the screen with the album artwork, and the colours of the app follow the artwork. The app has a dark and a light theme.
- Instant mix starts a queue of songs similar to a song, from `getSimilarSongs`.
- A person rates songs with stars, adds items to their library (star), and creates and edits playlists.
- Volume is normalised with the ReplayGain values the server reports, per track or per album.
- Plays are reported to the server (scrobbling), so "Recently played" and "Most played" stay up to date.
- Playback continues in the background, with controls on the lock screen and in the Android notification.

### Downloads

Downloads follow Apple Music.

- A person downloads a song, an album, a playlist or an artist. Each download is a pin, and a song file stays on the device while any pin holds it. Thus removing an album download keeps the songs that a downloaded playlist holds.
- A downloaded playlist stays in sync with the server: added songs are downloaded and removed songs are deleted.
- With "Automatic downloads" on, every item a person adds to their library is downloaded.
- "Remove download" and "Remove from library" are two separate actions.
- The library has a "Downloaded" section, and offline mode shows and plays only downloaded music.
- Settings sets the download quality (original or transcoded), downloads over cellular, and a storage limit. With "Optimize storage" on, the app removes the least recently played songs that only automatic downloads hold.

### Speakers

- Puffer connects to [Music Assistant](https://music-assistant.io) and plays the queue on any of its players. Music Assistant fetches the audio from the Subsonic server and sends it to the speakers over [Sendspin](https://www.sendspin-audio.com).
- With "Play as a speaker" on, the phone joins Music Assistant as a Sendspin player and plays in sync with the other speakers.

### Privacy

The app connects only to the servers a person configures. It has no advertising, no analytics and no proprietary dependencies.

## Requirements

- A Subsonic or OpenSubsonic server. Puffer signs in with a username and a password, or with an API key on servers that support the OpenSubsonic `apiKeyAuthentication` extension.
- For multi-room playback, a Music Assistant server, reached at `<host>:8095` with a long-lived access token or a username and a password.

## Install

- Android: APKs are on [GitHub Releases](https://github.com/anatosun/puffer/releases) and in the F-Droid repository at [anatosun.github.io/puffer/fdroid/repo](https://anatosun.github.io/puffer/fdroid/repo?fingerprint=BEF73814AF9AAA087C0D1E1585B92777674363B35CBE50D125C04846593D8ECF), signed with the key of fingerprint `BEF73814AF9AAA087C0D1E1585B92777674363B35CBE50D125C04846593D8ECF`.
- iOS: not yet published.

## Build

Puffer is a Flutter app. `environment.flutter` in `pubspec.yaml` sets the Flutter version.

```sh
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter test
flutter run
```

The Linux build plays audio through media_kit and needs the development packages of libsecret and mpv (`libsecret-devel` and `mpv-devel` on Fedora). iOS builds need macOS and Xcode.

To build the Android APKs:

```sh
flutter build apk --release --split-per-abi
```

## License

Puffer is free software under the [GNU General Public License v3.0 or later](LICENSE).
