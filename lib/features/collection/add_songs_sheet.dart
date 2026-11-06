import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/subsonic/models.dart';
import '../../ui/messages.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/artwork.dart';
import '../../ui/widgets/tiles.dart';
import 'playlist_edit.dart';

/// Songs on the server matching a search of the "Add songs" sheet.
final songSearchProvider = FutureProvider.autoDispose
    .family<List<Track>, String>((ref, query) async {
      if (query.trim().isEmpty) return const [];
      final repository = ref.watch(repositoryProvider);
      if (repository == null) return const [];
      return (await repository.search(query)).tracks;
    });

/// Adds songs to [playlist] one by one, in the order they are tapped, and reloads the playlist once when the sheet closes.
class PlaylistAdder {
  PlaylistAdder(this._add, Iterable<String> inPlaylist, {this.onError})
    : added = {...inPlaylist};

  final Future<void> Function(String songId) _add;

  /// Receives the failure of an add, whose song then shows no check.
  final void Function(Object error)? onError;

  /// The songs in the playlist, those added here included.
  final Set<String> added;
  bool changed = false;
  Future<void> _last = Future.value();

  /// Adds [songId], after the songs tapped before it.
  Future<void> add(String songId) {
    added.add(songId);
    changed = true;
    return _last = _last.then((_) => _add(songId)).catchError((Object e) {
      added.remove(songId);
      onError?.call(e);
    });
  }
}

/// A search over the songs of the server, each with a button that adds it to [playlist]. Songs in the playlist show a check.
Future<void> showAddSongs(
  BuildContext context,
  WidgetRef ref,
  Playlist playlist,
  Iterable<String> inPlaylist,
) async {
  final client = ref.read(clientProvider)!;
  final container = ProviderScope.containerOf(context, listen: false);
  final adder = PlaylistAdder(
    (id) => client.updatePlaylist(playlist.id, songIdsToAdd: [id]),
    inPlaylist,
    onError: (e) => showMessage('$e'),
  );
  await showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (context) => _AddSongs(playlist.name, adder),
  );
  if (adder.changed) {
    await adder._last;
    await playlistsChanged(container, playlist.id);
  }
}

class _AddSongs extends ConsumerStatefulWidget {
  const _AddSongs(this.name, this.adder);

  final String name;
  final PlaylistAdder adder;

  @override
  ConsumerState<_AddSongs> createState() => _AddSongsState();
}

class _AddSongsState extends ConsumerState<_AddSongs> {
  String _query = '';
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _typed(String text) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 300),
      () => setState(() => _query = text),
    );
  }

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(songSearchProvider(_query));
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.85,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Add songs to ${widget.name}',
                  prefixIcon: const Icon(Icons.search),
                ),
                onChanged: _typed,
              ),
            ),
            Expanded(
              child: results.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => MessageView('$e'),
                data: (tracks) => tracks.isEmpty
                    ? MessageView(
                        _query.trim().isEmpty
                            ? 'Search for songs to add'
                            : 'No matching songs',
                      )
                    : ListView.builder(
                        itemCount: tracks.length,
                        itemBuilder: (context, i) {
                          final track = tracks[i];
                          final inList = widget.adder.added.contains(track.id);
                          return ListTile(
                            leading: Artwork(
                              track.coverArt,
                              size: 44,
                              radius: 4,
                            ),
                            title: TrackTitle(track.title),
                            subtitle: TrackSubtitle(track.artist),
                            // A check that is no button, so it keeps its colour.
                            trailing: inList
                                ? Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Icon(
                                      Icons.check_circle,
                                      color: context.colors.primary,
                                      semanticLabel: 'In the playlist',
                                    ),
                                  )
                                : IconButton(
                                    tooltip: 'Add',
                                    icon: const Icon(Icons.add_circle_outline),
                                    onPressed: () {
                                      setState(() {});
                                      widget.adder.add(track.id).whenComplete(
                                        () {
                                          if (mounted) setState(() {});
                                        },
                                      );
                                    },
                                  ),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
