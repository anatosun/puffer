import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ui/theme.dart';
import '../../app/playlist_history.dart';
import '../../app/providers.dart';
import '../../data/subsonic/models.dart';
import '../../downloads/download_manager.dart';
import '../../ui/messages.dart';
import '../../ui/widgets/text_input_dialog.dart';
import '../../ui/widgets/tiles.dart';
import '../home/home_page.dart';
import 'playlist_page.dart';

/// Whether the signed-in person may edit [playlist].
bool ownsPlaylist(WidgetRef ref, Playlist playlist) {
  final owner = playlist.owner;
  return owner == null || owner == ref.read(credentialsProvider)?.username;
}

/// Reloads the playlist lists and, when [id] is downloaded, its downloaded tracks. The playlist is fetched into the cache before its page reloads, so the page does not show the order from before the edit.
Future<void> playlistsChanged(ProviderContainer container, [String? id]) async {
  container.invalidate(playlistsProvider);
  if (id == null) return;
  try {
    await container.read(repositoryProvider)?.playlist(id);
  } on Exception {
    // The page reloads from the server anyway.
  }
  container.invalidate(playlistProvider(id));
  final manager = container.read(downloadManagerProvider);
  final pinned =
      (await manager?.watchPin(PinKind.playlist, id).first)?.pinned ?? false;
  if (pinned) await manager!.pin(PinKind.playlist, id);
}

Future<String?> _askName(
  BuildContext context, {
  required String title,
  String initial = '',
}) => askText(context, title: title, initial: initial, label: 'Name');

/// Lets the person pick one of their playlists, or create one, and adds the tracks to it.
Future<void> showAddToPlaylist(
  BuildContext context,
  WidgetRef ref,
  Future<List<Track>> Function() tracks,
) async {
  // The ref of a menu that closed before a dialog returns is unusable; the container of the app is not.
  final container = ProviderScope.containerOf(context, listen: false);
  final client = container.read(clientProvider)!;
  final playlists = byRecency(
    (await container.read(playlistsProvider.future))
        .where((p) => ownsPlaylist(ref, p))
        .toList(),
    container.read(playlistHistoryProvider),
  );
  if (!context.mounted) return;
  final choice = await showModalBottomSheet<Object>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Add to playlist',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            ListTile(
              // A square the size of the covers below, so the titles line up.
              leading: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Icon(Icons.add),
              ),
              title: const Text('New playlist'),
              onTap: () => Navigator.pop(context, 'new'),
            ),
            for (final p in playlists)
              ListTile(
                leading: PlaylistArtwork(p, size: 48),
                title: Text(p.name),
                subtitle: Text(countOf(p.songCount, 'song')),
                onTap: () => Navigator.pop(context, p),
              ),
          ],
        ),
      ),
    ),
  );
  if (choice == null || !context.mounted) return;
  try {
    final ids = [for (final t in await tracks()) t.id];
    if (!context.mounted) return;
    if (choice is! Playlist) {
      await createPlaylistFrom(context, ref, ids);
      return;
    }
    final repository = container.read(repositoryProvider)!;
    final current =
        await repository.cachedPlaylist(choice.id) ??
        await repository.playlist(choice.id);
    if (!context.mounted) return;
    final add = await _confirmDuplicates(
      context,
      choice.name,
      ids,
      splitDuplicates(ids, current.entries.map((t) => t.id)),
    );
    if (add == null || add.isEmpty) return;
    await client.updatePlaylist(choice.id, songIdsToAdd: add);
    await playlistsChanged(container, choice.id);
    showMessage('Added to ${choice.name}');
  } on Exception catch (e) {
    showMessage('$e');
  }
}

/// The songs of [ids] that [existing] does not hold yet, in order, and how many of [ids] it holds already.
({List<String> fresh, int duplicates}) splitDuplicates(
  List<String> ids,
  Iterable<String> existing,
) {
  final have = existing.toSet();
  final fresh = [
    for (final id in ids)
      if (!have.contains(id)) id,
  ];
  return (fresh: fresh, duplicates: ids.length - fresh.length);
}

/// The songs of [ids] to add when some are in the playlist [name] already: all of them, only the new ones, or null when the person cancels. Without duplicates, all of them without asking.
Future<List<String>?> _confirmDuplicates(
  BuildContext context,
  String name,
  List<String> ids,
  ({List<String> fresh, int duplicates}) split,
) async {
  if (split.duplicates == 0) return ids;
  final all = split.fresh.isEmpty;
  final total = split.fresh.length + split.duplicates;
  final choice = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(all ? 'Already in $name' : 'Some songs are in $name'),
      content: Text(
        all
            ? total == 1
                  ? 'This song is in the playlist already.'
                  : 'These songs are in the playlist already.'
            : '${split.duplicates} of $total songs are in the playlist already.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        if (!all)
          TextButton(
            onPressed: () => Navigator.pop(context, 'new'),
            child: const Text('Skip them'),
          ),
        FilledButton(
          onPressed: () => Navigator.pop(context, 'all'),
          child: const Text('Add anyway'),
        ),
      ],
    ),
  );
  return switch (choice) {
    'all' => ids,
    'new' => split.fresh,
    _ => null,
  };
}

