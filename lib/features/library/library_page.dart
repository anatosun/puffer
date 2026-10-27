import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../data/subsonic/models.dart';
import '../../ui/widgets/tiles.dart';
import '../cast/output_sheet.dart';
import '../home/home_page.dart';
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

enum LibrarySection {
  playlists('Playlists', Icons.queue_music),
  artists('Artists', Icons.mic_none),
  albums('Albums', Icons.album_outlined),
  songs('Songs', Icons.music_note_outlined);

  const LibrarySection(this.title, this.icon);

  final String title;
  final IconData icon;
}

/// The "Downloaded" filter, the same on the library and on each of its sections.
class DownloadedChip extends ConsumerWidget {
  const DownloadedChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
    padding: const EdgeInsets.only(right: 4),
    child: FilterChip(
      label: const Text('Downloaded'),
      avatar: const Icon(Icons.arrow_circle_down, size: 18),
      selected: ref.watch(showDownloadedProvider),
      onSelected: ref.watch(isOfflineProvider)
          ? null
          : (_) => ref.read(downloadedOnlyProvider.notifier).toggle(),
    ),
  );
}

/// The library as Apple Music lays it out: a list of sections and settings, followed by the recently added albums.
class LibraryPage extends ConsumerWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloaded = ref.watch(showDownloadedProvider);
    final recent = downloaded
        ? ref.watch(downloadedAlbumsProvider)
        : ref.watch(albumListProvider('newest'));
    final albums = (recent.value ?? const <Album>[]).take(24).toList();
    // Songs are listed from the downloads; the Subsonic API has no listing of all songs.
    final sections = LibrarySection.values.where(
      (s) => s != LibrarySection.songs || downloaded,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Library',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        actions: const [DownloadedChip(), OutputButton()],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final columns = (constraints.maxWidth / 180).floor().clamp(2, 8);
          final width = (constraints.maxWidth - 16 * (columns + 1)) / columns;
          return CustomScrollView(
            slivers: [
              SliverList.list(
                children: [
                  for (final section in sections)
                    ListTile(
                      leading: Icon(
                        section.icon,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      title: Text(
                        section.title,
                        style: const TextStyle(fontSize: 18),
                      ),
                      trailing: const Icon(
                        Icons.chevron_right,
                        color: Colors.white38,
                      ),
                      onTap: () => context.push('/library/${section.name}'),
                    ),
                  ListTile(
                    leading: Icon(
                      Icons.settings_outlined,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    title: const Text(
                      'Settings',
                      style: TextStyle(fontSize: 18),
                    ),
                    trailing: const Icon(
                      Icons.chevron_right,
                      color: Colors.white38,
                    ),
                    onTap: () => context.push('/settings'),
                  ),
                  if (albums.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                      child: Text(
                        downloaded ? 'Recently downloaded' : 'Recently added',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                ],
              ),
              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverGrid.builder(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
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
  }
}

class LibrarySectionPage extends ConsumerWidget {
  const LibrarySectionPage(this.section, {super.key});

  final LibrarySection section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloaded = ref.watch(showDownloadedProvider);
    final body = switch ((section, downloaded)) {
      (LibrarySection.albums, true) => _AsyncList(
        ref.watch(downloadedAlbumsProvider),
        (albums) => AlbumGrid(albums),
        empty: 'No downloaded albums',
      ),
      (LibrarySection.albums, false) => const _AllAlbums(),
      (LibrarySection.artists, true) => _AsyncList(
        ref.watch(downloadedArtistsProvider),
        (artists) => ListView.builder(
          itemCount: artists.length,
          itemBuilder: (_, i) => ArtistTile(artists[i]),
        ),
        empty: 'No downloaded artists',
      ),
      (LibrarySection.artists, false) => _AsyncList(
        ref.watch(_artistsProvider),
        (artists) => ListView.builder(
          itemCount: artists.length,
          itemBuilder: (_, i) => ArtistTile(artists[i]),
        ),
        onRetry: () => ref.invalidate(_artistsProvider),
      ),
      (LibrarySection.playlists, true) => _AsyncList(
        ref.watch(downloadedPlaylistsProvider),
        (playlists) => ListView.builder(
          itemCount: playlists.length,
          itemBuilder: (_, i) => PlaylistTile(playlists[i]),
        ),
        empty: 'No downloaded playlists',
      ),
      (LibrarySection.playlists, false) => _AsyncList(
        ref.watch(_playlistsProvider),
        (playlists) => ListView.builder(
          itemCount: playlists.length,
          itemBuilder: (_, i) => PlaylistTile(playlists[i]),
        ),
        onRetry: () => ref.invalidate(_playlistsProvider),
      ),
      (LibrarySection.songs, _) => _AsyncList(
        ref.watch(downloadedTracksProvider),
        (tracks) => ListView.builder(
          itemCount: tracks.length,
          itemBuilder: (_, i) => TrackTile(tracks: tracks, index: i),
        ),
        empty: 'No downloaded songs',
      ),
    };
    return Scaffold(
      appBar: AppBar(
        title: Text(section.title),
        actions: const [DownloadedChip(), OutputButton()],
      ),
      body: body,
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
