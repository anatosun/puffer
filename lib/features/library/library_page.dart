import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/subsonic/models.dart';
import '../../ui/widgets/tiles.dart';
import '../cast/output_sheet.dart';
import 'downloaded.dart';

class DownloadedOnlyNotifier extends Notifier<bool> {
  @override
  bool build() =>
      ref.read(sharedPreferencesProvider).getBool('library.downloadedOnly') ??
      false;

  Future<void> toggle() async {
    state = !state;
    await ref
        .read(sharedPreferencesProvider)
        .setBool('library.downloadedOnly', state);
  }
}

final downloadedOnlyProvider = NotifierProvider<DownloadedOnlyNotifier, bool>(
  DownloadedOnlyNotifier.new,
);

/// Offline, the library always shows downloaded items.
final showDownloadedProvider = Provider<bool>(
  (ref) => ref.watch(downloadedOnlyProvider) || ref.watch(isOfflineProvider),
);

final _artistsProvider = FutureProvider.autoDispose<List<Artist>>(
  (ref) async => await ref.watch(repositoryProvider)?.artists() ?? const [],
);
final _playlistsProvider = FutureProvider.autoDispose<List<Playlist>>(
  (ref) async => await ref.watch(repositoryProvider)?.playlists() ?? const [],
);

/// All albums, loaded page by page as the list scrolls.
class PagedAlbumsNotifier extends AsyncNotifier<List<Album>> {
  static const _pageSize = 100;
  bool _done = false;
  bool _loading = false;

  @override
  Future<List<Album>> build() async {
    _done = false;
    final repository = ref.watch(repositoryProvider);
    if (repository == null) return const [];
    final page = await repository.albumList(
      'alphabeticalByName',
      size: _pageSize,
    );
    _done = page.length < _pageSize;
    return page;
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (_done || _loading || current == null) return;
    _loading = true;
    try {
      final page = await ref
          .read(repositoryProvider)!
          .albumList(
            'alphabeticalByName',
            size: _pageSize,
            offset: current.length,
          );
      _done = page.length < _pageSize;
      state = AsyncData([...current, ...page]);
    } on Exception {
      _done = true;
    } finally {
      _loading = false;
    }
  }
}

final pagedAlbumsProvider =
    AsyncNotifierProvider<PagedAlbumsNotifier, List<Album>>(
      PagedAlbumsNotifier.new,
    );

class LibraryPage extends ConsumerWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloaded = ref.watch(showDownloadedProvider);
    final offline = ref.watch(isOfflineProvider);
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            'Library',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: FilterChip(
                label: const Text('Downloaded'),
                avatar: const Icon(Icons.arrow_circle_down, size: 18),
                selected: downloaded,
                onSelected: offline
                    ? null
                    : (_) => ref.read(downloadedOnlyProvider.notifier).toggle(),
              ),
            ),
            const OutputButton(),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'Albums'),
              Tab(text: 'Artists'),
              Tab(text: 'Playlists'),
              Tab(text: 'Songs'),
            ],
          ),
        ),
        body: TabBarView(
          children: downloaded
              ? [
                  _AsyncList(
                    ref.watch(downloadedAlbumsProvider),
                    (albums) => AlbumGrid(albums),
                    empty: 'No downloaded albums',
                  ),
                  _AsyncList(
                    ref.watch(downloadedArtistsProvider),
                    (artists) => ListView.builder(
                      itemCount: artists.length,
                      itemBuilder: (_, i) => ArtistTile(artists[i]),
                    ),
                    empty: 'No downloaded artists',
                  ),
                  _AsyncList(
                    ref.watch(downloadedPlaylistsProvider),
                    (playlists) => ListView.builder(
                      itemCount: playlists.length,
                      itemBuilder: (_, i) => PlaylistTile(playlists[i]),
                    ),
                    empty: 'No downloaded playlists',
                  ),
                  _AsyncList(
                    ref.watch(downloadedTracksProvider),
                    (tracks) => ListView.builder(
                      itemCount: tracks.length,
                      itemBuilder: (_, i) =>
                          TrackTile(tracks: tracks, index: i),
                    ),
                    empty: 'No downloaded songs',
                  ),
                ]
              : [
                  const _AllAlbums(),
                  _AsyncList(
                    ref.watch(_artistsProvider),
                    (artists) => ListView.builder(
                      itemCount: artists.length,
                      itemBuilder: (_, i) => ArtistTile(artists[i]),
                    ),
                    onRetry: () => ref.invalidate(_artistsProvider),
                  ),
                  _AsyncList(
                    ref.watch(_playlistsProvider),
                    (playlists) => ListView.builder(
                      itemCount: playlists.length,
                      itemBuilder: (_, i) => PlaylistTile(playlists[i]),
                    ),
                    onRetry: () => ref.invalidate(_playlistsProvider),
                  ),
                  const MessageView(
                    'Search to find songs, or switch on "Downloaded" to list downloaded songs.',
                    icon: Icons.music_note,
                  ),
                ],
        ),
      ),
    );
  }
}

class _AllAlbums extends ConsumerStatefulWidget {
  const _AllAlbums();

  @override
  ConsumerState<_AllAlbums> createState() => _AllAlbumsState();
}

class _AllAlbumsState extends ConsumerState<_AllAlbums> {
  final _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      if (_controller.position.extentAfter < 800) {
        ref.read(pagedAlbumsProvider.notifier).loadMore();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _AsyncList(
    ref.watch(pagedAlbumsProvider),
    (albums) => AlbumGrid(albums, controller: _controller),
    onRetry: () => ref.invalidate(pagedAlbumsProvider),
  );
}

class _AsyncList<T> extends StatelessWidget {
  const _AsyncList(
    this.value,
    this.builder, {
    this.empty = 'Nothing here yet',
    this.onRetry,
  });

  final AsyncValue<List<T>> value;
  final Widget Function(List<T>) builder;
  final String empty;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => value.when(
    data: (items) => items.isEmpty
        ? MessageView(empty, icon: Icons.library_music_outlined)
        : builder(items),
    loading: () => const Center(child: CircularProgressIndicator()),
    error: (e, _) => MessageView('$e', onRetry: onRetry),
  );
}
