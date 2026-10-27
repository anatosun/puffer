import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/subsonic/models.dart';
import '../../ui/widgets/tiles.dart';

/// The albums of a `getAlbumList2` type, loaded page by page as the list scrolls.
class PagedAlbumsNotifier extends AsyncNotifier<List<Album>> {
  PagedAlbumsNotifier(this.type);

  final String type;
  static const _pageSize = 100;
  bool _done = false;
  bool _loading = false;

  @override
  Future<List<Album>> build() async {
    _done = false;
    final repository = ref.watch(repositoryProvider);
    ref.watch(isOfflineProvider);
    if (repository == null) return const [];
    final page = await repository.albumList(type, size: _pageSize);
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
          .albumList(type, size: _pageSize, offset: current.length);
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
    .family<PagedAlbumsNotifier, List<Album>, String>(PagedAlbumsNotifier.new);

class PagedAlbumGrid extends ConsumerStatefulWidget {
  const PagedAlbumGrid(this.type, {super.key});

  final String type;

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
        ref.read(pagedAlbumsProvider(widget.type).notifier).loadMore();
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
    ref.watch(pagedAlbumsProvider(widget.type)),
    (albums) => AlbumGrid(albums, controller: _controller),
    onRetry: () => ref.invalidate(pagedAlbumsProvider(widget.type)),
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
    data: (items) => items.isEmpty
        ? MessageView(empty, icon: Icons.library_music_outlined)
        : builder(items),
    loading: () => const Center(child: CircularProgressIndicator()),
    error: (e, _) => MessageView('$e', onRetry: onRetry),
  );
}
