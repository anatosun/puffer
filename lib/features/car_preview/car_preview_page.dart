import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/car_providers.dart';
import '../../app/playback_providers.dart';
import '../../playback/car_library.dart';
import '../../ui/widgets/artwork.dart';

/// The app opens on [CarPreviewPage], and has it at all, only when built with `--dart-define=PUFFER_CAR_PREVIEW=true`, as `make car-preview` does.
const carPreviewEnabled = bool.fromEnvironment('PUFFER_CAR_PREVIEW');

/// What Android Auto browses, laid out roughly as it shows it, so the car library can be tried on the desktop. It reads the same [CarLibrary] the media session gives a car. The screen has the shape of the Desktop Head Unit's, 800 by 480.
class CarPreviewPage extends ConsumerStatefulWidget {
  const CarPreviewPage({super.key});

  @override
  ConsumerState<CarPreviewPage> createState() => _CarPreviewPageState();
}

class _CarPreviewPageState extends ConsumerState<CarPreviewPage> {
  int _tab = 0;

  /// The items opened, from the tab or the search down to the list shown.
  final _path = <MediaItem>[];

  /// The search shown while not null.
  String? _query;
  final _search = TextEditingController();

  /// The lists asked for, by media ID, so a rebuild does not ask again. Cleared when the library changes.
  final _lists = <String, Future<List<MediaItem>>>{};
  CarLibrary? _library;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<List<MediaItem>> _children(CarLibrary car, String id) =>
      _lists[id] ??= car.children(id);

  Future<List<MediaItem>> _results(CarLibrary car, String query) =>
      _lists['search:$query'] ??= car.search(query);

  void _back() => setState(() {
    if (_path.isNotEmpty) {
      _path.removeLast();
    } else {
      _query = null;
      _search.clear();
    }
  });

