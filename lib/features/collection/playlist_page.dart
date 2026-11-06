import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../data/repositories/library_repository.dart';
import '../../data/subsonic/models.dart';
import '../../downloads/download_manager.dart';
import '../../ui/messages.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/item_actions.dart';
import '../../ui/widgets/shimmer.dart';
import '../../ui/widgets/tiles.dart';
import 'collection_header.dart';
import '../home/home_page.dart';
import 'add_songs_sheet.dart';
import 'playlist_edit.dart';
import '../../ui/widgets/backdrop.dart';

/// A playlist with its tracks: from the cache at once when there is one, then from the server. Large playlists thus open without waiting for the server, and downloaded ones always do.
final playlistProvider = StreamProvider.autoDispose.family<Playlist, String>((
  ref,
  id,
) {
  ref.watch(isOfflineProvider);
  final repository = ref.watch(repositoryProvider)!;
  return cachedThenFresh(
    repository.cachedPlaylist(id),
    () => repository.playlist(id),
  );
});

class PlaylistPage extends ConsumerWidget {
  const PlaylistPage(this.id, {super.key});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(playlistProvider(id))
        .when(
          loading: () => const CollectionPlaceholder(body: ListPlaceholder()),
          error: (e, _) => CollectionPlaceholder(
            body: MessageView(
              '$e',
              onRetry: () => ref.invalidate(playlistProvider(id)),
            ),
          ),
          data: (playlist) => Backdrop(
            coverArt: playlist.headerCover,
            top: 0.25,
            child: Scaffold(
              backgroundColor: Colors.transparent,
              body: _PlaylistBody(playlist),
            ),
          ),
        );
  }
}

/// The tracks of a playlist. The owner reorders them with the drag handles and removes them by swiping.
class _PlaylistBody extends ConsumerStatefulWidget {
  const _PlaylistBody(this.playlist);

  final Playlist playlist;

  @override
  ConsumerState<_PlaylistBody> createState() => _PlaylistBodyState();
}

class _PlaylistBodyState extends ConsumerState<_PlaylistBody> {
  late List<Track> _entries = widget.playlist.entries;

  @override
  void didUpdateWidget(_PlaylistBody old) {
    super.didUpdateWidget(old);
    if (old.playlist != widget.playlist) _entries = widget.playlist.entries;
  }

  Future<void> _saving = Future.value();

  /// Sends [edit] after the edits before it, so an undo never reaches the server before the removal it undoes.
  Future<void> _save(Future<void> Function() edit) {
    // Taken now: the page may close before the edit is sent.
    final container = ProviderScope.containerOf(context, listen: false);
    final id = widget.playlist.id;
    return _saving = _saving.then((_) async {
      try {
        await edit();
        await playlistsChanged(container, id);
      } on Exception catch (e) {
        showMessage('$e');
        if (mounted) setState(() => _entries = widget.playlist.entries);
      }
    });
  }

  void _move(int from, int to) {
    final entries = [..._entries];
    entries.insert(to, entries.removeAt(from));
    setState(() => _entries = entries);
    _save(
      () => ref
          .read(clientProvider)!
          .createPlaylist(playlistId: widget.playlist.id, songIds: entries.ids),
    );
  }

  void _remove(int index) {
    final before = _entries;
    final client = ref.read(clientProvider)!;
    final id = widget.playlist.id;
    setState(() => _entries = [...before]..removeAt(index));
    _save(() => client.updatePlaylist(id, songIndexesToRemove: [index]));
    showMessage(
      'Removed ${before[index].title}',
      action: 'Undo',
      onAction: () {
        // The order before the removal, which puts the song back where it was.
        Future<void> restore() =>
            client.createPlaylist(playlistId: id, songIds: before.ids);
        if (!mounted) {
          unawaited(_saving.then((_) => restore()).catchError((Object _) {}));
          return;
        }
        setState(() => _entries = before);
        _save(restore);
      },
    );
  }

  void _addSongs() => showAddSongs(context, ref, widget.playlist, _entries.ids);

  void _showMenu() {
    final p = widget.playlist;
    showItemActions(
      context,
      ref,
      kind: PinKind.playlist,
      id: p.id,
      title: p.name,
      subtitle: countOf(_entries.length, 'song'),
      coverArt: p.coverArt,
      playlist: p,
      tracks: () async => _entries,
    ).then((_) async {
      // The playlist is gone after "Delete playlist".
      if (!mounted) return;
      final exists = (await ref.read(playlistsProvider.future))
          .any((x) => x.id == p.id);
      if (!exists && mounted) context.pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    final playlist = widget.playlist;
    final editable =
        ownsPlaylist(ref, playlist) && !ref.watch(isOfflineProvider);
    return CollectionView(
      coverArt: playlist.headerCover,
      title: playlist.name,
      subtitle: playlist.owner,
      details:
          '${countOf(_entries.length, 'song')} · ${formatDuration(playlist.duration)}',
      tracks: _entries,
      pinKind: PinKind.playlist,
      pinId: playlist.id,
      actions: [
        if (editable)
          IconButton(
            tooltip: 'Add songs',
            icon: const Icon(Icons.playlist_add),
            onPressed: _addSongs,
          ),
        IconButton(icon: const Icon(Icons.more_vert), onPressed: _showMenu),
      ],
      slivers: [
        if (playlist.comment case final comment?)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(comment, style: TextStyle(color: context.muted)),
            ),
          ),
        if (_entries.isEmpty && editable)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: FilledButton.tonalIcon(
                  icon: const Icon(Icons.playlist_add),
                  label: const Text('Add songs'),
                  onPressed: _addSongs,
                ),
              ),
            ),
          ),
        if (!editable)
          SliverList.builder(
            itemCount: _entries.length,
            itemBuilder: (context, i) =>
                TrackTile(tracks: _entries, index: i, playlistId: playlist.id),
          )
        else
          SliverReorderableList(
            itemCount: _entries.length,
            onReorderItem: _move,
            itemBuilder: (context, i) => ReorderableDelayedDragStartListener(
              key: ValueKey('${_entries[i].id}-$i'),
              index: i,
              child: Dismissible(
                key: ValueKey('dismiss-${_entries[i].id}-$i'),
                direction: DismissDirection.endToStart,
                onDismissed: (_) => _remove(i),
                background: Container(
                  color: Colors.red.shade900,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 16),
                  child: const Icon(Icons.delete, color: Colors.white),
                ),
                child: TrackTile(
                  tracks: _entries,
                  index: i,
                  playlistId: playlist.id,
                  handle: ReorderableDragStartListener(
                    index: i,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Icon(Icons.drag_handle, color: context.faint),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

extension on List<Track> {
  List<String> get ids => [for (final t in this) t.id];
}

extension on Playlist {
  /// The cover of the header: the playlist's own, otherwise that of its first song with one.
  String? get headerCover =>
      coverArt ?? entries.map((t) => t.coverArt).nonNulls.firstOrNull;
}
