import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/repositories/library_repository.dart';
import '../../data/subsonic/models.dart';
import '../../ui/widgets/shimmer.dart';
import '../../ui/widgets/tiles.dart';
import '../cast/output_sheet.dart';
import '../../ui/widgets/backdrop.dart';

/// A `getAlbumList2` request: the type, with the genre of `byGenre` or the years of `byYear`.
typedef AlbumQuery = ({String type, String? genre, int? fromYear, int? toYear});

AlbumQuery albumQuery(
  String type, {
  String? genre,
  int? fromYear,
  int? toYear,
}) => (type: type, genre: genre, fromYear: fromYear, toYear: toYear);

/// The albums of an [AlbumQuery], loaded page by page as the list scrolls. The first page shows from the cache while the server answers.
class PagedAlbumsNotifier extends AsyncNotifier<List<Album>> {
  PagedAlbumsNotifier(this.query);

  final AlbumQuery query;
  static const _pageSize = 100;
  bool _done = false;
  bool _loading = false;

  @override
  Future<List<Album>> build() async {
    _done = false;
    final repository = ref.watch(repositoryProvider);
    ref.watch(isOfflineProvider);
    if (repository == null) return const [];
    // A random list is new on every visit, so it never shows from the cache.
    final cached = query.type == 'random'
        ? null
        : await repository.cachedAlbumList(
            query.type,
            size: _pageSize,
            genre: query.genre,
            fromYear: query.fromYear,
            toYear: query.toYear,
          );
    if (cached != null && cached.isNotEmpty) {
      _done = cached.length < _pageSize;
      unawaited(_refreshFirstPage(repository));
      return cached;
    }
    final page = await _load(repository, 0);
    _done = page.length < _pageSize;
    return page;
  }

  /// Replaces the cached first page with the answer of the server, unless more pages have loaded meanwhile.
  Future<void> _refreshFirstPage(LibraryRepository repository) async {
    try {
      final page = await _load(repository, 0);
      if (!ref.mounted || (state.value?.length ?? 0) > _pageSize) return;
      _done = page.length < _pageSize;
      state = AsyncData(page);
    } on Exception {
      // The cached page stays.
    }
  }

  Future<List<Album>> _load(LibraryRepository repository, int offset) =>
      repository.albumList(
        query.type,
        size: _pageSize,
        offset: offset,
        genre: query.genre,
        fromYear: query.fromYear,
        toYear: query.toYear,
      );

  Future<void> loadMore() async {
    final current = state.value;
    if (_done || _loading || current == null) return;
    _loading = true;
    try {
      final page = await _load(ref.read(repositoryProvider)!, current.length);
      _done = page.length < _pageSize;
      // Random lists ignore the offset, so later pages can repeat albums.
      final seen = {for (final a in current) a.id};
      state = AsyncData([...current, ...page.where((a) => seen.add(a.id))]);
    } on Exception {
      _done = true;
    } finally {
      _loading = false;
    }
  }
}

final pagedAlbumsProvider = AsyncNotifierProvider.autoDispose
    .family<PagedAlbumsNotifier, List<Album>, AlbumQuery>(
      PagedAlbumsNotifier.new,
    );

class PagedAlbumGrid extends ConsumerStatefulWidget {
  const PagedAlbumGrid(this.query, {super.key});

  final AlbumQuery query;

  @override
  ConsumerState<PagedAlbumGrid> createState() => _PagedAlbumGridState();
}

class _PagedAlbumGridState extends ConsumerState<PagedAlbumGrid> {
  final _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      if (_controller.position.extentAfter < 800) {
        ref.read(pagedAlbumsProvider(widget.query).notifier).loadMore();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AsyncList(
    ref.watch(pagedAlbumsProvider(widget.query)),
    (albums) => AlbumGrid(albums, controller: _controller),
    onRetry: () => ref.invalidate(pagedAlbumsProvider(widget.query)),
  );
}

/// A list in its loading, error, empty and loaded states.
class AsyncList<T> extends StatelessWidget {
  const AsyncList(
    this.value,
    this.builder, {
    super.key,
    this.empty = 'Nothing here yet',
    this.onRetry,
  });

  final AsyncValue<List<T>> value;
  final Widget Function(List<T>) builder;
  final String empty;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => value.when(
    data: (items) => items.isEmpty ? MessageView(empty) : builder(items),
    loading: () => const ListPlaceholder(),
    error: (e, _) => MessageView('$e', onRetry: onRetry),
  );
}

/// The albums of a genre or of a span of years.
class AlbumQueryPage extends StatelessWidget {
  const AlbumQueryPage({super.key, required this.title, required this.query});

  final String title;
  final AlbumQuery query;

  @override
  Widget build(BuildContext context) => Backdrop(
    child: Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: Text(title), actions: const [OutputButton()]),
      body: PagedAlbumGrid(query),
    ),
  );
}
