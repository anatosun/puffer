import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/experience.dart';
import '../../app/playback_providers.dart';
import '../../app/providers.dart';
import '../../data/subsonic/models.dart';
import '../../downloads/download_manager.dart';
import '../messages.dart';
import '../theme.dart';
import 'artwork.dart';
import 'download_indicator.dart';
import 'item_actions.dart';
import 'playing_bars.dart';
import 'pressable.dart';
import 'shimmer.dart';

/// A track row. Offline, tracks without a downloaded file are greyed out and cannot be played.
class TrackTile extends ConsumerWidget {
  const TrackTile({
    super.key,
    required this.tracks,
    required this.index,
    this.showArtwork = true,
    this.showNumber = false,
    this.handle,
  });

  final List<Track> tracks;
  final int index;
  final bool showArtwork;
  final bool showNumber;

  /// A drag handle, shown last in rows of editable playlists.
  final Widget? handle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = tracks[index];
    final offline = ref.watch(isOfflineProvider);
    final downloaded = ref.watch(downloadedTrackIdSetProvider);
    final playable = !offline || downloaded.contains(track.id);
    final current = ref.watch(currentTrackIdProvider) == track.id;
    final playing =
        current && (ref.watch(nowPlayingProvider).value?.playing ?? false);
    final color = current ? Theme.of(context).colorScheme.primary : null;

    final tile = ListTile(
      leading: showArtwork
          ? Stack(
              alignment: Alignment.center,
              children: [
                Artwork(track.coverArt, size: 44, radius: 4),
                if (current)
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    alignment: Alignment.center,
                    child: PlayingBars(playing: playing, color: Colors.white),
                  ),
              ],
            )
          : showNumber
          ? SizedBox(
              width: 28,
              child: current
                  ? Center(
                      child: PlayingBars(playing: playing, color: color!),
                    )
                  : Text(
                      '${track.trackNumber ?? ''}',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: context.muted),
                    ),
            )
          : null,
      title: Text(
        track.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: color),
      ),
      subtitle: Row(
        children: [
          if (downloaded.contains(track.id))
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(
                Icons.arrow_circle_down,
                size: 14,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          Expanded(
            child: Text(
              track.artist ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: context.muted),
            ),
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Downloaded tracks carry the mark next to the artist; this shows transfers in progress.
          TrackDownloadIcon(track.id, hideComplete: true),
          const SizedBox(width: 8),
          Text(
            formatDuration(track.duration),
            style: TextStyle(
              color: context.faint,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          ?handle,
        ],
      ),
      onTap: playable ? () => playFrom(ref, tracks, index) : null,
      onLongPress: () => showTrackActions(context, ref, track),
    );
    // An Opacity of 1 still makes Impeller composite the row in a layer.
    return playable ? tile : Opacity(opacity: 0.35, child: tile);
  }
}

/// Plays [tracks] from [index], skipping tracks that cannot play offline.
Future<void> playFrom(
  WidgetRef ref,
  List<Track> tracks,
  int index, {
  bool shuffle = false,
}) async {
  HapticFeedback.lightImpact();
  var list = tracks;
  var start = index;
  if (ref.read(isOfflineProvider)) {
    final downloaded = ref.read(downloadedTrackIdSetProvider);
    final selected = tracks[index];
    list = tracks.where((t) => downloaded.contains(t.id)).toList();
    start = list.indexOf(selected).clamp(0, list.length);
  }
  await runPlayback(
    () => ref
        .read(playbackControllerProvider)
        .playTracks(list, index: start, shuffle: shuffle),
  );
}

final currentTrackIdProvider = Provider<String?>(
  (ref) => ref.watch(nowPlayingProvider).value?.track?.id,
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
    return Pressable(
      child: SizedBox(
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
                style: TextStyle(color: context.muted, fontSize: 13),
              ),
            ],
          ),
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
  mix: () => ref.read(repositoryProvider)!.radio(albumId: album.id),
  rating: album.rating,
  onRated: (value) => rememberRating(album.json, value),
  artistId: album.artistId,
);

/// A horizontal row of album cards at the cover size the person picked.
class AlbumShelf extends ConsumerWidget {
  const AlbumShelf(this.albums, {super.key, this.loading = false});

  final List<Album> albums;
  final bool loading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = ref.watch(coverSizeProvider).shelfWidth;
    return SizedBox(
      height: width + 60,
      child: loading
          ? ShelfPlaceholder(width: width)
          : ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: albums.length,
              separatorBuilder: (_, _) => const SizedBox(width: 14),
              itemBuilder: (context, i) => AlbumCard(albums[i], width: width),
            ),
    );
  }
}

class PlaylistCard extends ConsumerWidget {
  const PlaylistCard(this.playlist, {super.key, this.width = 150});

  final Playlist playlist;
  final double width;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Pressable(
      child: SizedBox(
        width: width,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => context.push('/playlist/${playlist.id}'),
          onLongPress: () => showPlaylistActions(context, ref, playlist),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Artwork(playlist.coverArt, size: width, icon: Icons.queue_music),
              const SizedBox(height: 6),
              Text(
                playlist.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(
                '${playlist.songCount} songs',
                maxLines: 1,
                style: TextStyle(color: context.muted, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A horizontal row of playlist cards at the cover size the person picked.
class PlaylistShelf extends ConsumerWidget {
  const PlaylistShelf(this.playlists, {super.key, this.loading = false});

  final List<Playlist> playlists;
  final bool loading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = ref.watch(coverSizeProvider).shelfWidth;
    return SizedBox(
      height: width + 60,
      child: loading
          ? ShelfPlaceholder(width: width)
          : ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: playlists.length,
              separatorBuilder: (_, _) => const SizedBox(width: 14),
              itemBuilder: (context, i) =>
                  PlaylistCard(playlists[i], width: width),
            ),
    );
  }
}

class AlbumGrid extends ConsumerWidget {
  const AlbumGrid(this.albums, {super.key, this.controller});

  final List<Album> albums;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final size = ref.watch(coverSizeProvider);
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = size.columns(constraints.maxWidth);
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
              style: TextStyle(color: context.muted),
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
        mix: () => ref.read(repositoryProvider)!.radio(artistId: artist.id),
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
        style: TextStyle(color: context.muted),
      ),
      trailing: DownloadIcon(displayForPin(pin), progress: pin.fraction),
      onTap: () => context.push('/playlist/${playlist.id}'),
      onLongPress: () => showPlaylistActions(context, ref, playlist),
    );
  }
}

Future<void> showPlaylistActions(
  BuildContext context,
  WidgetRef ref,
  Playlist playlist,
) => showItemActions(
  context,
  ref,
  kind: PinKind.playlist,
  id: playlist.id,
  title: playlist.name,
  subtitle: '${playlist.songCount} songs',
  coverArt: playlist.coverArt,
  playlist: playlist,
  tracks: () async =>
      (await ref.read(repositoryProvider)!.playlist(playlist.id)).entries,
);

/// Error and empty states of lists, with the pufferfish.
class MessageView extends StatelessWidget {
  const MessageView(this.message, {super.key, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Opacity(
            opacity: 0.55,
            child: Image.asset('assets/icon/foreground.png', height: 120),
          ),
          const SizedBox(height: 4),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: context.muted),
          ),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    ),
  );
}
