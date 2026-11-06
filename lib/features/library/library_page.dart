import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/playlist_history.dart';
import '../../app/providers.dart';
import '../../data/repositories/library_repository.dart';
import '../collection/playlist_edit.dart';
import '../../data/subsonic/models.dart';
import '../../ui/widgets/tiles.dart';
import '../../app/experience.dart';
import '../cast/output_sheet.dart';
import '../home/home_page.dart';
import 'album_lists.dart';
import 'downloaded.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/backdrop.dart';

/// Every artist. The Subsonic API lists them in one response, so the list shows from the cache at once while the server answers.
final artistsProvider = StreamProvider.autoDispose<List<Artist>>((ref) {
  final repository = ref.watch(repositoryProvider);
  ref.watch(isOfflineProvider);
  if (repository == null) return Stream.value(const []);
  return cachedThenFresh(repository.cachedArtists(), repository.artists);
});

/// Albums matching a search of the Albums list.
final albumSearchProvider = FutureProvider.autoDispose
    .family<List<Album>, String>((ref, query) async {
      ref.watch(isOfflineProvider);
      return await ref.watch(repositoryProvider)?.searchAlbums(query) ??
          const [];
    });

/// Genres by name, from the cache at once when there is one, then from the server.
final genresProvider = StreamProvider.autoDispose<List<Genre>>((ref) {
  final repository = ref.watch(repositoryProvider);
  ref.watch(isOfflineProvider);
  if (repository == null) return Stream.value(const []);
  List<Genre> sorted(List<Genre> genres) =>
      [...genres]
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return cachedThenFresh(
    repository.cachedGenres(),
    repository.genres,
  ).map(sorted);
});

/// The library as Apple Music lays it out: a list of sections, Downloaded and Settings, followed by the recently added albums. With [downloaded], the same list for the downloaded music. Offline, the library shows the downloaded music.
class LibraryPage extends ConsumerWidget {
  const LibraryPage({super.key, this.downloaded = false});

  final bool downloaded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offline = ref.watch(isOfflineProvider);
    final showDownloaded = downloaded || offline;
    final recent = showDownloaded
        ? ref.watch(downloadedAlbumsProvider)
        : ref.watch(albumListProvider('newest'));
    final albums = (recent.value ?? const <Album>[]).take(24).toList();
    final sections =
        [
          for (final s in ref.watch(librarySectionsProvider))
            if (s.visible) s.item,
        ].where(
          (s) => switch (s) {
            // Songs are listed from the downloads; the Subsonic API has no listing of all songs.
            LibrarySection.songs => showDownloaded,
            // Genres and years are listings of the server.
            LibrarySection.genres || LibrarySection.years => !showDownloaded,
            _ => true,
          },
        );
    final transfers = showDownloaded
        ? ref.watch(transfersProvider).value?.length ?? 0
        : 0;
    final prefix = downloaded ? '/library/downloaded' : '/library';
    final primary = Theme.of(context).colorScheme.primary;

    Widget row(IconData icon, String title, String path) => ListTile(
      leading: Icon(icon, color: primary),
      title: Text(title, style: const TextStyle(fontSize: 18)),
      trailing: Icon(Icons.chevron_right, color: context.faint),
      onTap: () => context.push(path),
    );

