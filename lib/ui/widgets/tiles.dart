import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/experience.dart';
import '../../app/playback_providers.dart';
import '../../app/playlist_history.dart';
import '../../app/providers.dart';
import '../../data/subsonic/models.dart';
import '../../features/home/home_page.dart';
import '../../downloads/download_manager.dart';
import '../messages.dart';
import '../theme.dart';
import 'artwork.dart';
import 'brand_mark.dart';
import 'download_indicator.dart';
import 'item_actions.dart';
import 'playing_bars.dart';
import 'pressable.dart';
import 'shimmer.dart';
import 'star_button.dart';

/// A track row. Offline, tracks without a downloaded file are greyed out and cannot be played.
class TrackTile extends ConsumerWidget {
  const TrackTile({
    super.key,
    required this.tracks,
    required this.index,
    this.showArtwork = true,
    this.showNumber = false,
    this.handle,
    this.playlistId,
  });

  final List<Track> tracks;
  final int index;

  /// The playlist the tracks come from, which then counts as played.
  final String? playlistId;
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
    final stars = ref.watch(trackStarsProvider)
        ? ref.watch(ratingOverridesProvider)[track.id] ?? track.rating
        : null;

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
      title: TrackTitle(track.title, color: color),
      subtitle: TrackSubtitle(track.artist, stars: stars),
      isThreeLine: TrackSubtitle.showsStars(stars),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TrackDownloadIcon(track.id),
          const SizedBox(width: 8),
          TrackDuration(track.duration),
          if (ref.watch(trackHeartsProvider))
            TrackHeart(track.id, starred: track.starred),
          ?handle,
        ],
      ),
      onTap: playable
          ? () => playFrom(ref, tracks, index, playlistId: playlistId)
          : null,
      onLongPress: () => showTrackActions(context, ref, track),
    );
    // An Opacity of 1 still makes Impeller composite the row in a layer.
    return playable ? tile : Opacity(opacity: 0.35, child: tile);
  }
}

/// The title of a song, on the first line of its row.
class TrackTitle extends StatelessWidget {
  const TrackTitle(this.title, {super.key, this.color});

  final String title;
  final Color? color;

  @override
  Widget build(BuildContext context) => Text(
    title,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(color: color),
  );
}

/// The lines under the title of a song row: the artist, then the rating as five small stars when the song is rated. Unrated songs, and rows with the stars turned off ([stars] null), show no stars.
class TrackSubtitle extends StatelessWidget {
  const TrackSubtitle(this.artist, {super.key, this.stars});

  final String? artist;

  /// The rating from 0 to 5, or null without stars.
  final int? stars;

  /// Whether the row shows stars, which takes a third line.
  static bool showsStars(int? stars) => (stars ?? 0) > 0;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        artist ?? '',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: context.muted),
      ),
      if (showsStars(stars))
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: TrackStars(stars!),
        ),
    ],
  );
}

/// Five small stars, filled up to [stars]. They only display; the menu of the song changes the rating.
class TrackStars extends StatelessWidget {
  const TrackStars(this.stars, {super.key});

  final int stars;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$stars stars',
    excludeSemantics: true,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          Icon(
            i <= stars ? Icons.star_rounded : Icons.star_outline_rounded,
            size: 12,
            color: i <= stars
                ? Theme.of(context).colorScheme.primary
                : context.faint,
          ),
      ],
    ),
  );
}

/// The length of a song, right-aligned in a column wide enough for most lengths, so the icons before it line up from row to row.
class TrackDuration extends StatelessWidget {
  const TrackDuration(this.duration, {super.key});

  final Duration duration;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minWidth: 40),
    child: Text(
      formatDuration(duration),
      textAlign: TextAlign.right,
      style: TextStyle(
        color: context.faint,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
    ),
  );
}

/// A filled heart for a song in the library, left of the drag handle when the row has one. It only displays. Other songs keep the space empty, so the icons of all rows stand in the same columns.
class TrackHeart extends ConsumerWidget {
  const TrackHeart(this.id, {super.key, required this.starred});

  final String id;
  final bool starred;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = isStarred(ref, (
      trackId: id,
      albumId: null,
      artistId: null,
    ), fallback: starred);
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: SizedBox.square(
        dimension: 16,
        child: on
            ? Icon(
                Icons.favorite,
                size: 16,
                color: Theme.of(context).colorScheme.primary,
                semanticLabel: 'In your library',
              )
            : null,
      ),
    );
  }
}

