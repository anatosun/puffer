import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/subsonic/models.dart';
import '../../downloads/download_manager.dart';

/// Albums with at least one downloaded track, built from the cache.
final downloadedAlbumsProvider = FutureProvider<List<Album>>((ref) async {
  final tracks = await ref.watch(downloadedTracksProvider.future);
  final repository = ref.watch(repositoryProvider);
  if (repository == null) return const [];
  final albums = <Album>[];
  for (final entry in groupBy(
    tracks.where((t) => t.albumId != null),
    (Track t) => t.albumId!,
  ).entries) {
    final first = entry.value.first;
    albums.add(
      await repository.cachedAlbum(entry.key) ??
          Album({
            'id': entry.key,
            'name': first.album,
            'artist': first.artist,
            'artistId': first.artistId,
            'coverArt': first.coverArt,
          }),
    );
  }
  return albums
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
});

/// Artists with at least one downloaded track.
final downloadedArtistsProvider = FutureProvider<List<Artist>>((ref) async {
  final tracks = await ref.watch(downloadedTracksProvider.future);
  final artists = [
    for (final entry in groupBy(
      tracks.where((t) => t.artistId != null),
      (Track t) => t.artistId!,
    ).entries)
      Artist({
        'id': entry.key,
        'name': entry.value.first.artist,
        'albumCount': entry.value.map((t) => t.albumId).toSet().length,
      }),
  ];
  return artists
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
});

final _playlistPinsProvider = StreamProvider((ref) {
  final manager = ref.watch(downloadManagerProvider);
  return manager == null
      ? Stream.value(const [])
      : manager.watchPins(PinKind.playlist);
});

/// Downloaded playlists, read from the cache.
final downloadedPlaylistsProvider = FutureProvider<List<Playlist>>((ref) async {
  final pins = await ref.watch(_playlistPinsProvider.future);
  final repository = ref.watch(repositoryProvider);
  if (repository == null) return const [];
  final playlists = <Playlist>[];
  for (final pin in pins) {
    try {
      playlists.add(await repository.playlist(pin.itemId));
    } on Exception {
      // Not cached yet.
    }
  }
  return playlists;
});
