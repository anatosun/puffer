import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/playback_providers.dart';
import '../../app/providers.dart';
import '../../data/subsonic/models.dart';
import '../../playback/playback_controller.dart';
import '../../ui/messages.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/artwork.dart';
import '../../ui/widgets/playing_bars.dart';
import '../../ui/widgets/item_actions.dart';
import '../../downloads/download_manager.dart';
import '../../ui/widgets/download_indicator.dart';
import '../../ui/widgets/tiles.dart';
import '../collection/album_page.dart';
import '../collection/artist_page.dart';
import '../collection/playlist_edit.dart';

/// The Subsonic cover when [coverArt] is known, otherwise the Music Assistant image at [imageUrl].
class NowPlayingArtwork extends ConsumerWidget {
  const NowPlayingArtwork(
    this.coverArt,
    this.imageUrl, {
    required this.size,
    this.radius = 6,
    super.key,
  });

  final String? coverArt;
  final Uri? imageUrl;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (coverArt != null || imageUrl == null) {
      return Artwork(coverArt, size: size, radius: radius);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image(
        image: CachedNetworkImageProvider(imageUrl.toString()),
        width: size,
        height: size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => Artwork(null, size: size, radius: 0),
      ),
    );
  }
}

enum BelowTab {
  played('Played'),
  queue('Queue'),
  album('Album'),
  artist('Artist'),
  about('About'),
  similar('Similar');

  const BelowTab(this.label);

  final String label;
}

class BelowTabNotifier extends Notifier<BelowTab> {
  @override
  BelowTab build() => BelowTab.queue;

  void set(BelowTab tab) => state = tab;
}

/// The tab below the player that shows. It goes back to the queue whenever the player opens, since it lives only while the player shows.
final belowTabProvider =
    NotifierProvider.autoDispose<BelowTabNotifier, BelowTab>(
      BelowTabNotifier.new,
    );

/// Switches to the queue tab and scrolls down to it, from the "Up next" row or a swipe up on the artwork.
void showQueue(BuildContext context, ProviderContainer container) {
  container.read(belowTabProvider.notifier).set(BelowTab.queue);
  final position = Scrollable.maybeOf(context)?.position;
  position?.animateTo(
    position.viewportDimension,
    duration: const Duration(milliseconds: 400),
    curve: Curves.easeOutCubic,
  );
}

/// What the tabs other than the queue show for the current song, from the server. Offline, or before the server answers, they are empty and their tabs hide.
typedef _Below = ({
  Track? track,
  Album? album,
  List<Album> artistAlbums,
  ArtistInfo? info,
});

_Below _below(WidgetRef ref) {
  final track = ref.watch(nowPlayingProvider.select((s) => s.value?.track));
  if (track == null || ref.watch(isOfflineProvider)) {
    return (track: track, album: null, artistAlbums: const [], info: null);
  }
  final album = track.albumId == null
      ? null
      : ref.watch(albumProvider(track.albumId!)).value;
  final artist = track.artistId == null
      ? null
      : ref.watch(artistProvider(track.artistId!)).value;
  final info = track.artistId == null
      ? null
      : ref.watch(artistInfoProvider(track.artistId!)).value;
  return (
    track: track,
    album: album,
    // The album that plays has its own tab.
    artistAlbums: [
      for (final a in artist?.albums ?? const <Album>[])
        if (a.id != track.albumId) a,
    ],
    info: info,
  );
}

List<BelowTab> _available(_Below below, {required bool played}) => [
  if (played) BelowTab.played,
  BelowTab.queue,
  if ((below.album?.songs.length ?? 0) > 1) BelowTab.album,
  if (below.artistAlbums.isNotEmpty) BelowTab.artist,
  if (below.info?.biography != null || below.info?.imageUrl != null)
    BelowTab.about,
  if (below.info?.similarArtists.isNotEmpty ?? false) BelowTab.similar,
];

/// Whether songs before the current one are in the queue, for the "Played" tab.
/// Whether the Played tab has something to show: songs before the current one, or queues played before this one.
bool _hasPlayed(WidgetRef ref) =>
    (ref.watch(nowPlayingProvider.select((s) => s.value?.index)) ?? 0) > 0 ||
    (ref.watch(pastQueuesProvider).value?.isNotEmpty ?? false);

