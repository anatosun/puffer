import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../data/subsonic/models.dart';
import '../../downloads/download_manager.dart';
import '../theme.dart';
import 'artwork.dart';
import 'download_indicator.dart';
import 'item_actions.dart';

/// A track row. Offline, tracks without a downloaded file are greyed out and cannot be played.
class TrackTile extends ConsumerWidget {
  const TrackTile({
    super.key,
    required this.tracks,
    required this.index,
    this.showArtwork = true,
    this.showNumber = false,
  });

  final List<Track> tracks;
  final int index;
  final bool showArtwork;
  final bool showNumber;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = tracks[index];
    final offline = ref.watch(isOfflineProvider);
    final downloaded = ref.watch(downloadedTrackIdSetProvider);
    final playable = !offline || downloaded.contains(track.id);
    final current = ref.watch(currentTrackIdProvider).value == track.id;
    final color = current ? Theme.of(context).colorScheme.primary : null;

    return Opacity(
      opacity: playable ? 1 : 0.35,
      child: ListTile(
        leading: showArtwork
            ? Artwork(track.coverArt, size: 44, radius: 4)
            : showNumber
            ? SizedBox(
                width: 28,
                child: Text(
                  '${track.trackNumber ?? ''}',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: color ?? Colors.white54),
                ),
              )
            : null,
        title: Text(
          track.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: color),
        ),
        subtitle: Text(
          track.artist ?? '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white54),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TrackDownloadIcon(track.id),
            const SizedBox(width: 8),
            Text(
              formatDuration(track.duration),
              style: const TextStyle(
                color: Colors.white38,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        onTap: playable ? () => playFrom(ref, tracks, index) : null,
        onLongPress: () => showTrackActions(context, ref, track),
      ),
    );
  }
}

/// Plays [tracks] from [index], skipping tracks that cannot play offline.
Future<void> playFrom(
  WidgetRef ref,
  List<Track> tracks,
  int index, {
  bool shuffle = false,
}) async {
  var list = tracks;
  var start = index;
  if (ref.read(isOfflineProvider)) {
    final downloaded = ref.read(downloadedTrackIdSetProvider);
    final selected = tracks[index];
    list = tracks.where((t) => downloaded.contains(t.id)).toList();
    start = list.indexOf(selected).clamp(0, list.length);
  }
  await ref
      .read(playbackProvider)
      .playTracks(list, index: start, shuffle: shuffle);
}

final currentTrackIdProvider = StreamProvider<String?>(
  (ref) => ref.watch(playbackProvider).mediaItem.map((m) => m?.id),
);

class AlbumCard extends ConsumerWidget {
  const AlbumCard(this.album, {super.key, this.width = 150});

  final Album album;
  final double width;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pin =
        ref.watch(pinStateProvider((PinKind.album, album.id))).value ??
        PinState.none;
    return SizedBox(
      width: width,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => context.push('/album/${album.id}'),
        onLongPress: () => showAlbumActions(context, ref, album),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                Artwork(album.coverArt, size: width),
                if (pin.pinned)
                  Positioned(
                    right: 6,
                    bottom: 6,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: DownloadIcon(
                        displayForPin(pin),
                        progress: pin.fraction,
                        size: 16,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              album.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            Text(
              album.artist ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showAlbumActions(
  BuildContext context,
  WidgetRef ref,
  Album album,
) => showItemActions(
  context,
  ref,
  kind: PinKind.album,
  id: album.id,
  title: album.name,
  subtitle: album.artist,
  coverArt: album.coverArt,
  starred: album.starred,
  tracks: () async =>
      (await ref.read(repositoryProvider)!.album(album.id)).songs,
  artistId: album.artistId,
);

class AlbumGrid extends StatelessWidget {
  const AlbumGrid(this.albums, {super.key, this.controller});

  final List<Album> albums;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / 180).floor().clamp(2, 8);
        final width = (constraints.maxWidth - 16 * (columns + 1)) / columns;
        return GridView.builder(
          controller: controller,
          padding: const EdgeInsets.all(16),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: width / (width + 48),
          ),
          itemCount: albums.length,
          itemBuilder: (context, i) => AlbumCard(albums[i], width: width),
        );
      },
    );
  }
}

class ArtistTile extends ConsumerWidget {
  const ArtistTile(this.artist, {super.key});

  final Artist artist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pin =
        ref.watch(pinStateProvider((PinKind.artist, artist.id))).value ??
        PinState.none;
    return ListTile(
      leading: ClipOval(
        child: Artwork(
          artist.coverArt,
          size: 44,
          radius: 0,
          icon: Icons.person,
        ),
      ),
      title: Text(artist.name),
      subtitle: artist.albumCount > 0
          ? Text(
              '${artist.albumCount} albums',
              style: const TextStyle(color: Colors.white54),
            )
          : null,
      trailing: DownloadIcon(displayForPin(pin), progress: pin.fraction),
      onTap: () => context.push('/artist/${artist.id}'),
      onLongPress: () => showItemActions(
        context,
        ref,
        kind: PinKind.artist,
        id: artist.id,
        title: artist.name,
        coverArt: artist.coverArt,
        starred: artist.starred,
      ),
    );
  }
}

class PlaylistTile extends ConsumerWidget {
  const PlaylistTile(this.playlist, {super.key});

  final Playlist playlist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pin =
        ref.watch(pinStateProvider((PinKind.playlist, playlist.id))).value ??
        PinState.none;
    return ListTile(
      leading: Artwork(
        playlist.coverArt,
        size: 52,
        radius: 4,
        icon: Icons.queue_music,
      ),
      title: Text(playlist.name),
      subtitle: Text(
        '${playlist.songCount} songs',
        style: const TextStyle(color: Colors.white54),
      ),
      trailing: DownloadIcon(displayForPin(pin), progress: pin.fraction),
      onTap: () => context.push('/playlist/${playlist.id}'),
      onLongPress: () => showItemActions(
        context,
        ref,
        kind: PinKind.playlist,
        id: playlist.id,
        title: playlist.name,
        subtitle: '${playlist.songCount} songs',
        coverArt: playlist.coverArt,
        tracks: () async =>
            (await ref.read(repositoryProvider)!.playlist(playlist.id)).entries,
      ),
    );
  }
}

/// Error and empty states of lists.
class MessageView extends StatelessWidget {
  const MessageView(
    this.message, {
    super.key,
    this.icon = Icons.cloud_off,
    this.onRetry,
  });

  final String message;
  final IconData icon;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: Colors.white24),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54),
          ),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    ),
  );
}
