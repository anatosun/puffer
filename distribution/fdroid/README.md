# F-Droid distribution

The app is published through two channels:

1. The self-hosted repository at `https://anatosun.github.io/puffer/fdroid/repo`. The workflow `.github/workflows/fdroid-repo.yml` adds every GitHub release to it and signs the index with our key. It reads `repo-metadata.yml` and `fastlane/metadata/android/`.
2. The official F-Droid repository. We submit `io.github.anatosun.puffer.yml` as a merge request to [fdroiddata](https://gitlab.com/fdroid/fdroiddata). F-Droid builds the app from source and signs it with its own key. Hence an F-Droid APK cannot update an APK from our releases, and the reverse. Reproducible builds (`Binaries:` and `AllowedAPKSigningKeys:`) remove this restriction.

## Setup of the self-hosted repository

Create the keystore for the index:

```sh
keytool -genkeypair -storetype PKCS12 -keystore fdroid-index.p12 -alias repokey -keyalg RSA -keysize 4096 -validity 10000 -dname "CN=Puffer F-Droid repo"
base64 -w0 fdroid-index.p12
```

Then set the repository secrets `FDROID_KEYSTORE_BASE64` (the output of `base64`), `FDROID_KEYSTORE_PASS`, `FDROID_KEY_ALIAS` (`repokey`) and `FDROID_KEY_PASS`, and enable GitHub Pages from the `gh-pages` branch. Keep an offline copy of the keystore: without it, every person has to add the repository again.

## Checklist for the official repository

- [ ] A free licence file at the repository root, matching `License:` in the recipe
- [ ] No proprietary dependencies in `flutter pub deps` (Firebase, Play Services, GMS)
- [ ] `dependenciesInfo { includeInApk = false; includeInBundle = false }` in `android/app/build.gradle.kts`
- [ ] A release tag `vX.Y.Z` whose pubspec build number `+N` equals `versionCode`
- [ ] A complete `fastlane/metadata/android/en-US/`: icon, screenshots, changelog for `N`
- [ ] `srclibs: flutter@<tag>` set to the Flutter version in `pubspec.yaml`
