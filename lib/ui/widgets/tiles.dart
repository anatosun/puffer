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
import '../layout.dart';
import '../messages.dart';
import '../theme.dart';
import 'artwork.dart';
import 'brand_mark.dart';
import 'download_indicator.dart';
import 'title_cover.dart';
import 'item_actions.dart';
import 'playing_bars.dart';
import 'pressable.dart';
import 'shimmer.dart';
import 'star_button.dart';

/// Whether the rows of an album by [albumArtist] show the artist: on every row once one song is by someone else.
bool albumShowsArtists(String? albumArtist, List<Track> songs) =>
    songs.any((t) => t.artist != null && t.artist != albumArtist);

/// Whether any song of a list is rated, cached per list and per set of ratings, so each row asks once and a long list is scanned once.
final _listRated = Expando<(Map<String, int>, bool)>();

/// Whether the rows of [tracks] keep a line for the stars: the stars are on and a song of the list is rated, so every row has the same height.
bool listShowsStars(WidgetRef ref, List<Track> tracks) {
  if (!ref.watch(trackStarsProvider)) return false;
  final overrides = ref.watch(ratingOverridesProvider);
  final cached = _listRated[tracks];
  if (cached != null && identical(cached.$1, overrides)) return cached.$2;
  final rated = tracks.any((t) => (overrides[t.id] ?? t.rating) > 0);
  _listRated[tracks] = (overrides, rated);
  return rated;
}

/// A track row. Offline, tracks without a downloaded file are greyed out and cannot be played.
class TrackTile extends ConsumerWidget {
  const TrackTile({
    super.key,
    required this.tracks,
    required this.index,
    this.showArtwork = true,
    this.showNumber = false,
    this.showArtist = true,
    this.handle,
    this.playlistId,
  });

  final List<Track> tracks;
  final int index;

  /// The playlist the tracks come from, which then counts as played.
  final String? playlistId;
  final bool showArtwork;
  final bool showNumber;

  /// Shows the artist below the title, or in its column in a wide window. The page of an album hides it when every song is by the album artist.
  final bool showArtist;

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

    // A wide window shows the artist and the album in columns of their own, as a table.
    final wide = isWide(context);
    final rated = TrackSubtitle.showsStars(stars);
    final reserveStars = listShowsStars(ref, tracks);
    final Widget? subtitle = wide
        ? (rated
              ? TrackStars(stars!, size: CompactRow.starSize)
              : reserveStars
              ? const SizedBox(height: CompactRow.starSize)
              : null)
        : !showArtist && !reserveStars
        ? null
        : TrackSubtitle(
            showArtist ? track.artist : null,
            stars: stars,
            reserveStars: reserveStars,
            starSize: CompactRow.starSize,
          );
    Widget tile = CompactRow(
      // Rows with a cover are as tall as it; the rows of an album, numbered, are a little lower.
      minHeight: showArtwork ? 44 : 36,
      verticalPadding: showArtwork ? 4 : 6,
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
      title: wide
          ? Row(
              children: [
                Expanded(flex: 5, child: TrackTitle(track.title, color: color)),
                if (showArtist) ...[
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 3,
                    child: _Column(
                      track.artist,
                      path: track.artistId == null
                          ? null
                          : '/artist/${track.artistId}',
                    ),
                  ),
                ],
                // The album column says nothing on the page of the album.
                if (!showNumber) ...[
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 3,
                    child: _Column(
                      track.album,
                      path: track.albumId == null
                          ? null
                          : '/album/${track.albumId}',
                    ),
                  ),
                ],
              ],
            )
          : TrackTitle(track.title, color: color),
      subtitle: subtitle,
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
    tile = SongsDraggable(
      songs: DraggedSongs(track.title, () async => [track]),
      child: SecondaryTap(
        onTap: () => showTrackActions(context, ref, track),
        child: tile,
      ),
    );
    // An Opacity of 1 still makes Impeller composite the row in a layer.
    return playable ? tile : Opacity(opacity: 0.35, child: tile);
  }
}

/// A song row, lower than a [ListTile]: the title, the artist and the stars stack to the height of the cover, with little room between rows.
class CompactRow extends StatelessWidget {
  const CompactRow({
    super.key,
    required this.minHeight,
    required this.verticalPadding,
    this.leading,
    required this.title,
    this.subtitle,
    required this.trailing,
    this.onTap,
    this.onLongPress,
  });

  /// The height of the stars in a row.
  static const double starSize = 11;

  final double minHeight;
  final double verticalPadding;
  final Widget? leading;
  final Widget title;
  final Widget? subtitle;
  final Widget trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 16,
          vertical: verticalPadding,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: minHeight),
          child: Row(
            children: [
              if (leading case final leading?) ...[
                leading,
                const SizedBox(width: 14),
              ],
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DefaultTextStyle.merge(
                      style: text.bodyLarge?.copyWith(
                        fontSize: 15,
                        height: 1.1,
                      ),
                      child: title,
                    ),
                    if (subtitle case final subtitle?)
                      DefaultTextStyle.merge(
                        style: text.bodyMedium?.copyWith(
                          fontSize: 13,
                          height: 1.15,
                        ),
                        child: subtitle,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              trailing,
            ],
          ),
        ),
      ),
    );
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

