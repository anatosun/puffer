# Flathub

`io.github.anatosun.puffer.yml` is the Flatpak manifest for Flathub. It repackages the Linux bundles of a GitHub release (`puffer-X.Y.Z-linux-x64.tar.gz` and `puffer-X.Y.Z-linux-arm64.tar.gz`) and builds libass, libplacebo and libmpv, which the GNOME runtime lacks. The desktop entry and the AppStream metadata come from this folder at the release tag.

## First submission

1. Release a version whose tag contains this folder; the manifest names 0.1.44.
2. Fill in the two `sha256` values of the bundles from `SHA256SUMS-linux-x64.txt` and `SHA256SUMS-linux-arm64.txt` of the release.
3. Build and run it locally:

   ```sh
   flatpak install flathub org.gnome.Sdk//51 org.gnome.Platform//51 org.flatpak.Builder
   flatpak run org.flatpak.Builder --force-clean --user --install --install-deps-from=flathub build io.github.anatosun.puffer.yml
   flatpak run io.github.anatosun.puffer
   flatpak run --command=flatpak-builder-lint org.flatpak.Builder manifest io.github.anatosun.puffer.yml
   ```

4. Fork https://github.com/flathub/flathub, branch from `new-pr`, add the manifest, and open a pull request against `new-pr`, as https://docs.flathub.org/docs/for-app-authors/submission describes.

Flathub reviewers may ask for a build from source. `flatpak-flutter` (https://github.com/TheAppgineer/flatpak-flutter) generates the offline sources of the Flutter SDK and of the pub packages for that.

## Each release

Once the app is on Flathub, the manifest lives in `flathub/io.github.anatosun.puffer`. The Flathub bot reads the `x-checker-data` entries and opens a pull request with the new URLs and checksums. Each release adds a `<release>` line to `io.github.anatosun.puffer.metainfo.xml`.