  void _open(CarLibrary car, MediaItem item) {
    if (item.playable == false) {
      setState(() => _path.add(item));
    } else {
      car.playFromId(item.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final car = ref.watch(carLibraryProvider);
    if (!identical(car, _library)) {
      _library = car;
      _lists.clear();
      _path.clear();
    }
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text('Car preview')),
      body: car == null
          ? const Center(child: Text('Sign in to a server first.'))
          : Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: AspectRatio(
                  aspectRatio: 800 / 480,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: ColoredBox(
                      color: const Color(0xFF121212),
                      child: FutureBuilder(
                        future: _children(car, AudioService.browsableRootId),
                        builder: (context, snapshot) {
                          final tabs = snapshot.data ?? const <MediaItem>[];
                          return Column(
                            children: [
                              _topBar(car, tabs),
                              Expanded(child: _content(car, tabs)),
                              const _NowPlayingBar(),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _topBar(CarLibrary car, List<MediaItem> tabs) => SizedBox(
    height: 64,
    child: Row(
      children: [
        if (_path.isNotEmpty || _query != null)
          IconButton(
            icon: const Icon(Icons.arrow_back),
            iconSize: 28,
            onPressed: _back,
          )
        else
          const SizedBox(width: 16),
        Expanded(
          child: _path.isNotEmpty
              ? Text(
                  _path.last.title,
                  style: const TextStyle(fontSize: 22),
                  overflow: TextOverflow.ellipsis,
                )
              : _query != null
              ? TextField(
                  controller: _search,
                  autofocus: true,
                  style: const TextStyle(fontSize: 20),
                  decoration: const InputDecoration(
                    hintText: 'Search',
                    border: InputBorder.none,
                  ),
                  onSubmitted: (q) => setState(() => _query = q.trim()),
                )
              : Row(
                  children: [
                    for (final (i, t) in tabs.indexed)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(t.title),
                          selected: i == _tab,
                          onSelected: (_) => setState(() => _tab = i),
                        ),
                      ),
                  ],
                ),
        ),
        if (_query == null && _path.isEmpty)
          IconButton(
            icon: const Icon(Icons.search),
            iconSize: 28,
            onPressed: () => setState(() => _query = ''),
          ),
        const SizedBox(width: 8),
      ],
    ),
  );

  Widget _content(CarLibrary car, List<MediaItem> tabs) {
    final MediaItem? parent;
    final Future<List<MediaItem>> items;
    if (_path.isNotEmpty) {
      parent = _path.last;
      items = _children(car, parent.id);
    } else if (_query != null) {
      if (_query!.isEmpty) return const SizedBox.shrink();
      parent = null;
      items = _results(car, _query!);
    } else if (tabs.isNotEmpty) {
      parent = tabs[_tab.clamp(0, tabs.length - 1)];
      items = _children(car, parent.id);
    } else {
      return const Center(child: CircularProgressIndicator());
    }
    return FutureBuilder(
      future: items,
      builder: (context, snapshot) {
        final list = snapshot.data;
        if (list == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (list.isEmpty) {
          return const Center(child: Text('Nothing here'));
        }
        if (carShowsGrid(parent, list)) {
          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 160,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 0.75,
            ),
            itemCount: list.length,
            itemBuilder: (context, i) =>
                _GridTile(list[i], onTap: () => _open(car, list[i])),
          );
        }
        return ListView.builder(
          itemCount: list.length,
          itemBuilder: (context, i) =>
              _ListTile(list[i], onTap: () => _open(car, list[i])),
        );
      },
    );
  }
}

/// The cover of [item] from the file the car would read, or a placeholder.
class _Cover extends StatelessWidget {
  const _Cover(this.item, {required this.size});

  final MediaItem item;
  final double? size;

  @override
  Widget build(BuildContext context) {
    final uri = item.artUri;
    final placeholder = ColoredBox(
      color: Colors.white10,
      child: Icon(
        item.playable == false ? Icons.album : Icons.music_note,
        color: Colors.white38,
      ),
    );
    return SizedBox.square(
      dimension: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: uri != null && uri.scheme == 'file'
            ? Image.file(
                File.fromUri(uri),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => placeholder,
              )
            : placeholder,
      ),
    );
  }
}

class _GridTile extends StatelessWidget {
  const _GridTile(this.item, {required this.onTap});

  final MediaItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(aspectRatio: 1, child: _Cover(item, size: null)),
        const SizedBox(height: 6),
        Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        if (item.artist != null)
          Text(
            item.artist!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
      ],
    ),
  );
}

class _ListTile extends StatelessWidget {
  const _ListTile(this.item, {required this.onTap});

  final MediaItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    onTap: onTap,
    minTileHeight: 64,
    leading: _Cover(item, size: 48),
    title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
    subtitle: item.artist == null
        ? null
        : Text(item.artist!, maxLines: 1, overflow: TextOverflow.ellipsis),
    trailing: item.playable == false ? const Icon(Icons.chevron_right) : null,
  );
}

/// The song that plays, with the buttons a car shows.
class _NowPlayingBar extends ConsumerWidget {
  const _NowPlayingBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final np = ref.watch(nowPlayingProvider).value;
    if (np == null) return const SizedBox(height: 8);
    final controller = ref.read(playbackControllerProvider);
    final image = artworkImage(ref, np.coverArt, size: 300);
    return Container(
      height: 72,
      color: Colors.white10,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          SizedBox.square(
            dimension: 52,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: image == null
                  ? const ColoredBox(color: Colors.white10)
                  : Image(image: image, fit: BoxFit.cover),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(np.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                if (np.artist != null)
                  Text(
                    np.artist!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white54),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.skip_previous),
            iconSize: 32,
            onPressed: controller.previous,
          ),
          IconButton(
            icon: Icon(np.playing ? Icons.pause : Icons.play_arrow),
            iconSize: 40,
            onPressed: np.playing ? controller.pause : controller.play,
          ),
          IconButton(
            icon: const Icon(Icons.skip_next),
            iconSize: 32,
            onPressed: controller.next,
          ),
        ],
      ),
    );
  }
}
