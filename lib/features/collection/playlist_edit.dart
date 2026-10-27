import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/subsonic/models.dart';
import '../../downloads/download_manager.dart';
import '../../ui/messages.dart';
import '../home/home_page.dart';
import 'playlist_page.dart';

/// Whether the signed-in person may edit [playlist].
bool ownsPlaylist(WidgetRef ref, Playlist playlist) {
  final owner = playlist.owner;
  return owner == null || owner == ref.read(credentialsProvider)?.username;
}

/// Reloads the playlist lists and, when [id] is downloaded, its downloaded tracks.
Future<void> playlistsChanged(WidgetRef ref, [String? id]) async {
  ref.invalidate(recentPlaylistsProvider);
  if (id == null) return;
  ref.invalidate(playlistProvider(id));
  final manager = ref.read(downloadManagerProvider);
  final pinned =
      (await manager?.watchPin(PinKind.playlist, id).first)?.pinned ?? false;
  if (pinned) await manager!.pin(PinKind.playlist, id);
}

Future<String?> _askName(
  BuildContext context, {
  required String title,
  String initial = '',
}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Name'),
        onSubmitted: (v) => Navigator.pop(context, v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text.trim()),
          child: const Text('Save'),
        ),
      ],
    ),
  ).whenComplete(controller.dispose);
}

/// Lets the person pick one of their playlists, or create one, and adds the tracks to it.
Future<void> showAddToPlaylist(
  BuildContext context,
  WidgetRef ref,
  Future<List<Track>> Function() tracks,
) async {
  final client = ref.read(clientProvider)!;
  final playlists = (await ref.read(recentPlaylistsProvider.future))
      .where((p) => ownsPlaylist(ref, p))
      .toList();
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
              leading: const Icon(Icons.add),
              title: const Text('New playlist'),
              onTap: () => Navigator.pop(context, 'new'),
            ),
            for (final p in playlists)
              ListTile(
                leading: const Icon(Icons.queue_music),
                title: Text(p.name),
                subtitle: Text('${p.songCount} songs'),
                onTap: () => Navigator.pop(context, p),
              ),
          ],
        ),
      ),
    ),
  );
  if (choice == null || !context.mounted) return;
  final name = choice == 'new'
      ? await _askName(context, title: 'New playlist')
      : null;
  if (choice == 'new' && (name == null || name.isEmpty)) return;
  try {
    final ids = [for (final t in await tracks()) t.id];
    if (choice is Playlist) {
      await client.updatePlaylist(choice.id, songIdsToAdd: ids);
      await playlistsChanged(ref, choice.id);
      showMessage('Added to ${choice.name}');
    } else {
      await client.createPlaylist(name: name, songIds: ids);
      await playlistsChanged(ref);
      showMessage('Created $name');
    }
  } on Exception catch (e) {
    showMessage('$e');
  }
}

Future<void> renamePlaylist(
  BuildContext context,
  WidgetRef ref,
  Playlist playlist,
) async {
  final name = await _askName(
    context,
    title: 'Rename playlist',
    initial: playlist.name,
  );
  if (name == null || name.isEmpty || name == playlist.name) return;
  try {
    await ref.read(clientProvider)!.updatePlaylist(playlist.id, name: name);
    await playlistsChanged(ref, playlist.id);
  } on Exception catch (e) {
    showMessage('$e');
  }
}

/// Deletes the playlist after confirmation. Returns whether it was deleted.
Future<bool> deletePlaylist(
  BuildContext context,
  WidgetRef ref,
  Playlist playlist,
) async {
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
    await ref
        .read(downloadManagerProvider)
        ?.unpin(PinKind.playlist, playlist.id);
    await ref.read(clientProvider)!.deletePlaylist(playlist.id);
    await playlistsChanged(ref);
    return true;
  } on Exception catch (e) {
    showMessage('$e');
    return false;
  }
}
