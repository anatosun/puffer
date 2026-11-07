import 'dart:async';

import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/search_history.dart';
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

/// The results the page shows. On octo-fiesta the results of external providers wait for "More", which each new query resets.
final _shownProvider =
    Provider.autoDispose<AsyncValue<({SearchResult result, bool more})?>>((
      ref,
    ) {
      final query = ref.watch(_queryProvider).trim();
      final showExternal = ref.watch(externalShownProvider('search:$query'));
      return ref
          .watch(_resultsProvider)
          .whenData((r) => r?.shown(showExternal: showExternal));
    });

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  // The query outlives the page, so the field starts with it.
  late final _field = TextEditingController(text: ref.read(_queryProvider));
  Timer? _debounce;
  Offset? _down;

  @override
  void dispose() {
    _debounce?.cancel();
    _field.dispose();
    super.dispose();
  }

  void _remember() =>
      ref.read(recentSearchesProvider.notifier).add(ref.read(_queryProvider));

  /// Searches [query] at once, as when it is picked from the recent searches.
  void _search(String query) {
    _debounce?.cancel();
    _field.value = TextEditingValue(
      text: query,
      selection: TextSelection.collapsed(offset: query.length),
    );
    ref.read(_queryProvider.notifier).set(query);
    _remember();
  }

  /// Remembers the search when a result is tapped, but not when the results are scrolled.
  Widget _rememberOnTap(Widget results) => Listener(
    onPointerDown: (e) => _down = e.position,
    onPointerUp: (e) {
      final down = _down;
      if (down != null && (e.position - down).distance < kTouchSlop) {
        _remember();
      }
    },
    child: results,
  );

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(_shownProvider);
    final offline = ref.watch(isOfflineProvider);
    return Backdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          actions: [
            // On proxies such as octo-fiesta: the results of external providers, which wait for this button.
            if (results.value?.more ?? false)
              MoreSourcesButton(
                onPressed: () => ref
                    .read(
                      externalShownProvider(
                        'search:${ref.read(_queryProvider).trim()}',
                      ).notifier,
                    )
                    .show(),
              ),
            const OutputButton(),
          ],
          title: TextField(
            controller: _field,
            autofocus: false,
            textInputAction: TextInputAction.search,
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
            onSubmitted: (value) {
              _debounce?.cancel();
              ref.read(_queryProvider.notifier).set(value);
              _remember();
            },
          ),
        ),
        body: results.when(
          loading: () => const ListPlaceholder(),
          error: (e, _) => MessageView('$e'),
          data: (shown) {
            if (shown == null) {
              return _RecentSearches(onPick: _search);
            }
            final r = shown.result;
            if (r.artists.isEmpty && r.albums.isEmpty && r.tracks.isEmpty) {
              return MessageView(
                shown.more ? 'No results in your library' : 'No results',
              );
            }
            return _rememberOnTap(
              ListView(
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
              ),
            );
          },
        ),
      ),
    );
  }
}

/// The recent searches, shown while the field is empty. A tap searches again; the cross forgets one.
class _RecentSearches extends ConsumerWidget {
  const _RecentSearches({required this.onPick});

  final void Function(String query) onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recent = ref.watch(recentSearchesProvider);
    if (recent.isEmpty) return const MessageView('Search your library');
    final history = ref.read(recentSearchesProvider.notifier);
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Recent searches',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              TextButton(onPressed: history.clear, child: const Text('Clear')),
            ],
          ),
        ),
        for (final query in recent)
          ListTile(
            leading: const Icon(Icons.history),
            title: Text(query, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: IconButton(
              tooltip: 'Remove',
              icon: const Icon(Icons.close),
              onPressed: () => history.remove(query),
            ),
            onTap: () => onPick(query),
          ),
      ],
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
