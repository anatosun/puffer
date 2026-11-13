import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/playlist_history.dart';
import '../../app/providers.dart';
import '../../data/repositories/library_repository.dart';
import '../../data/subsonic/models.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/artwork.dart';
import '../../ui/widgets/backdrop.dart';
import '../../ui/widgets/pressable.dart';
import '../../ui/widgets/tiles.dart';
import '../../app/experience.dart';
import '../cast/output_sheet.dart';
import '../library/album_lists.dart';
import '../library/downloaded.dart';

/// The albums of a Home shelf. They stay in memory for the session and show from the cache at start-up while the server answers; pull to refresh reloads them.
final albumListProvider = StreamProvider.family<List<Album>, String>((
  ref,
  type,
) {
  final repository = ref.watch(repositoryProvider);
  ref.watch(isOfflineProvider);
  if (repository == null) return Stream.value(const []);
  return cachedThenFresh(
    repository.cachedAlbumList(type, size: 20),
    () => repository.albumList(type, size: 20),
  );
});

/// Every playlist on the server, cached like [albumListProvider].
final playlistsProvider = StreamProvider<List<Playlist>>((ref) {
  final repository = ref.watch(repositoryProvider);
  ref.watch(isOfflineProvider);
  if (repository == null) return Stream.value(const []);
  return cachedThenFresh(repository.cachedPlaylists(), repository.playlists);
});

/// Playlists, most recently played on this device or changed on the server first.
final recentPlaylistsProvider = Provider<AsyncValue<List<Playlist>>>((ref) {
  final played = ref.watch(playlistHistoryProvider);
  return ref.watch(playlistsProvider).whenData((p) => byRecency(p, played));
});

/// The albums of the Home shelf [type]. Offline, those of them with downloaded songs, which can play, in the same order.
final shelfAlbumsProvider = Provider.autoDispose
    .family<AsyncValue<List<Album>>, String>((ref, type) {
      final albums = ref.watch(albumListProvider(type));
      if (!ref.watch(isOfflineProvider)) return albums;
      final downloaded = ref.watch(downloadedTracksProvider).value;
      if (downloaded == null || (albums.isLoading && !albums.hasValue)) {
        return const AsyncLoading();
      }
      final ids = {for (final t in downloaded) ?t.albumId};
      return AsyncData([
        for (final a in albums.value ?? const <Album>[])
          if (ids.contains(a.id)) a,
      ]);
    });

/// The playlists of the Home shelf, most recent first. Offline, the downloaded ones.
final shelfPlaylistsProvider = Provider.autoDispose<AsyncValue<List<Playlist>>>(
  (ref) {
    if (!ref.watch(isOfflineProvider)) {
      return ref.watch(recentPlaylistsProvider);
    }
    final played = ref.watch(playlistHistoryProvider);
    return ref
        .watch(downloadedPlaylistsProvider)
        .whenData((p) => byRecency(p, played));
  },
);

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
      child: Pressable(
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
      ),
    );
  }
}

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(startupSyncProvider);
    final last = ref.watch(continueListeningProvider)
        ? ref.watch(shelfAlbumsProvider('recent')).value?.firstOrNull
        : null;
    return Backdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(
            ref.watch(greetingProvider) ? _greeting(DateTime.now()) : 'Home',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          actions: const [OutputButton()],
        ),
        body: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(albumListProvider);
            ref.invalidate(playlistsProvider);
          },
          child: ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              if (last != null) _ContinueListening(last),
              for (final setting in ref.watch(homeShelvesProvider))
                if (setting.visible)
                  switch (setting.item) {
                    HomeShelf.downloaded => _Shelf(
                      shelf: setting.item,
                      items: ref.watch(downloadedAlbumsProvider),
                      builder: (albums, loading) =>
                          AlbumShelf(albums, loading: loading),
                    ),
                    HomeShelf.playlists => _Shelf(
                      shelf: setting.item,
                      items: ref.watch(shelfPlaylistsProvider),
                      builder: (playlists, loading) => PlaylistShelf(
                        playlists.take(20).toList(),
                        loading: loading,
                      ),
                    ),
                    _ => _Shelf(
                      shelf: setting.item,
                      items: ref.watch(
                        shelfAlbumsProvider(setting.item.albumList!),
                      ),
                      builder: (albums, loading) =>
                          AlbumShelf(albums, loading: loading),
                    ),
                  },
            ],
          ),
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
    return Backdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(shelf.label),
          actions: const [OutputButton()],
        ),
        body: switch (shelf) {
          HomeShelf.downloaded => AsyncList(
            ref.watch(downloadedAlbumsProvider),
            (albums) => AlbumGrid(albums),
            empty: 'No downloaded albums',
          ),
          HomeShelf.playlists => AsyncList(
            ref.watch(shelfPlaylistsProvider),
            (playlists) => ListView.builder(
              itemCount: playlists.length,
              itemBuilder: (_, i) => PlaylistTile(playlists[i]),
            ),
            onRetry: () => ref.invalidate(playlistsProvider),
          ),
          // Offline, the albums of the shelf that can play; the server has the others.
          _ when ref.watch(isOfflineProvider) => AsyncList(
            ref.watch(shelfAlbumsProvider(shelf.albumList!)),
            (albums) => AlbumGrid(albums),
            empty: 'No downloaded albums',
          ),
          _ => PagedAlbumGrid(albumQuery(shelf.albumList!)),
        },
      ),
    );
  }
}
