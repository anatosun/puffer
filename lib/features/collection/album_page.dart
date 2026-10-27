import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../data/subsonic/models.dart';
import '../../downloads/download_manager.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/shimmer.dart';
import '../../ui/widgets/tiles.dart';
import 'collection_header.dart';

final albumProvider = FutureProvider.autoDispose.family<Album, String>((
  ref,
  id,
) async {
  ref.watch(isOfflineProvider);
  return ref.watch(repositoryProvider)!.album(id);
});

class AlbumPage extends ConsumerWidget {
  const AlbumPage(this.id, {super.key});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(albumProvider(id))
        .when(
          loading: () => const CollectionPlaceholder(body: ListPlaceholder()),
          error: (e, _) => CollectionPlaceholder(
            body: MessageView(
              '$e',
              onRetry: () => ref.invalidate(albumProvider(id)),
            ),
          ),
          data: (album) {
            final songs = album.songs;
            final discs = groupBy(songs, (Track t) => t.discNumber);
            return Scaffold(
              body: CollectionView(
                coverArt: album.coverArt,
                title: album.name,
                subtitle: album.artist,
                onSubtitleTap: album.artistId == null
                    ? null
                    : () => context.push('/artist/${album.artistId}'),
                details: [
                  album.genre,
                  album.year,
                  '${songs.length} songs',
                  formatDuration(album.duration),
                ].nonNulls.join(' · '),
                tracks: songs,
                pinKind: PinKind.album,
                pinId: album.id,
                trailing: StarButton(starred: album.starred, albumId: album.id),
                slivers: [
                  SliverList.list(
                    children: [
                      for (final disc in discs.entries) ...[
                        if (discs.length > 1)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                            child: Text(
                              'Disc ${disc.key}',
                              style: TextStyle(
                                color: context.muted,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        for (final track in disc.value)
                          TrackTile(
                            tracks: songs,
                            index: songs.indexOf(track),
                            showArtwork: false,
                            showNumber: true,
                          ),
                      ],
                    ],
                  ),
                ],
              ),
            );
          },
        );
  }
}