/// The lines under the title of a song row: the artist, then the rating as five small stars below it, so the stars of a list line up. Rows without a rating keep the room of the stars with [reserveStars], so every row of a list where one song is rated has the same height. Without [artist], the stars go right below the title.
class TrackSubtitle extends StatelessWidget {
  const TrackSubtitle(
    this.artist, {
    super.key,
    this.stars,
    this.reserveStars = false,
    this.starSize = TrackStars.height,
  });

  final String? artist;

  /// The height of the stars.
  final double starSize;

  /// The rating from 0 to 5, or null without stars.
  final int? stars;

  /// Keeps the line of the stars when the song has none.
  final bool reserveStars;

  /// Whether the row shows stars.
  static bool showsStars(int? stars) => (stars ?? 0) > 0;

  @override
  Widget build(BuildContext context) {
    final starsLine = showsStars(stars)
        ? TrackStars(stars!, size: starSize)
        : reserveStars
        ? SizedBox(height: starSize)
        : null;
    if (artist == null) return starsLine ?? const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TrackArtist(artist),
        if (starsLine != null)
          Padding(padding: const EdgeInsets.only(top: 2), child: starsLine),
      ],
    );
  }
}

/// The artist of a song, on the second line of its row.
class TrackArtist extends StatelessWidget {
  const TrackArtist(this.artist, {super.key});

  final String? artist;

  @override
  Widget build(BuildContext context) => Text(
    artist ?? '',
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(color: context.muted),
  );
}

/// Five small stars, filled up to [stars]. They only display; the menu of the song changes the rating.
class TrackStars extends StatelessWidget {
  const TrackStars(this.stars, {super.key, this.size = height});

  final int stars;

  /// The height of each star.
  final double size;

