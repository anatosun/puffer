import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/subsonic/models.dart';
import '../../ui/widgets/tiles.dart';
import '../cast/output_sheet.dart';
import '../library/downloaded.dart';

final albumListProvider = FutureProvider.autoDispose
    .family<List<Album>, String>((ref, type) async {
      final repository = ref.watch(repositoryProvider);
      ref.watch(isOfflineProvider);
      if (repository == null) return const [];
      return repository.albumList(type, size: 20);
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
          for (final type in ['recent', 'newest', 'frequent', 'random']) {
            ref.invalidate(albumListProvider(type));
          }
        },
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            if (offline)
              _Shelf(
                title: 'Downloaded',
                albums: ref.watch(downloadedAlbumsProvider),
              )
            else ...[
              _Shelf(
                title: 'Recently played',
                albums: ref.watch(albumListProvider('recent')),
              ),
              _Shelf(
                title: 'Recently added',
                albums: ref.watch(albumListProvider('newest')),
              ),
              _Shelf(
                title: 'Most played',
                albums: ref.watch(albumListProvider('frequent')),
              ),
              _Shelf(
                title: 'Discover',
                albums: ref.watch(albumListProvider('random')),
              ),
              _Shelf(
                title: 'Downloaded',
                albums: ref.watch(downloadedAlbumsProvider),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Shelf extends StatelessWidget {
  const _Shelf({required this.title, required this.albums});

  final String title;
  final AsyncValue<List<Album>> albums;

  @override
  Widget build(BuildContext context) {
    final list = albums.value ?? const [];
    if (albums.hasValue && list.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        SizedBox(
          height: 210,
          child: albums.isLoading && list.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 14),
                  itemBuilder: (context, i) => AlbumCard(list[i]),
                ),
        ),
      ],
    );
  }
}
