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
          final columns = ref
              .watch(coverSizeProvider)
              .columns(constraints.maxWidth);
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
                      trailing: Icon(Icons.chevron_right, color: context.faint),
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
                    trailing: Icon(Icons.chevron_right, color: context.faint),
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
      (LibrarySection.albums, true) => AsyncList(
        ref.watch(downloadedAlbumsProvider),
        (albums) => AlbumGrid(albums),
        empty: 'No downloaded albums',
      ),
      (LibrarySection.albums, false) => const PagedAlbumGrid(
        'alphabeticalByName',
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
        ref.watch(_playlistsProvider),
        (playlists) => ListView.builder(
          itemCount: playlists.length,
          itemBuilder: (_, i) => PlaylistTile(playlists[i]),
        ),
        onRetry: () => ref.invalidate(_playlistsProvider),
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
        actions: const [DownloadedChip(), OutputButton()],
      ),
      body: body,
    );
  }
}