    return Backdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(
            downloaded ? 'Downloaded' : 'Library',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          actions: const [OutputButton()],
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            final columns = ref
                .watch(coverSizeProvider)
                .columns(constraints.maxWidth);
            final width = (constraints.maxWidth - 16 * (columns + 1)) / columns;
            return CustomScrollView(
              slivers: [
                SliverList.list(
                  children: [
                    if (transfers > 0)
                      ListTile(
                        leading: Icon(Icons.downloading, color: primary),
                        title: const Text(
                          'Downloading',
                          style: TextStyle(fontSize: 18),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '$transfers',
                              style: TextStyle(color: context.muted),
                            ),
                            Icon(Icons.chevron_right, color: context.faint),
                          ],
                        ),
                        onTap: () =>
                            context.push('/library/downloaded/progress'),
                      ),
                    for (final section in sections)
                      row(
                        section.icon,
                        section.title,
                        '$prefix/${section.name}',
                      ),
                    if (!downloaded && !offline)
                      row(
                        Icons.arrow_circle_down,
                        'Downloaded',
                        '/library/downloaded',
                      ),
                    if (!downloaded)
                      row(Icons.settings_outlined, 'Settings', '/settings'),
                    if (albums.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                        child: Text(
                          showDownloaded
                              ? 'Recently downloaded'
                              : 'Recently added',
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
      ),
    );
  }
}

/// A list of the library: albums, artists, playlists, genres, years or songs. The search button filters the list; for albums on the server it searches the server, since the list loads page by page.
class LibrarySectionPage extends ConsumerStatefulWidget {
  const LibrarySectionPage(this.section, {super.key, this.downloaded = false});

  final LibrarySection section;
  final bool downloaded;

  @override
  ConsumerState<LibrarySectionPage> createState() => _LibrarySectionPageState();
}

class _LibrarySectionPageState extends ConsumerState<LibrarySectionPage> {
  final _search = TextEditingController();
  Timer? _debounce;
  bool _searching = false;

  /// The query the list shows, which follows the text field after a pause in typing.
  String _query = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _typed(String value) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 300),
      () => setState(() => _query = value.trim()),
    );
  }

  void _closeSearch() {
    _debounce?.cancel();
    _search.clear();
    setState(() {
      _searching = false;
      _query = '';
    });
  }

  List<T> _filter<T>(List<T> items, Iterable<String?> Function(T) fields) =>
      _query.isEmpty
      ? items
      : [
          for (final item in items)
            if (matchesQuery(_query, fields(item))) item,
        ];

  Widget _artists(List<Artist> artists) {
    final shown = _filter(artists, (a) => [a.name]);
    return shown.isEmpty
        ? const MessageView('No matching artists')
        : ListView.builder(
            itemCount: shown.length,
            itemBuilder: (_, i) => ArtistTile(shown[i]),
          );
  }

  Widget _playlists(List<Playlist> playlists) {
    final sort = ref.watch(playlistSortProvider);
    final sorted = sortPlaylists(
      playlists,
      sort,
      ref.watch(playlistHistoryProvider),
    );
    final shown = _filter(sorted, (p) => [p.name, p.owner]);
    return shown.isEmpty
        ? const MessageView('No matching playlists')
        : ListView.builder(
            itemCount: shown.length,
            itemBuilder: (_, i) => PlaylistTile(shown[i]),
          );
  }

  @override
  Widget build(BuildContext context) {
    final section = widget.section;
    final offline = ref.watch(isOfflineProvider);
    final downloaded = widget.downloaded || offline;
    final body = switch ((section, downloaded)) {
      (LibrarySection.albums, true) => AsyncList(
        ref.watch(downloadedAlbumsProvider),
        (albums) {
          final shown = _filter(albums, (a) => [a.name, a.artist]);
          return shown.isEmpty
              ? const MessageView('No matching albums')
              : AlbumGrid(shown);
        },
        empty: 'No downloaded albums',
      ),
      (LibrarySection.albums, false) when _query.isNotEmpty => AsyncList(
        ref.watch(albumSearchProvider(_query)),
        (albums) => AlbumGrid(albums),
        empty: 'No matching albums',
        onRetry: () => ref.invalidate(albumSearchProvider(_query)),
      ),
      (LibrarySection.albums, false) => PagedAlbumGrid(
        albumQuery('alphabeticalByName'),
      ),
      (LibrarySection.artists, true) => AsyncList(
        ref.watch(downloadedArtistsProvider),
        _artists,
        empty: 'No downloaded artists',
      ),
      (LibrarySection.artists, false) => AsyncList(
        ref.watch(artistsProvider),
        _artists,
        onRetry: () => ref.invalidate(artistsProvider),
      ),
      (LibrarySection.playlists, true) => AsyncList(
        ref.watch(downloadedPlaylistsProvider),
        _playlists,
        empty: 'No downloaded playlists',
      ),
      (LibrarySection.playlists, false) => AsyncList(
        ref.watch(recentPlaylistsProvider),
        _playlists,
        empty: 'No playlists yet',
        onRetry: () => ref.invalidate(playlistsProvider),
      ),
      (LibrarySection.genres, _) => AsyncList(ref.watch(genresProvider), (
        genres,
      ) {
        final shown = _filter(genres, (g) => [g.name]);
        return shown.isEmpty
            ? const MessageView('No matching genres')
            : ListView.builder(
                itemCount: shown.length,
                itemBuilder: (_, i) => ListTile(
                  title: Text(shown[i].name),
                  subtitle: Text(
                    countOf(shown[i].albumCount, 'album'),
                    style: TextStyle(color: context.muted),
                  ),
                  onTap: () => context.push(
                    '/genre/${Uri.encodeComponent(shown[i].name)}',
                  ),
                ),
              );
      }, onRetry: () => ref.invalidate(genresProvider)),
      (LibrarySection.years, _) => ListView(
        children: [
          for (
            var decade = DateTime.now().year ~/ 10 * 10;
            decade >= 1950;
            decade -= 10
          )
            ListTile(
              title: Text('${decade}s'),
              onTap: () => context.push('/years/$decade/${decade + 9}'),
            ),
          ListTile(
            title: const Text('Before 1950'),
            onTap: () => context.push('/years/1000/1949'),
          ),
        ],
      ),
      (LibrarySection.songs, _) => AsyncList(
        ref.watch(downloadedTracksProvider),
        (tracks) {
          final shown = _filter(tracks, (t) => [t.title, t.artist, t.album]);
          return shown.isEmpty
              ? const MessageView('No matching songs')
              : ListView.builder(
                  itemCount: shown.length,
                  itemBuilder: (_, i) => TrackTile(tracks: shown, index: i),
                );
        },
        empty: 'No downloaded songs',
      ),
    };
    final playlists = section == LibrarySection.playlists;
    // As a tab of the navigation bar the page has no back button and takes the large title of the other tabs.
    final isTab = !(GoRouter.maybeOf(context)?.canPop() ?? false);
    return Backdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: _searching
              ? TextField(
                  controller: _search,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Search ${section.title.toLowerCase()}',
                    border: InputBorder.none,
                  ),
                  onChanged: _typed,
                )
              : Text(
                  section.title,
                  style: isTab
                      ? Theme.of(context).textTheme.headlineMedium
                      : null,
                ),
          actions: [
            if (section != LibrarySection.years)
              IconButton(
                tooltip: _searching ? 'Close search' : 'Search',
                icon: Icon(_searching ? Icons.close : Icons.search),
                onPressed: _searching
                    ? _closeSearch
                    : () => setState(() => _searching = true),
              ),
            if (playlists && !_searching) const _PlaylistMenu(),
            const OutputButton(),
          ],
        ),
        floatingActionButton: playlists && !downloaded && !_searching
            ? FloatingActionButton(
                tooltip: 'New playlist',
                onPressed: () => createPlaylist(context, ref),
                child: const Icon(Icons.add),
              )
            : null,
        body: body,
      ),
    );
  }
}

/// Sorts the playlists by recent use or by name.
class _PlaylistMenu extends ConsumerWidget {
  const _PlaylistMenu();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sort = ref.watch(playlistSortProvider);
    return PopupMenuButton<PlaylistSort>(
      tooltip: 'Sort',
      icon: const Icon(Icons.sort),
      initialValue: sort,
      onSelected: ref.read(playlistSortProvider.notifier).set,
      itemBuilder: (_) => [
        for (final s in PlaylistSort.values)
          CheckedPopupMenuItem(
            value: s,
            checked: s == sort,
            child: Text(s.label),
          ),
      ],
    );
  }
}
