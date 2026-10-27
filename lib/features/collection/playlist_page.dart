import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../data/subsonic/models.dart';
import '../../downloads/download_manager.dart';
import '../../ui/messages.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/item_actions.dart';
import '../../ui/widgets/tiles.dart';
import 'collection_header.dart';
import '../home/home_page.dart';
import 'playlist_edit.dart';

final playlistProvider = FutureProvider.autoDispose.family<Playlist, String>((
  ref,
  id,
) async {
  ref.watch(isOfflineProvider);
  return ref.watch(repositoryProvider)!.playlist(id);
});

class PlaylistPage extends ConsumerWidget {
  const PlaylistPage(this.id, {super.key});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlist = ref.watch(playlistProvider(id));
    return TransparentAppBarScaffold(
      actions: [
        if (playlist.value case final p?)
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () =>
                showItemActions(
                  context,
                  ref,
                  kind: PinKind.playlist,
                  id: p.id,
                  title: p.name,
                  subtitle: '${p.entries.length} songs',
                  coverArt: p.coverArt,
                  playlist: p,
                  tracks: () async => p.entries,
                ).then((_) async {
                  // The playlist is gone after "Delete playlist".
                  if (!context.mounted) return;
                  final exists = (await ref.read(
                    recentPlaylistsProvider.future,
                  )).any((x) => x.id == p.id);
                  if (!exists && context.mounted) context.pop();
                }),
          ),
      ],
      body: playlist.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => MessageView(
          '$e',
          onRetry: () => ref.invalidate(playlistProvider(id)),
        ),
        data: (playlist) => _PlaylistBody(playlist),
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

  Future<void> _save(Future<void> Function() edit) async {
    try {
      await edit();
      await playlistsChanged(ref, widget.playlist.id);
    } on Exception catch (e) {
      showMessage('$e');
      setState(() => _entries = widget.playlist.entries);
    }
  }

  void _move(int from, int to) {
    final entries = [..._entries];
    entries.insert(to, entries.removeAt(from));
    setState(() => _entries = entries);
    _save(
      () => ref
          .read(clientProvider)!
          .createPlaylist(
            playlistId: widget.playlist.id,
            songIds: [for (final t in entries) t.id],
          ),
    );
  }

  void _remove(int index) {
    setState(() => _entries = [..._entries]..removeAt(index));
    _save(
      () => ref
          .read(clientProvider)!
          .updatePlaylist(widget.playlist.id, songIndexesToRemove: [index]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final playlist = widget.playlist;
    final header = CollectionHeader(
      coverArt: playlist.coverArt,
      title: playlist.name,
      subtitle: playlist.owner,
      details:
          '${_entries.length} songs · ${formatDuration(playlist.duration)}',
      tracks: _entries,
      pinKind: PinKind.playlist,
      pinId: playlist.id,
    );
    final editable =
        ownsPlaylist(ref, playlist) && !ref.watch(isOfflineProvider);
    if (!editable) {
      return ListView.builder(
        padding: EdgeInsets.zero,
        itemCount: _entries.length + 1,
        itemBuilder: (context, i) =>
            i == 0 ? header : TrackTile(tracks: _entries, index: i - 1),
      );
    }
    return ReorderableListView.builder(
      padding: EdgeInsets.zero,
      header: header,
      buildDefaultDragHandles: false,
      itemCount: _entries.length,
      onReorderItem: _move,
      itemBuilder: (context, i) => Dismissible(
        key: ValueKey('${_entries[i].id}-$i'),
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
          handle: ReorderableDragStartListener(
            index: i,
            child: Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Icon(Icons.drag_handle, color: context.faint),
            ),
          ),
        ),
      ),
    );
  }
}
