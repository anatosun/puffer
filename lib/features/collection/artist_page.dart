import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/library_repository.dart';
import '../../app/experience.dart';
import '../../app/providers.dart';
import '../../data/subsonic/models.dart';
import '../../downloads/download_manager.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/shimmer.dart';
import '../../ui/widgets/tiles.dart';
import '../../ui/widgets/star_button.dart';
import 'collection_header.dart';
import '../../ui/widgets/backdrop.dart';

/// An artist with its albums: from the cache at once when there is one, then from the server.
final artistProvider = StreamProvider.autoDispose.family<Artist, String>((
  ref,
  id,
) {
  ref.watch(isOfflineProvider);
  final repository = ref.watch(repositoryProvider)!;
  return cachedThenFresh(
    repository.cachedArtist(id),
    () => repository.artist(id),
  );
});

/// The albums the page of the artist shows, newest first. On octo-fiesta the albums of external providers wait for "More", unless the artist itself comes from one.
final artistAlbumsProvider = Provider.autoDispose
    .family<AsyncValue<({List<Album> items, bool more})>, String>((ref, id) {
      final showExternal =
          isExternalId(id) || ref.watch(externalShownProvider('artist:$id'));
      return ref.watch(artistProvider(id)).whenData((artist) {
        final shown = shownItems(
          artist.albums,
          (a) => a.id,
          showExternal: showExternal,
        );
        shown.items.sort((a, b) => (b.year ?? 0).compareTo(a.year ?? 0));
        return shown;
      });
    });

/// Every track of the albums the page shows, album by album: first the cached albums, read in one query, then the albums from the server, a few requests at a time. Albums that cannot be loaded are skipped.
final artistTracksProvider = StreamProvider.autoDispose
    .family<List<Track>, String>((ref, id) async* {
      // Only the album IDs, so the artist arriving from the server after the cache reloads nothing when its albums are the same.
      final key = ref.watch(
        artistAlbumsProvider(id)
            .select((v) => v.value?.items.map((a) => a.id).join('\n')),
      );
      if (key == null) return;
      final repository = ref.watch(repositoryProvider)!;
      final ids = key.isEmpty ? const <String>[] : key.split('\n');
      List<Track> tracksOf(Map<String, Album> byId) => [
        for (final id in ids) ...?byId[id]?.songs,
      ];
      final cached = await repository.cachedAlbums(ids);
      if (cached.isNotEmpty) yield tracksOf(cached);
      if (ref.read(isOfflineProvider)) {
        if (cached.isEmpty) yield const [];
        return;
      }
      yield tracksOf({...cached, ...await repository.albums(ids)});
    });

/// The most played songs of the artist, on servers with the `topSongsByArtistId` extension. The page shows [shownTopSongs] of them, and playing one carries on through the rest. Empty without the extension, offline, and when the request fails.
final artistTopSongsProvider = FutureProvider.autoDispose
    .family<List<Track>, String>((ref, id) async {
      if (!ref.watch(hasTopSongsProvider) || ref.watch(isOfflineProvider)) {
        return const [];
      }
      try {
        return await ref.watch(repositoryProvider)!.topSongs(id, count: 20);
      } on Exception {
        return const [];
      }
    });

/// The number of top songs the artist page lists.
const shownTopSongs = 5;

final artistInfoProvider = FutureProvider.autoDispose
    .family<ArtistInfo?, String>((ref, id) async {
      try {
        return await ref.watch(repositoryProvider)?.artistInfo(id);
      } on Exception {
        return null;
      }
    });

class ArtistPage extends ConsumerWidget {
  const ArtistPage(this.id, {super.key});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracks = ref.watch(artistTracksProvider(id)).value ?? const [];
    final info = ref.watch(artistInfoProvider(id)).value;
    final topSongs = ref.watch(artistTopSongsProvider(id)).value ?? const [];
    final photo = info?.imageUrl;
    return ref
        .watch(artistProvider(id))
        .when(
          loading: () => const CollectionPlaceholder(body: ListPlaceholder()),
          error: (e, _) => CollectionPlaceholder(
            body: MessageView(
              '$e',
              onRetry: () => ref.invalidate(artistProvider(id)),
            ),
          ),
          data: (artist) {
            final shown = ref.watch(artistAlbumsProvider(id)).value;
            final albums = shown?.items ?? const <Album>[];
            final groups = <ReleaseKind, List<Album>>{};
            for (final album in albums) {
              (groups[album.releaseKind] ??= []).add(album);
            }
            return Backdrop(
              coverArt: artist.coverArt,
              top: 0.25,
              child: Scaffold(
                backgroundColor: Colors.transparent,
                body: LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = ref
                        .watch(coverSizeProvider)
                        .columns(constraints.maxWidth);
                    final width =
                        (constraints.maxWidth - 16 * (columns + 1)) / columns;
                    return CollectionView(
                      coverArt: artist.coverArt,
                      image: photo == null || ref.watch(isOfflineProvider)
                          ? null
                          : CachedNetworkImageProvider(photo),
                      title: artist.name,
                      details: countOf(albums.length, 'album'),
                      tracks: tracks,
                      pinKind: PinKind.artist,
                      pinId: artist.id,
                      circular: true,
                      trailing: StarButton(
                        starred: artist.starred,
                        artistId: artist.id,
                      ),
                      slivers: [
                        // "More" comes first, where it is in reach without scrolling past the albums.
                        if (shown?.more ?? false)
                          SliverToBoxAdapter(
                            child: MoreButton(
                              onPressed: () => ref
                                  .read(
                                    externalShownProvider('artist:$id')
                                        .notifier,
                                  )
                                  .show(),
                            ),
                          ),
                        if (info?.biography case final biography?)
                          SliverToBoxAdapter(child: Biography(biography)),
                        if (topSongs.isNotEmpty) ...[
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                              child: Text(
                                'Top songs',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ),
                          ),
                          SliverList.builder(
                            itemCount: math.min(shownTopSongs, topSongs.length),
                            itemBuilder: (context, i) =>
                                TrackTile(tracks: topSongs, index: i),
                          ),
                        ],
                        // Albums, EPs, singles, live recordings and compilations each get a section, with a heading when there is more than one.
                        for (final kind in ReleaseKind.values)
                          if (groups[kind] case final group?) ...[
                            if (groups.length > 1)
                              SliverToBoxAdapter(
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    16,
                                    16,
                                    0,
                                  ),
                                  child: Text(
                                    kind.label,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge,
                                  ),
                                ),
                              ),
                            SliverPadding(
                              padding: const EdgeInsets.all(16),
                              sliver: SliverGrid.builder(
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: columns,
                                      mainAxisSpacing: 16,
                                      crossAxisSpacing: 16,
                                      childAspectRatio: width / (width + 48),
                                    ),
                                itemCount: group.length,
                                itemBuilder: (context, i) =>
                                    AlbumCard(group[i], width: width),
                              ),
                            ),
                          ],
                      ],
                    );
                  },
                ),
              ),
            );
          },
        );
  }
}

/// The biography in three lines; a tap shows all of it.
class Biography extends StatefulWidget {
  const Biography(this.text, {super.key});

  final String text;

  @override
  State<Biography> createState() => _BiographyState();
}

class _BiographyState extends State<Biography> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => setState(() => _expanded = !_expanded),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 200),
        alignment: Alignment.topCenter,
        child: Text(
          widget.text,
          maxLines: _expanded ? null : 3,
          overflow: _expanded ? null : TextOverflow.ellipsis,
          style: TextStyle(color: context.muted, height: 1.4),
        ),
      ),
    ),
  );
}