  /// The usual height of the stars, which a row without them keeps when its neighbours have them.
  static const double height = 12;

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
            size: size,
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
    return SongsDraggable(
      songs: DraggedSongs(
        album.name,
        () async => (await ref.read(repositoryProvider)!.album(album.id)).songs,
      ),
      child: Pressable(
        child: SizedBox(
          width: width,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => context.push('/album/${album.id}'),
            onLongPress: () => showAlbumActions(context, ref, album),
            onSecondaryTap: () => showAlbumActions(context, ref, album),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                HoverPlay(
                  tooltip: 'Play ${album.name}',
                  onPlay: () async => playFrom(
                    ref,
                    (await ref.read(repositoryProvider)!.album(album.id)).songs,
                    0,
                  ),
                  child: Stack(
                    children: [
                      Artwork(album.coverArt, size: width),
                      if (pin.pinned) CardDownloadBadge(pin),
                    ],
                  ),
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
  artists: album.artists,
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

/// The download state in the top-right corner of a cover, the same on album and playlist cards.
class CardDownloadBadge extends StatelessWidget {
  const CardDownloadBadge(this.pin, {super.key});

  final PinState pin;

  @override
  Widget build(BuildContext context) => Positioned(
    top: 6,
    right: 6,
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
          onSecondaryTap: () => showPlaylistActions(context, ref, playlist),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              HoverPlay(
                tooltip: 'Play ${playlist.name}',
                onPlay: () async => playFrom(
                  ref,
                  (await ref.read(repositoryProvider)!.playlist(playlist.id))
                      .entries,
                  0,
                  playlistId: playlist.id,
                ),
                child: Stack(
                  children: [
                    PlaylistArtwork(playlist, size: width, radius: 6),
                    if (pin.pinned) CardDownloadBadge(pin),
                  ],
                ),
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
    void actions() => showItemActions(
      context,
      ref,
      kind: PinKind.artist,
      id: artist.id,
      title: artist.name,
      coverArt: artist.coverArt,
      starred: artist.starred,
      mix: () => ref.read(repositoryProvider)!.radio(artistId: artist.id),
      artists: [(id: artist.id, name: artist.name)],
    );
    return SecondaryTap(
      onTap: actions,
      child: ListTile(
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
          artist.albumCount > 0
              ? countOf(artist.albumCount, 'album')
              : 'Artist',
          style: TextStyle(color: context.muted),
        ),
        trailing: DownloadIcon(displayForPin(pin), progress: pin.fraction),
        onTap: () => context.push('/artist/${artist.id}'),
        onLongPress: actions,
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

/// The label at the top of the title cover of [playlist]: "Playlist" and its owner.
String playlistLabel(Playlist playlist) =>
    ['Playlist', ?playlist.owner].join(' · ');

/// The cover of a playlist. With [titleCoversProvider] on, its name in large type over the colours of its albums. Otherwise the cover from the server, or without one, a 2×2 mosaic of its first four albums, or the cover of its first album when it has fewer. The mosaic needs the playlist to have been opened or downloaded once.
class PlaylistArtwork extends ConsumerWidget {
  const PlaylistArtwork(this.playlist, {super.key, this.size, this.radius = 4});

  final Playlist playlist;
  final double? size;
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final covers =
        ref.watch(playlistCoversProvider(playlist.id)).value ?? const [];
    if (ref.watch(titleCoversProvider)) {
      return TitleCover(
        playlist.name,
        seed: playlist.id,
        artIds: [?playlist.coverArt, ...covers],
        label: playlistLabel(playlist),
        detail: countOf(playlist.songCount, 'song'),
        size: size,
        radius: radius,
      );
    }
    if (playlist.coverArt != null) {
      return Artwork(
        playlist.coverArt,
        size: size,
        radius: radius,
        icon: Icons.queue_music,
      );
    }
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
    return SecondaryTap(
      onTap: () => showPlaylistActions(context, ref, playlist),
      child: ListTile(
        leading: PlaylistArtwork(playlist, size: 52),
        title: Text(
          playlist.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          countOf(playlist.songCount, 'song'),
          style: TextStyle(color: context.muted),
        ),
        trailing: DownloadIcon(displayForPin(pin), progress: pin.fraction),
        onTap: () => context.push('/playlist/${playlist.id}'),
        onLongPress: () => showPlaylistActions(context, ref, playlist),
      ),
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
  cover: PlaylistArtwork(playlist, size: 48),
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

/// Calls [onTap] on a right click, for the menus that a long press opens on a touch screen.
class SecondaryTap extends StatelessWidget {
  const SecondaryTap({super.key, required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      GestureDetector(onSecondaryTap: onTap, child: child);
}

/// Shows a play button over [child] while the mouse is over it. A touch screen has no hover, so it never shows there.
class HoverPlay extends StatefulWidget {
  const HoverPlay({
    super.key,
    required this.onPlay,
    required this.tooltip,
    required this.child,
  });

  final Future<void> Function() onPlay;
  final String tooltip;
  final Widget child;

  @override
  State<HoverPlay> createState() => _HoverPlayState();
}

class _HoverPlayState extends State<HoverPlay> {
  bool _hover = false;

  void _set(bool hover) {
    if (_hover != hover) setState(() => _hover = hover);
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => _set(true),
    onExit: (_) => _set(false),
    child: Stack(
      children: [
        widget.child,
        if (_hover)
          Positioned(
            right: 8,
            bottom: 8,
            child: IconButton.filled(
              tooltip: widget.tooltip,
              style: IconButton.styleFrom(
                backgroundColor: context.colors.primary,
                foregroundColor: context.colors.onPrimary,
              ),
              icon: const Icon(Icons.play_arrow_rounded),
              onPressed: () => runPlayback(widget.onPlay),
            ),
          ),
      ],
    ),
  );
}

/// Songs dragged with the mouse, which a playlist of the sidebar takes.
class DraggedSongs {
  const DraggedSongs(this.label, this.tracks);

  /// What the pointer carries, such as the title of the song or the album.
  final String label;
  final Future<List<Track>> Function() tracks;
}

/// Lets the mouse drag [songs] from [child]. A finger scrolls the list instead, so dragging starts only once a mouse has been over the child; a touch screen sends no hover.
class SongsDraggable extends StatefulWidget {
  const SongsDraggable({super.key, required this.songs, required this.child});

  final DraggedSongs songs;
  final Widget child;

  @override
  State<SongsDraggable> createState() => _SongsDraggableState();
}

class _SongsDraggableState extends State<SongsDraggable> {
  bool _mouse = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) {
      if (!_mouse) setState(() => _mouse = true);
    },
    child: Draggable<DraggedSongs>(
      data: widget.songs,
      maxSimultaneousDrags: _mouse ? null : 0,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Material(
        color: context.colors.inverseSurface,
        borderRadius: BorderRadius.circular(8),
        elevation: 6,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.music_note,
                size: 18,
                color: context.colors.onInverseSurface,
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 240),
                child: Text(
                  widget.songs.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: context.colors.onInverseSurface),
                ),
              ),
            ],
          ),
        ),
      ),
      child: widget.child,
    ),
  );
}

/// A column of a song row in a wide window: muted text that opens [path] on a click.
class _Column extends StatelessWidget {
  const _Column(this.text, {this.path});

  final String? text;
  final String? path;

  @override
  Widget build(BuildContext context) {
    final label = Text(
      text ?? '',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(color: context.muted, fontSize: 14),
    );
    if (path == null || text == null) return label;
    return Align(
      alignment: Alignment.centerLeft,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(onTap: () => context.push(path!), child: label),
      ),
    );
  }
}