/// The tab bar below the player, with instant mix at its end.
class BelowTabBar extends ConsumerWidget {
  const BelowTabBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final below = _below(ref);
    final tabs = _available(below, played: _hasPlayed(ref));
    final selected = ref.watch(belowTabProvider);
    final index = math.max(0, tabs.indexOf(selected));
    final track = below.track;
    // An instant mix asks the server for songs that sound alike, so it needs the connection and the `sonicSimilarity` extension.
    final mix =
        track != null &&
        ref.watch(canMixProvider) &&
        !ref.watch(isOfflineProvider);
    return Padding(
      // The right padding matches the player's, so instant mix sits under the speaker button.
      padding: const EdgeInsets.only(top: 8, left: 12, right: 24),
      child: Row(
        children: [
          Expanded(
            child: DefaultTabController(
              // A new controller when the tabs change with the song, or when another control picks a tab, such as "Up next" picking the queue.
              key: ValueKey('${tabs.join()}$index'),
              length: tabs.length,
              initialIndex: index,
              // Six tabs do not fit a narrow phone at a readable size, so the bar scrolls sideways; the queue, second, shows from the start.
              child: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelPadding: const EdgeInsets.symmetric(horizontal: 12),
                dividerColor: Colors.transparent,
                tabs: [for (final t in tabs) Tab(text: t.label)],
                onTap: (i) => ref.read(belowTabProvider.notifier).set(tabs[i]),
              ),
            ),
          ),
          if (mix)
            IconButton(
              tooltip: 'Instant mix',
              color: context.muted,
              icon: const Icon(Icons.radio),
              onPressed: () => runPlayback(() async {
                final tracks = await ref
                    .read(repositoryProvider)!
                    .instantMix(track);
                if (tracks.length < 2) {
                  showMessage('The server found no similar songs');
                  return;
                }
                await ref.read(playbackControllerProvider).playTracks(tracks);
              }),
            ),
        ],
      ),
    );
  }
}

