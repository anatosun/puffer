import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/experience.dart';
import '../../app/providers.dart';
import '../../data/subsonic/models.dart';
import '../../downloads/download_manager.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/tiles.dart';
import 'collection_header.dart';

final artistProvider = FutureProvider.autoDispose.family<Artist, String>((
  ref,
  id,
) async {
  ref.watch(isOfflineProvider);
  return ref.watch(repositoryProvider)!.artist(id);
});

/// Every track of the artist, album by album. Albums that cannot be loaded offline are skipped.
final artistTracksProvider = FutureProvider.autoDispose
    .family<List<Track>, String>((ref, id) async {
      final artist = await ref.watch(artistProvider(id).future);
      final repository = ref.watch(repositoryProvider)!;
      final tracks = <Track>[];
      for (final album in artist.albums) {
        try {
          tracks.addAll((await repository.album(album.id)).songs);
        } on Exception {
          // Not cached.
        }
      }
      return tracks;
    });

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
    final photo = info?.imageUrl;
    return ref
        .watch(artistProvider(id))
        .when(
          loading: () => const CollectionPlaceholder(
            body: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => CollectionPlaceholder(
            body: MessageView(
              '$e',
              onRetry: () => ref.invalidate(artistProvider(id)),
            ),
          ),
          data: (artist) {
            final albums = [...artist.albums]
              ..sort((a, b) => (b.year ?? 0).compareTo(a.year ?? 0));
            return Scaffold(
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
                    details: '${albums.length} albums',
                    tracks: tracks,
                    pinKind: PinKind.artist,
                    pinId: artist.id,
                    circular: true,
                    trailing: StarButton(
                      starred: artist.starred,
                      artistId: artist.id,
                    ),
                    slivers: [
                      if (info?.biography case final biography?)
                        SliverToBoxAdapter(child: _Biography(biography)),
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
                          itemCount: albums.length,
                          itemBuilder: (context, i) =>
                              AlbumCard(albums[i], width: width),
                        ),
                      ),
                    ],
                  );
                },
              ),
            );
          },
        );
  }
}

/// The biography in three lines; a tap shows all of it.
class _Biography extends StatefulWidget {
  const _Biography(this.text);

  final String text;

  @override
  State<_Biography> createState() => _BiographyState();
}

class _BiographyState extends State<_Biography> {
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