/// The song behind a queue entry, from the cache when the library knows it, or null when it does not. Only songs missing from the cache are asked of the server, so scrolling a long queue sends no request per row. Rows that scroll away drop theirs.
final queueTrackProvider = FutureProvider.autoDispose.family<Track?, String>((
  ref,
  id,
) async {
  final repository = ref.watch(repositoryProvider);
  if (repository == null) return null;
  final cached = await repository.cachedTracks([id]);
  if (cached.isNotEmpty) return cached.single;
  try {
    return await repository.track(id);
  } on Exception {
    return null;
  }
});

/// Plays [tracks] from [index], skipping tracks that cannot play offline. With [playlistId], the playlist moves to the top of the recent playlists.
Future<void> playFrom(
  WidgetRef ref,
  List<Track> tracks,
  int index, {
  bool shuffle = false,
  String? playlistId,
}) async {
  HapticFeedback.lightImpact();
  if (playlistId != null) {
    await ref.read(playlistHistoryProvider.notifier).played(playlistId);
  }
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
                  if (pin.pinned) CardDownloadBadge(pin),
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

/// The download state in the bottom-right corner of a cover, the same on album and playlist cards.
class CardDownloadBadge extends StatelessWidget {
  const CardDownloadBadge(this.pin, {super.key});

  final PinState pin;

  @override
  Widget build(BuildContext context) => Positioned(
    right: 6,
    bottom: 6,
    child: Container(
      padding: const EdgeInsets.all(2),
      decoration: const BoxDecoration(
        color: Colors.black54,
        shape: BoxShape.circle,
      ),
      child: DownloadIcon(displayForPin(pin), progress: pin.fraction, size: 16),
    ),
  );
}

class PlaylistCard extends ConsumerWidget {
  const PlaylistCard(this.playlist, {super.key, this.width = 150});

  final Playlist playlist;
  final double width;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pin =
        ref.watch(pinStateProvider((PinKind.playlist, playlist.id))).value ??
        PinState.none;
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
              Stack(
                children: [
                  PlaylistArtwork(playlist, size: width, radius: 6),
                  if (pin.pinned) CardDownloadBadge(pin),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                playlist.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(
                countOf(playlist.songCount, 'song'),
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
      title: Text(artist.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      // Always a second line, so artist rows are as tall as each other and as song rows.
      subtitle: Text(
        artist.albumCount > 0 ? countOf(artist.albumCount, 'album') : 'Artist',
        style: TextStyle(color: context.muted),
      ),
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

/// The covers of a playlist's first albums, from the cache. Reloads when the playlists change.
final playlistCoversProvider = FutureProvider.autoDispose
    .family<List<String>, String>((ref, id) async {
      ref.watch(playlistsProvider);
      return await ref.watch(repositoryProvider)?.cachedPlaylistCovers(id) ??
          const [];
    });

/// The cover of a playlist. Without a cover from the server, a 2×2 mosaic of its first four albums, or the cover of its first album when it has fewer. The mosaic needs the playlist to have been opened or downloaded once.
class PlaylistArtwork extends ConsumerWidget {
  const PlaylistArtwork(this.playlist, {super.key, this.size, this.radius = 4});

  final Playlist playlist;
  final double? size;
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (playlist.coverArt != null) {
      return Artwork(
        playlist.coverArt,
        size: size,
        radius: radius,
        icon: Icons.queue_music,
      );
    }
    final covers =
        ref.watch(playlistCoversProvider(playlist.id)).value ?? const [];
    if (covers.length < 4) {
      return Artwork(
        covers.firstOrNull,
        size: size,
        radius: radius,
        icon: Icons.queue_music,
      );
    }
    // The cells share the box the cover gets, which a list row can make smaller than [size] (a ListTile gives its leading widget at most 48 points of height).
    final half = size == null ? null : size! / 2;
    Widget cell(int i) =>
        Expanded(child: Artwork(covers[i], size: half, radius: 0));
    Widget row(int first) => Expanded(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [cell(first), cell(first + 1)],
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox.square(
        dimension: size,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [row(0), row(2)],
        ),
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
      leading: PlaylistArtwork(playlist, size: 52),
      title: Text(playlist.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        countOf(playlist.songCount, 'song'),
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
  subtitle: countOf(playlist.songCount, 'song'),
  coverArt: playlist.coverArt,
  playlist: playlist,
  tracks: () async =>
      (await ref.read(repositoryProvider)!.playlist(playlist.id)).entries,
);

/// Shows the items of external providers, which a proxy such as octo-fiesta mixes in. It sits in the bar of the search page and next to the heart of the artist page.
class MoreSourcesButton extends StatelessWidget {
  const MoreSourcesButton({super.key, required this.onPressed, this.iconSize});

  final VoidCallback onPressed;
  final double? iconSize;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'More from other sources',
    iconSize: iconSize,
    icon: const Icon(Icons.travel_explore),
    onPressed: onPressed,
  );
}

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
          BrandMark(size: 120, color: context.faint),
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
