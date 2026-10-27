import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/subsonic/models.dart';
import '../../ui/widgets/tiles.dart';
import '../../app/experience.dart';
import '../cast/output_sheet.dart';
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
  return playlists.take(20).toList();
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
                    title: setting.shelf.label,
                    items: ref.watch(downloadedAlbumsProvider),
                    builder: (albums, loading) =>
                        AlbumShelf(albums, loading: loading),
                  ),
                  HomeShelf.playlists => _Shelf(
                    title: setting.shelf.label,
                    items: ref.watch(recentPlaylistsProvider),
                    builder: (playlists, loading) =>
                        PlaylistShelf(playlists, loading: loading),
                  ),
                  _ => _Shelf(
                    title: setting.shelf.label,
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

class _Shelf<T> extends StatelessWidget {
  const _Shelf({
    required this.title,
    required this.items,
    required this.builder,
  });

  final String title;
  final AsyncValue<List<T>> items;
  final Widget Function(List<T> items, bool loading) builder;

  @override
  Widget build(BuildContext context) {
    final list = items.value ?? <T>[];
    if (items.hasValue && list.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        builder(list, items.isLoading && list.isEmpty),
      ],
    );
  }
}
