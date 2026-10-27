import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../data/subsonic/models.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/artwork.dart';
import '../../ui/widgets/tiles.dart';
import '../../app/experience.dart';
import '../cast/output_sheet.dart';
import '../library/album_lists.dart';
import '../library/downloaded.dart';

/// Yields [cached] first when there is one, then [fresh]. A failure of [fresh] after a cached value keeps the cached value.
Stream<T> _cachedThenFresh<T>(
  Future<T?> cached,
  Future<T> Function() fresh,
) async* {
  final first = await cached;
  if (first != null) yield first;
  try {
    yield await fresh();
  } on Exception {
    if (first == null) rethrow;
  }
}

/// The albums of a Home shelf. They stay in memory for the session and show from the cache at start-up while the server answers; pull to refresh reloads them.
final albumListProvider = StreamProvider.family<List<Album>, String>((
  ref,
  type,
) {
  final repository = ref.watch(repositoryProvider);
  ref.watch(isOfflineProvider);
  if (repository == null) return Stream.value(const []);
  return _cachedThenFresh(
    repository.cachedAlbumList(type, size: 20),
    () => repository.albumList(type, size: 20),
  );
});

/// Playlists, most recently changed first, cached like [albumListProvider].
final recentPlaylistsProvider = StreamProvider<List<Playlist>>((ref) {
  final repository = ref.watch(repositoryProvider);
  ref.watch(isOfflineProvider);
  if (repository == null) return Stream.value(const []);
  List<Playlist> sorted(List<Playlist> playlists) =>
      [...playlists]
        ..sort((a, b) => (b.changed ?? '').compareTo(a.changed ?? ''));
  return _cachedThenFresh(
    repository.cachedPlaylists().then((p) => p == null ? null : sorted(p)),
    () async => sorted(await repository.playlists()),
  );
});

String _greeting(DateTime now) => switch (now.hour) {
  >= 5 && < 12 => 'Good morning',
  >= 12 && < 18 => 'Good afternoon',
  _ => 'Good evening',
};

/// A large card for the album played last, coloured by its artwork, with a play button.
class _ContinueListening extends ConsumerWidget {
  const _ContinueListening(this.album);

  final Album album;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = artworkScheme(
      ref,
      album.coverArt,
      Theme.of(context).brightness,
    );
    final tint =
        scheme?.primaryContainer ?? context.colors.surfaceContainerHighest;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Material(
        color: tint,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push('/album/${album.id}'),
          onLongPress: () => showAlbumActions(context, ref, album),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Artwork(album.coverArt, size: 96, radius: 10),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'CONTINUE LISTENING',
                        style: TextStyle(
                          fontSize: 11,
                          letterSpacing: 1,
                          fontWeight: FontWeight.w700,
                          color:
                              scheme?.onPrimaryContainer.withValues(
                                alpha: 0.7,
                              ) ??
                              context.muted,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        album.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: scheme?.onPrimaryContainer,
                            ),
                      ),
                      Text(
                        album.artist ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color:
                              scheme?.onPrimaryContainer.withValues(
                                alpha: 0.8,
                              ) ??
                              context.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton.filled(
                  iconSize: 32,
                  tooltip: 'Play',
                  style: IconButton.styleFrom(
                    backgroundColor: scheme?.primary,
                    foregroundColor: scheme?.onPrimary,
                  ),
                  onPressed: () async {
                    HapticFeedback.lightImpact();
                    final songs =
                        (await ref.read(repositoryProvider)!.album(album.id))
                            .songs;
                    if (songs.isNotEmpty) await playFrom(ref, songs, 0);
                  },
                  icon: const Icon(Icons.play_arrow_rounded),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(startupSyncProvider);
    final offline = ref.watch(isOfflineProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _greeting(DateTime.now()),
          style: Theme.of(context).textTheme.headlineMedium,
        ),
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
            if (!offline)
              if (ref.watch(albumListProvider('recent')).value?.firstOrNull
                  case final last?)
                _ContinueListening(last),
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
        _ => PagedAlbumGrid(albumQuery(shelf.albumList!)),
      },
    );
  }
}
