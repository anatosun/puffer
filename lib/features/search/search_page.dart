import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/subsonic/models.dart';
import '../../ui/widgets/shimmer.dart';
import '../../ui/widgets/tiles.dart';
import '../cast/output_sheet.dart';
import '../../ui/widgets/backdrop.dart';

final _queryProvider = NotifierProvider<_QueryNotifier, String>(
  _QueryNotifier.new,
);

class _QueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  void set(String value) => state = value;
}

final _resultsProvider = FutureProvider.autoDispose<SearchResult?>((ref) async {
  final query = ref.watch(_queryProvider).trim();
  final repository = ref.watch(repositoryProvider);
  ref.watch(isOfflineProvider);
  if (query.isEmpty || repository == null) return null;
  return repository.search(query);
});

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(_resultsProvider);
    final offline = ref.watch(isOfflineProvider);
    return Backdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          actions: const [OutputButton()],
          title: TextField(
            autofocus: false,
            decoration: InputDecoration(
              hintText: offline
                  ? 'Search downloaded music'
                  : 'Artists, albums, songs',
              prefixIcon: const Icon(Icons.search),
              border: InputBorder.none,
            ),
            onChanged: (value) {
              _debounce?.cancel();
              _debounce = Timer(
                const Duration(milliseconds: 300),
                () => ref.read(_queryProvider.notifier).set(value),
              );
            },
          ),
        ),
        body: results.when(
          loading: () => const ListPlaceholder(),
          error: (e, _) => MessageView('$e'),
          data: (r) {
            if (r == null) {
              return const MessageView('Search your library');
            }
            if (r.artists.isEmpty && r.albums.isEmpty && r.tracks.isEmpty) {
              return const MessageView('No results');
            }
            return ListView(
              children: [
                if (r.artists.isNotEmpty) ...[
                  const _Heading('Artists'),
                  for (final a in r.artists) ArtistTile(a),
                ],
                if (r.albums.isNotEmpty) ...[
                  const _Heading('Albums'),
                  AlbumShelf(r.albums),
                ],
                if (r.tracks.isNotEmpty) ...[
                  const _Heading('Songs'),
                  for (var i = 0; i < r.tracks.length; i++)
                    TrackTile(tracks: r.tracks, index: i),
                ],
                const SizedBox(height: 24),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
    child: Text(text, style: Theme.of(context).textTheme.titleLarge),
  );
}
