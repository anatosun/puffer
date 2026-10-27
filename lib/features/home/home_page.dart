import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../data/subsonic/models.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/tiles.dart';
import '../../app/experience.dart';
import '../cast/output_sheet.dart';
import '../library/album_lists.dart';
import '../library/downloaded.dart';

final albumListProvider = FutureProvider.autoDispose
    .family<List<Album>, String>((ref, type) async {
      final repository = ref.watch(repositoryProvider);
      ref.watch(isOfflineProvider);
      if (repository == null) return const [];
      return repository.albumList(type, size: 20);
    });

/// Playlists, most recently changed first.
final recentPlaylistsProvider = FutureProvider.autoDispose<List<Playlist>>((
  ref,
) async {
  final repository = ref.watch(repositoryProvider);
  ref.watch(isOfflineProvider);
  if (repository == null) return const [];
  final playlists = [...await repository.playlists()];
  playlists.sort((a, b) => (b.changed ?? '').compareTo(a.changed ?? ''));
  return playlists;
});

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(startupSyncProvider);
    final offline = ref.watch(isOfflineProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text('Home', style: Theme.of(context).textTheme.headlineMedium),
        actions: [
          if (offline)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Chip(
                avatar: Icon(Icons.cloud_off, size: 16),
                label: Text('Offline'),
                visualDensity: VisualDensity.compact,
              ),
            ),
          const OutputButton(),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(albumListProvider);
          ref.invalidate(recentPlaylistsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            // Offline, only downloaded albums can play.
            for (final setting in ref.watch(homeShelvesProvider))
              if (setting.visible &&
                  (!offline || setting.shelf == HomeShelf.downloaded))
                switch (setting.shelf) {
                  HomeShelf.downloaded => _Shelf(
                    shelf: setting.shelf,
                    items: ref.watch(downloadedAlbumsProvider),
                    builder: (albums, loading) =>
                        AlbumShelf(albums, loading: loading),
                  ),
                  HomeShelf.playlists => _Shelf(
                    shelf: setting.shelf,
                    items: ref.watch(recentPlaylistsProvider),
                    builder: (playlists, loading) => PlaylistShelf(
                      playlists.take(20).toList(),
                      loading: loading,
                    ),
                  ),
                  _ => _Shelf(
                    shelf: setting.shelf,
                    items: ref.watch(
                      albumListProvider(setting.shelf.albumList!),
                    ),
                    builder: (albums, loading) =>
                        AlbumShelf(albums, loading: loading),
                  ),
                },
          ],
        ),
      ),
    );
  }
}

/// A shelf of Home. Its title opens the full list.
class _Shelf<T> extends StatelessWidget {
  const _Shelf({
    required this.shelf,
    required this.items,
    required this.builder,
  });

  final HomeShelf shelf;
  final AsyncValue<List<T>> items;
  final Widget Function(List<T> items, bool loading) builder;

  @override
  Widget build(BuildContext context) {
    final list = items.value ?? <T>[];
    if (items.hasValue && list.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => context.push('/home/${shelf.name}'),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 8, 10),
            child: Row(
              children: [
                Text(
                  shelf.label,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Icon(Icons.chevron_right, color: context.faint),
              ],
            ),
          ),
        ),
        builder(list, items.isLoading && list.isEmpty),
      ],
    );
  }
}

/// Every item of a Home shelf.
class ShelfPage extends ConsumerWidget {
  const ShelfPage(this.shelf, {super.key});

  final HomeShelf shelf;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text(shelf.label), actions: const [OutputButton()]),
      body: switch (shelf) {
        HomeShelf.downloaded => AsyncList(
          ref.watch(downloadedAlbumsProvider),
          (albums) => AlbumGrid(albums),
          empty: 'No downloaded albums',
        ),
        HomeShelf.playlists => AsyncList(
          ref.watch(recentPlaylistsProvider),
          (playlists) => ListView.builder(
            itemCount: playlists.length,
            itemBuilder: (_, i) => PlaylistTile(playlists[i]),
          ),
          onRetry: () => ref.invalidate(recentPlaylistsProvider),
        ),
        _ => PagedAlbumGrid(shelf.albumList!),
      },
    );
  }
}
