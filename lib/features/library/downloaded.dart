import 'package:collection/collection.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/db/database.dart';
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

/// A track file in transfer, with the cached track when there is one.
class Transfer {
  const Transfer(this.file, this.track);

  final TrackFile file;
  final Track? track;

  String get title => track?.title ?? file.trackId;
}

/// The status line of a transfer. Without Wi-Fi, a queued file that may not download over cellular waits for Wi-Fi.
String transferStatus(TrackFile file, {bool waitingForWifi = false}) =>
    switch (file.status) {
      FileStatus.downloading => '${(file.progress * 100).round()} %',
      FileStatus.queued when waitingForWifi => 'Waiting for Wi-Fi',
      FileStatus.queued => 'Waiting',
      FileStatus.paused => 'Paused',
      FileStatus.failed => 'Failed',
      FileStatus.complete || FileStatus.evicted => '',
    };

/// The track files in transfer, downloading first. The cached tracks are read once per track, not on every progress update.
final transfersProvider = StreamProvider<List<Transfer>>((ref) {
  final manager = ref.watch(downloadManagerProvider);
  final repository = ref.watch(repositoryProvider);
  if (manager == null || repository == null) return Stream.value(const []);
  final tracks = <String, Track?>{};
  return manager.watchTransfers().asyncMap((files) async {
    final missing = [
      for (final f in files)
        if (!tracks.containsKey(f.trackId)) f.trackId,
    ];
    if (missing.isNotEmpty) {
      final found = {
        for (final t in await repository.cachedTracks(missing)) t.id: t,
      };
      for (final id in missing) {
        tracks[id] = found[id];
      }
    }
    return [for (final f in files) Transfer(f, tracks[f.trackId])];
  });
});

/// Whether queued downloads wait for Wi-Fi: downloads over cellular are off and the device has no Wi-Fi or Ethernet.
final waitingForWifiProvider = Provider<bool>((ref) {
  if (ref.watch(downloadSettingsProvider).overCellular) return false;
  final results = ref.watch(connectivityProvider).value;
  return results != null &&
      !results.any(
        (r) => r == ConnectivityResult.wifi || r == ConnectivityResult.ethernet,
      );
});
