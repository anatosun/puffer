import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/experience.dart';
import '../../app/providers.dart';
import '../../data/subsonic/models.dart';
import '../../downloads/download_manager.dart';
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

class ArtistPage extends ConsumerWidget {
  const ArtistPage(this.id, {super.key});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracks = ref.watch(artistTracksProvider(id)).value ?? const [];
    return TransparentAppBarScaffold(
      body: ref
          .watch(artistProvider(id))
          .when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => MessageView(
              '$e',
              onRetry: () => ref.invalidate(artistProvider(id)),
            ),
            data: (artist) {
              final albums = [...artist.albums]
                ..sort((a, b) => (b.year ?? 0).compareTo(a.year ?? 0));
              return LayoutBuilder(
                builder: (context, constraints) {
                  final columns = ref
                      .watch(coverSizeProvider)
                      .columns(constraints.maxWidth);
                  final width =
                      (constraints.maxWidth - 16 * (columns + 1)) / columns;
                  return CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(
                        child: CollectionHeader(
                          coverArt: artist.coverArt,
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
                          itemCount: albums.length,
                          itemBuilder: (context, i) =>
                              AlbumCard(albums[i], width: width),
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
    );
  }
}
