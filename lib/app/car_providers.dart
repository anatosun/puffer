import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../playback/car_library.dart';
import 'playback_providers.dart';
import 'providers.dart';

/// The authority of the content provider that lets the car read artwork (`ArtworkProvider.kt`).
const carArtAuthority = 'io.github.anatosun.puffer.artwork';

/// The size of the covers a car shows, the size the app's colour extraction fetches, so the two share their cache.
const carArtSize = 300;

/// [file] as a URI the car can open: Android Auto runs in a process of its own, which cannot read the app's files.
Uri carArtUri(File file) =>
    Uri(scheme: 'content', host: carArtAuthority, path: file.path);

/// What a car browses, for the session; null while signed out. The car preview of debug builds reads it too, which is why it is built on every platform. A car plays on this device, so playing from the car leaves the Music Assistant player that was selected.
final carLibraryProvider = Provider<CarLibrary?>((ref) {
  final handler = ref.watch(playbackProvider);
  final repository = ref.watch(repositoryProvider);
  if (repository == null) return null;
  // Android Auto reads covers through the content provider; the preview opens the files.
  final toUri = Platform.isAndroid ? carArtUri : (File f) => f.uri;
  // The covers fetched for the car in this session, by cover-art ID.
  final fetched = <String, File>{};
  Uri? art(String? coverArt) {
    if (coverArt == null) return null;
    final file =
        ref.read(artworkStoreProvider)?.existing(coverArt) ?? fetched[coverArt];
    return file == null ? null : toUri(file);
  }

  // One after another, so a long list does not ask the server for every cover at once.
  Future<void> prepareArt(Iterable<String?> coverArts) async {
    final cache = ref.read(artworkCacheProvider);
    for (final coverArt in coverArts.nonNulls) {
      final key = 'art:$coverArt:$carArtSize';
      try {
        final cached = await cache.getFileFromCache(key);
        if (cached != null) {
          fetched[coverArt] = cached.file;
          continue;
        }
        final client = ref.read(clientProvider);
        if (client == null || ref.read(isOfflineProvider)) continue;
        fetched[coverArt] = await cache.getSingleFile(
          client.unsignedCoverArtUri(coverArt, size: carArtSize).toString(),
          key: key,
        );
      } on Object {
        // The item shows without its cover.
      }
    }
  }

  return CarLibrary(
    repository: repository,
    play: (tracks, {index = 0, shuffle = false}) async {
      ref.read(outputProvider.notifier).select(null);
      await handler.playTracks(tracks, index: index, shuffle: shuffle);
    },
    resume: () async {
      ref.read(outputProvider.notifier).select(null);
      await handler.play();
    },
    nowPlaying: () => handler.mediaItem.value,
    art: art,
    prepareArt: prepareArt,
  );
});

/// Gives the player [carLibraryProvider], which Android Auto reaches through the media session. It lives for the session from `main`, as a car can start the app without its screen.
final carSessionProvider = Provider<void>((ref) {
  if (!Platform.isAndroid) return;
  ref.watch(playbackProvider).library = ref.watch(carLibraryProvider);
});