/// Asks for a name, with [initialName] filled in, and creates a playlist of the songs [ids]. Used for "New playlist" in "Add to playlist" and for saving a queue.
Future<void> createPlaylistFrom(
  BuildContext context,
  WidgetRef ref,
  List<String> ids, {
  String initialName = '',
}) async {
  // The ref of a menu that closed before a dialog returns is unusable; the container of the app is not.
  final container = ProviderScope.containerOf(context, listen: false);
  final name = await _askName(
    context,
    title: 'New playlist',
    initial: initialName,
  );
  if (name == null || name.isEmpty) return;
  try {
    await container
        .read(clientProvider)!
        .createPlaylist(name: name, songIds: ids);
    await playlistsChanged(container);
    showMessage('Created $name');
  } on Exception catch (e) {
    showMessage('$e');
  }
}

/// Asks for a name and creates an empty playlist.
Future<void> createPlaylist(BuildContext context, WidgetRef ref) async {
  // The ref of a menu that closed before a dialog returns is unusable; the container of the app is not.
  final container = ProviderScope.containerOf(context, listen: false);
  final name = await _askName(context, title: 'New playlist');
  if (name == null || name.isEmpty) return;
  try {
    await container.read(clientProvider)!.createPlaylist(name: name);
    await playlistsChanged(container);
    showMessage('Created $name');
  } on Exception catch (e) {
    showMessage('$e');
  }
}

/// Edits the name, the description and whether other users see [playlist].
Future<void> editPlaylistDetails(
  BuildContext context,
  WidgetRef ref,
  Playlist playlist,
) async {
  // The ref of a menu that closed before a dialog returns is unusable; the container of the app is not.
  final container = ProviderScope.containerOf(context, listen: false);
  final edited = await showDialog<({String name, String comment, bool public})>(
    context: context,
    builder: (context) => _DetailsDialog(playlist),
  );
  if (edited == null || edited.name.isEmpty) return;
  final unchanged =
      edited.name == playlist.name &&
      edited.comment == (playlist.comment ?? '') &&
      edited.public == playlist.isPublic;
  if (unchanged) return;
  try {
    await container
        .read(clientProvider)!
        .updatePlaylist(
          playlist.id,
          name: edited.name,
          comment: edited.comment,
          isPublic: edited.public,
        );
    await playlistsChanged(container, playlist.id);
  } on Exception catch (e) {
    showMessage('$e');
  }
}

class _DetailsDialog extends StatefulWidget {
  const _DetailsDialog(this.playlist);

  final Playlist playlist;

  @override
  State<_DetailsDialog> createState() => _DetailsDialogState();
}

class _DetailsDialogState extends State<_DetailsDialog> {
  late final _name = TextEditingController(text: widget.playlist.name);
  late final _comment = TextEditingController(
    text: widget.playlist.comment ?? '',
  );
  late bool _public = widget.playlist.isPublic;

  @override
  void dispose() {
    _name.dispose();
    _comment.dispose();
    super.dispose();
  }

  void _save() => Navigator.pop(context, (
    name: _name.text.trim(),
    comment: _comment.text.trim(),
    public: _public,
  ));

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Edit playlist'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _comment,
            minLines: 1,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'Description'),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Public'),
            subtitle: const Text('Other users of the server see it'),
            value: _public,
            onChanged: (v) => setState(() => _public = v),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _save, child: const Text('Save')),
    ],
  );
}

/// Deletes the playlist after confirmation. Returns whether it was deleted.
Future<bool> deletePlaylist(
  BuildContext context,
  WidgetRef ref,
  Playlist playlist,
) async {
  // The ref of a menu that closed before a dialog returns is unusable; the container of the app is not.
  final container = ProviderScope.containerOf(context, listen: false);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Delete ${playlist.name}?'),
      content: const Text(
        'The playlist is deleted on the server. Its songs stay in your library.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (confirmed != true) return false;
  try {
    await container
        .read(downloadManagerProvider)
        ?.unpin(PinKind.playlist, playlist.id);
    await container.read(clientProvider)!.deletePlaylist(playlist.id);
    await playlistsChanged(container);
    return true;
  } on Exception catch (e) {
    showMessage('$e');
    return false;
  }
}