/// The content of the selected tab below the player.
class BelowContent extends ConsumerWidget {
  const BelowContent({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final below = _below(ref);
    final tabs = _available(below, played: _hasPlayed(ref));
    final selected = ref.watch(belowTabProvider);
    final tab = tabs.contains(selected) ? selected : BelowTab.queue;

    // Links leave the player for the page they open.
    void open(String path) {
      final router = GoRouter.of(context);
      Navigator.pop(context);
      router.push(path);
    }

    switch (tab) {
      case BelowTab.played:
        return const _QueueSliver(played: true);
      case BelowTab.queue:
        return const _QueueSliver();
      case BelowTab.album:
        final album = below.album!;
        final songs = album.songs;
        return SliverList.list(
          children: [
            ListTile(
              title: Text(
                album.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              onTap: () => open('/album/${album.id}'),
              // The queue becomes the album, carrying on from the song and position that play.
              trailing: FilledButton.tonalIcon(
                icon: const Icon(Icons.queue_music),
                label: const Text('Play album'),
                onPressed: () => runPlayback(() async {
                  final np = ref.read(nowPlayingProvider).value;
                  final at = songs.indexWhere((t) => t.id == np?.track?.id);
                  final controller = ref.read(playbackControllerProvider);
                  await controller.playTracks(songs, index: math.max(0, at));
                  final position = np?.positionNow() ?? Duration.zero;
                  if (at >= 0 && position > const Duration(seconds: 1)) {
                    await controller.seek(position);
                  }
                }),
              ),
            ),
            for (var i = 0; i < songs.length; i++)
              TrackTile(
                tracks: songs,
                index: i,
                showArtwork: false,
                showNumber: true,
              ),
          ],
        );
      case BelowTab.artist:
        final albums = below.artistAlbums;
        return SliverList.builder(
          itemCount: albums.length,
          itemBuilder: (context, i) {
            final album = albums[i];
            return ListTile(
              leading: Artwork(album.coverArt, size: 52, radius: 4),
              title: Text(
                album.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              // Always a second line and the download state, as on the other album, playlist and artist rows.
              subtitle: Text(
                [
                  if (album.year != null) '${album.year}',
                  countOf(album.songCount, 'song'),
                ].join(' · '),
                style: TextStyle(color: context.muted),
              ),
              trailing: PinDownloadIcon(PinKind.album, album.id),
              onTap: () => open('/album/${album.id}'),
            );
          },
        );
      case BelowTab.about:
        final info = below.info!;
        final track = below.track!;
        return SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // A small photo of the artist with the name, which opens the artist page.
              ListTile(
                leading: ClipOval(
                  child: SizedBox.square(
                    dimension: 56,
                    child: info.imageUrl == null
                        ? const Artwork(null, size: 56, icon: Icons.person)
                        : CachedNetworkImage(
                            imageUrl: info.imageUrl!,
                            fit: BoxFit.cover,
                            errorWidget: (_, _, _) => const Artwork(
                              null,
                              size: 56,
                              icon: Icons.person,
                            ),
                          ),
                  ),
                ),
                title: Text(
                  track.artist ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                trailing: Icon(Icons.chevron_right, color: context.faint),
                onTap: () => open('/artist/${track.artistId}'),
              ),
              if (info.biography case final biography?) Biography(biography),
            ],
          ),
        );
      case BelowTab.similar:
        final similar = below.info!.similarArtists;
        return SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          sliver: SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 96,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.78,
            ),
            itemCount: similar.length,
            itemBuilder: (context, i) {
              final artist = similar[i];
              return InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => open('/artist/${artist.id}'),
                child: LayoutBuilder(
                  builder: (context, box) => Column(
                    children: [
                      ClipOval(
                        // The portrait leaves room for one line of name under it.
                        child: Artwork(
                          artist.coverArt,
                          size: math.max(
                            0.0,
                            math.min(box.maxWidth, box.maxHeight - 28),
                          ),
                          radius: 0,
                          icon: Icons.person,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        artist.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
    }
  }
}

/// The queue: played tracks dimmed, the current one marked, upcoming ones below. Pressing and dragging a track moves it; swiping it away removes it.
class _QueueSliver extends ConsumerStatefulWidget {
  const _QueueSliver({this.played = false});

  /// The songs played before the current one, most recent first; otherwise the current song and those after it.
  final bool played;

  @override
  ConsumerState<_QueueSliver> createState() => _QueueSliverState();
}

bool _sameOrder(List<QueueEntry> a, List<QueueEntry> b) =>
    a.length == b.length &&
    Iterable.generate(a.length).every((i) => a[i].id == b[i].id);

class _QueueSliverState extends ConsumerState<_QueueSliver> {
  /// The order after a move, shown until the output reports the new queue.
  List<QueueEntry>? _moved;
  List<QueueEntry>? _movedFrom;

  @override
  Widget build(BuildContext context) {
    final np = ref.watch(nowPlayingProvider).value;
    final reported = np?.queue ?? const <QueueEntry>[];
    if (_movedFrom != null && !_sameOrder(reported, _movedFrom!)) {
      _moved = null;
      _movedFrom = null;
    }
    final queue = _moved ?? reported;
    final current = np?.index ?? 0;
    final controller = ref.read(playbackControllerProvider);
    final showStars = ref.watch(trackStarsProvider);
    final showHearts = ref.watch(trackHeartsProvider);
    final ratings = ref.watch(ratingOverridesProvider);

    /// A row of the queue. With [dragIndex], it carries a handle that drags it to another place, as in editable playlists.
    /// With [handleSpace], a row without a handle keeps the space of one, so its icons line up with those of the rows that have one.
    Widget tile(
      int i, {
      required bool removable,
      int? dragIndex,
      bool handleSpace = false,
    }) {
      final item = queue[i];
      final playing = i == np?.index;
      // The library knows a song's rating and heart, which the queue entry does not carry.
      // Entries of Music Assistant that are no Subsonic song have no track ID; their columns stay empty.
      final trackId = item.trackId;
      final known = (showStars || showHearts) && trackId != null
          ? ref.watch(queueTrackProvider(trackId)).value
          : null;
      final stars = showStars ? ratings[trackId] ?? known?.rating : null;
      final row = ListTile(
        leading: Stack(
          alignment: Alignment.center,
          children: [
            NowPlayingArtwork(
              item.coverArt,
              item.imageUrl,
              size: 44,
              radius: 4,
            ),
            if (playing) ...[
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              PlayingBars(playing: np?.playing ?? false, color: Colors.white),
            ],
          ],
        ),
        selected: playing,
        title: TrackTitle(item.title),
        subtitle: TrackSubtitle(item.artist, stars: stars),
        isThreeLine: TrackSubtitle.showsStars(stars),
        // The same columns on every row: download state, heart, drag handle.
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            trackId == null
                ? const DownloadIcon(DownloadDisplay.none, size: 16)
                : TrackDownloadIcon(trackId),
            if (showHearts)
              TrackHeart(trackId ?? '', starred: known?.starred ?? false),
            if (dragIndex != null)
              ReorderableDragStartListener(
                index: dragIndex,
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Icon(Icons.drag_handle, color: context.faint),
                ),
              )
            else if (handleSpace)
              const SizedBox(width: 8 + 24),
          ],
        ),
        onTap: playing ? null : () => controller.skipTo(i),
      );
      if (!removable) return row;
      return Dismissible(
        key: ValueKey('dismiss-${item.id}-$i'),
        direction: DismissDirection.endToStart,
        onDismissed: (_) => controller.removeAt(i),
        background: Container(
          color: Colors.red.shade900,
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 16),
          child: const Icon(Icons.delete, color: Colors.white),
        ),
        child: row,
      );
    }

    if (widget.played) {
      // Most recent first; a tap plays the song again from the queue. The queues played before this one follow.
      return SliverMainAxisGroup(
        slivers: [
          SliverList.builder(
            itemCount: math.min(current, queue.length),
            itemBuilder: (context, j) => tile(current - 1 - j, removable: true),
          ),
          const _PastQueues(),
        ],
      );
    }

    // The current song comes first and stays there; the songs after it can be moved and removed.
    final start = math.min(current, queue.length);
    final count = queue.length - start;
    final songIds = [for (final e in queue) ?e.trackId];
    final canSave = songIds.isNotEmpty && !ref.watch(isOfflineProvider);
    final list = SliverReorderableList(
      itemCount: count,
      onReorderItem: (from, to) {
        if (from == 0) return;
        final target = math.max(1, to);
        final moved = [...queue];
        moved.insert(start + target, moved.removeAt(start + from));
        setState(() {
          _movedFrom = reported;
          _moved = moved;
        });
        controller.move(start + from, start + target);
      },
      itemBuilder: (context, j) {
        final i = start + j;
        final item = queue[i];
        if (j == 0) {
          return KeyedSubtree(
            key: ValueKey('${item.id}-$i'),
            child: tile(i, removable: false, handleSpace: true),
          );
        }
        return ReorderableDelayedDragStartListener(
          key: ValueKey('${item.id}-$i'),
          index: j,
          child: tile(i, removable: true, dragIndex: j),
        );
      },
    );
    if (!canSave) return list;
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: TextButton.icon(
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save as playlist'),
                // The whole queue, the songs played included, in its order.
                onPressed: () => createPlaylistFrom(context, ref, songIds),
              ),
            ),
          ),
        ),
        list,
      ],
    );
  }
}

/// The queues played before the current one, most recent first. A tap plays one again from where it was.
class _PastQueues extends ConsumerWidget {
  const _PastQueues();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queues = ref.watch(pastQueuesProvider).value ?? const [];
    if (queues.isEmpty) return const SliverToBoxAdapter();
    return SliverList.list(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(
            'Earlier queues',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        for (final (i, queue) in queues.indexed)
          ListTile(
            leading: NowPlayingArtwork(
              queue.tracks[queue.index].coverArt,
              null,
              size: 44,
              radius: 4,
            ),
            title: Text(
              queue.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${countOf(queue.tracks.length, 'song')} · stopped at ${queue.tracks[queue.index].title}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: ref.watch(isOfflineProvider)
                ? null
                : IconButton(
                    tooltip: 'Save as playlist',
                    icon: const Icon(Icons.save_outlined),
                    onPressed: () => createPlaylistFrom(context, ref, [
                      for (final t in queue.tracks) t.id,
                    ], initialName: queue.label),
                  ),
            onTap: () => runPlayback(() => ref.read(playPastQueueProvider)(i)),
          ),
      ],
    );
  }
}
