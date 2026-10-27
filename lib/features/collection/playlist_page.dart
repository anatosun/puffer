import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/subsonic/models.dart';
import '../../downloads/download_manager.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/tiles.dart';
import 'collection_header.dart';

final playlistProvider = FutureProvider.autoDispose.family<Playlist, String>((
  ref,
  id,
) async {
  ref.watch(isOfflineProvider);
  return ref.watch(repositoryProvider)!.playlist(id);
});

class PlaylistPage extends ConsumerWidget {
  const PlaylistPage(this.id, {super.key});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TransparentAppBarScaffold(
      body: ref
          .watch(playlistProvider(id))
          .when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => MessageView(
              '$e',
              onRetry: () => ref.invalidate(playlistProvider(id)),
            ),
            data: (playlist) {
              final entries = playlist.entries;
              return ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: entries.length + 1,
                itemBuilder: (context, i) => i == 0
                    ? CollectionHeader(
                        coverArt: playlist.coverArt,
                        title: playlist.name,
                        subtitle: playlist.owner,
                        details:
                            '${entries.length} songs · ${formatDuration(playlist.duration)}',
                        tracks: entries,
                        pinKind: PinKind.playlist,
                        pinId: playlist.id,
                      )
                    : TrackTile(tracks: entries, index: i - 1),
              );
            },
          ),
    );
  }
}
