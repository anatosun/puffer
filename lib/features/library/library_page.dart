import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../data/subsonic/models.dart';
import '../../ui/widgets/tiles.dart';
import '../../app/experience.dart';
import '../cast/output_sheet.dart';
import '../home/home_page.dart';
import 'album_lists.dart';
import 'downloaded.dart';
import '../../ui/theme.dart';

final _artistsProvider = FutureProvider.autoDispose<List<Artist>>(
  (ref) async => await ref.watch(repositoryProvider)?.artists() ?? const [],
);

/// Genres by name.
final genresProvider = FutureProvider.autoDispose<List<Genre>>((ref) async {
  final genres = [...?await ref.watch(repositoryProvider)?.genres()];
  return genres
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
});

enum LibrarySection {
  playlists('Playlists', Icons.queue_music),
  artists('Artists', Icons.mic_none),
  albums('Albums', Icons.album_outlined),
  genres('Genres', Icons.category_outlined),
  years('Years', Icons.calendar_month_outlined),
  songs('Songs', Icons.music_note_outlined);

  const LibrarySection(this.title, this.icon);

  final String title;
  final IconData icon;
}

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
    final sections = LibrarySection.values.where(
      (s) => switch (s) {
        // Songs are listed from the downloads; the Subsonic API has no listing of all songs.
        LibrarySection.songs => showDownloaded,
        // Genres and years are listings of the server.
        LibrarySection.genres || LibrarySection.years => !showDownloaded,
        _ => true,
      },
    );
    final prefix = downloaded ? '/library/downloaded' : '/library';
    final primary = Theme.of(context).colorScheme.primary;

    Widget row(IconData icon, String title, String path) => ListTile(
      leading: Icon(icon, color: primary),
      title: Text(title, style: const TextStyle(fontSize: 18)),
      trailing: Icon(Icons.chevron_right, color: context.faint),
      onTap: () => context.push(path),
    );

    return Scaffold(
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
                  for (final section in sections)
                    row(section.icon, section.title, '$prefix/${section.name}'),
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
    );
  }
}

class LibrarySectionPage extends ConsumerWidget {
  const LibrarySectionPage(this.section, {super.key, this.downloaded = false});

  final LibrarySection section;
  final bool downloaded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloaded = this.downloaded || ref.watch(isOfflineProvider);
    final body = switch ((section, downloaded)) {
      (LibrarySection.albums, true) => AsyncList(
        ref.watch(downloadedAlbumsProvider),
        (albums) => AlbumGrid(albums),
        empty: 'No downloaded albums',
      ),
      (LibrarySection.albums, false) => PagedAlbumGrid(
        albumQuery('alphabeticalByName'),
      ),
      (LibrarySection.artists, true) => AsyncList(
        ref.watch(downloadedArtistsProvider),
        (artists) => ListView.builder(
          itemCount: artists.length,
          itemBuilder: (_, i) => ArtistTile(artists[i]),
        ),
        empty: 'No downloaded artists',
      ),
      (LibrarySection.artists, false) => AsyncList(
        ref.watch(_artistsProvider),
        (artists) => ListView.builder(
          itemCount: artists.length,
          itemBuilder: (_, i) => ArtistTile(artists[i]),
        ),
        onRetry: () => ref.invalidate(_artistsProvider),
      ),
      (LibrarySection.playlists, true) => AsyncList(
        ref.watch(downloadedPlaylistsProvider),
        (playlists) => ListView.builder(
          itemCount: playlists.length,
          itemBuilder: (_, i) => PlaylistTile(playlists[i]),
        ),
        empty: 'No downloaded playlists',
      ),
      (LibrarySection.playlists, false) => AsyncList(
        ref.watch(recentPlaylistsProvider),
        (playlists) => ListView.builder(
          itemCount: playlists.length,
          itemBuilder: (_, i) => PlaylistTile(playlists[i]),
        ),
        onRetry: () => ref.invalidate(recentPlaylistsProvider),
      ),
      (LibrarySection.genres, _) => AsyncList(
        ref.watch(genresProvider),
        (genres) => ListView.builder(
          itemCount: genres.length,
          itemBuilder: (_, i) => ListTile(
            title: Text(genres[i].name),
            subtitle: Text(
              '${genres[i].albumCount} albums',
              style: TextStyle(color: context.muted),
            ),
            onTap: () =>
                context.push('/genre/${Uri.encodeComponent(genres[i].name)}'),
          ),
        ),
        onRetry: () => ref.invalidate(genresProvider),
      ),
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
        actions: const [OutputButton()],
      ),
      body: body,
    );
  }
}
