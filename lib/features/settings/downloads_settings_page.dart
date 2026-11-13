import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../data/db/database.dart';
import '../../data/subsonic/models.dart';
import '../../downloads/download_manager.dart';
import '../../downloads/download_settings.dart';
import '../../ui/messages.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/download_indicator.dart';
import 'settings_section.dart';
import '../../ui/widgets/backdrop.dart';

/// The downloaded songs of one album: its ID, when the songs name it, and their size.
typedef AlbumUsage = ({String? id, String name, int bytes});

/// The downloaded songs of one artist, with their albums.
typedef ArtistUsage = ({String artist, int bytes, List<AlbumUsage> albums});

/// The size of the downloaded [tracks] by artist and album, from [sizes] by track ID, largest first.
List<ArtistUsage> downloadUsage(List<Track> tracks, Map<String, int> sizes) {
  int bytes(Iterable<Track> songs) => songs.map((t) => sizes[t.id] ?? 0).sum;
  return [
    for (final MapEntry(key: artist, value: songs) in groupBy(
      tracks,
      (t) => t.artist ?? 'Unknown artist',
    ).entries)
      (
        artist: artist,
        bytes: bytes(songs),
        albums: [
          for (final album in groupBy(
            songs,
            (t) => t.albumId ?? t.album ?? '',
          ).values)
            (
              id: album.first.albumId,
              name: album.first.album ?? 'Unknown album',
              bytes: bytes(album),
            ),
        ]..sort((a, b) => b.bytes.compareTo(a.bytes)),
      ),
  ]..sort((a, b) => b.bytes.compareTo(a.bytes));
}

/// The total size of the downloads and their size per artist and album.
final _usageProvider = FutureProvider.autoDispose<(int, List<ArtistUsage>)>((
  ref,
) async {
  ref.watch(completeTrackIdsProvider);
  final db = ref.watch(databaseProvider);
  final repository = ref.watch(repositoryProvider);
  if (repository == null) return (0, const <ArtistUsage>[]);
  final files = await (db.select(
    db.trackFiles,
  )..where((t) => t.status.equalsValue(FileStatus.complete))).get();
  final sizes = {for (final f in files) f.trackId: f.size ?? 0};
  final tracks = await repository.cachedTracks(sizes.keys);
  return (sizes.values.sum, downloadUsage(tracks, sizes));
});

final _failedCountProvider = StreamProvider.autoDispose<int>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.trackFiles)
        ..where((t) => t.status.equalsValue(FileStatus.failed)))
      .watch()
      .map((r) => r.length);
});

const _limits = [2, 4, 8, 16, 32, 64];
const _simultaneous = [1, 2, 3, 4, 6];

class DownloadsSettingsPage extends ConsumerWidget {
  const DownloadsSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(downloadSettingsProvider);
    final updater = ref.read(downloadSettingsUpdaterProvider);
    final usage = ref.watch(_usageProvider).value;
    final failed = ref.watch(_failedCountProvider).value ?? 0;
    final manager = ref.watch(downloadManagerProvider);

    return Backdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Downloads'),
          actions: [
            if (manager != null && !ref.watch(isOfflineProvider))
              const _RefreshButton(),
            if (manager != null)
              IconButton(
                tooltip: 'Remove all downloads',
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                onPressed: () => _removeAll(context, ref),
              ),
          ],
        ),
        body: ListView(
          children: [
            ListTile(
              title: Text(
                usage == null ? '…' : formatBytes(usage.$1),
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              subtitle: const Text('Downloaded music on this device'),
            ),
            if (failed > 0)
              ListTile(
                leading: const Icon(
                  Icons.error_outline,
                  color: Colors.orangeAccent,
                ),
                title: Text('$failed downloads failed'),
                trailing: TextButton(
                  onPressed: manager?.retryFailed,
                  child: const Text('Retry'),
                ),
              ),
            const SettingsSection('Quality'),
            RadioGroup<DownloadQuality>(
              groupValue: settings.quality,
              onChanged: (q) => updater.update(settings.copyWith(quality: q)),
              child: Column(
                children: [
                  for (final q in DownloadQuality.values)
                    RadioListTile<DownloadQuality>(
                      value: q,
                      title: Text(q.label),
                    ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'The quality applies to new downloads. Transcoding is done by the server.',
                style: TextStyle(color: context.muted, fontSize: 13),
              ),
            ),
            const SettingsSection('Downloading'),
            SwitchListTile(
              title: const Text('Download over cellular'),
              value: settings.overCellular,
              onChanged: (v) =>
                  updater.update(settings.copyWith(overCellular: v)),
            ),
            ListTile(
              title: const Text('Simultaneous downloads'),
              trailing: DropdownButton<int>(
                value: _simultaneous.contains(settings.simultaneous)
                    ? settings.simultaneous
                    : 3,
                underline: const SizedBox.shrink(),
                items: [
                  for (final n in _simultaneous)
                    DropdownMenuItem(value: n, child: Text('$n')),
                ],
                onChanged: (n) =>
                    updater.update(settings.copyWith(simultaneous: n)),
              ),
            ),
            SwitchListTile(
              title: const Text('Keep the screen on'),
              subtitle: const Text('While downloads in progress show'),
              value: ref.watch(keepScreenOnWhileDownloadingProvider),
              onChanged: (v) => ref
                  .read(keepScreenOnWhileDownloadingProvider.notifier)
                  .set(v),
            ),
            SwitchListTile(
              title: const Text('Automatic downloads'),
              subtitle: const Text(
                'Download songs, albums and artists when you add them to your library',
              ),
              value: settings.automaticDownloads,
              onChanged: (v) =>
                  updater.update(settings.copyWith(automaticDownloads: v)),
            ),
            SwitchListTile(
              title: const Text('Optimize storage'),
              subtitle: const Text(
                'Remove automatically downloaded songs you have not played recently when downloads exceed the limit',
              ),
              value: settings.optimizeStorage,
              onChanged: (v) =>
                  updater.update(settings.copyWith(optimizeStorage: v)),
            ),
            if (settings.optimizeStorage)
              ListTile(
                title: const Text('Storage limit'),
                trailing: DropdownButton<int>(
                  value: _limits.contains(settings.storageLimitBytes >> 30)
                      ? settings.storageLimitBytes >> 30
                      : 8,
                  items: [
                    for (final gb in _limits)
                      DropdownMenuItem(value: gb, child: Text('$gb GB')),
                  ],
                  onChanged: (gb) => updater.update(
                    settings.copyWith(storageLimitBytes: gb! << 30),
                  ),
                ),
              ),
            if (libraryFolderAvailable) ...[
              const SettingsSection('Library folder'),
              const _LibraryFolder(),
            ],
            if (usage != null && usage.$2.isNotEmpty) ...[
              const SettingsSection('Storage by artist'),
              for (final artist in usage.$2)
                ExpansionTile(
                  title: Text(artist.artist),
                  trailing: Text(
                    formatBytes(artist.bytes),
                    style: TextStyle(color: context.muted),
                  ),
                  children: [
                    for (final album in artist.albums) _AlbumUsageRow(album),
                  ],
                ),
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

/// Asks before removing every download, then removes them.
Future<void> _removeAll(BuildContext context, WidgetRef ref) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Remove all downloads?'),
      content: const Text(
        'Your library stays on the server and can be streamed.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: destructiveButton,
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Remove all'),
        ),
      ],
    ),
  );
  if (confirmed ?? false) await ref.read(removeAllDownloadsProvider)();
}

/// Syncs every download with the server: new songs of the downloaded playlists, missing covers and waveforms, and the files that are missing or failed.
class _RefreshButton extends ConsumerWidget {
  const _RefreshButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(downloadRefreshProvider)) {
      return const SizedBox.square(
        dimension: 48,
        child: Center(
          child: SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    return IconButton(
      tooltip: 'Refresh downloads',
      icon: const Icon(Icons.refresh),
      onPressed: () async {
        final failed = await ref.read(downloadRefreshProvider.notifier).run();
        if (failed == null) return;
        showMessage(
          failed == 0
              ? 'Downloads are up to date'
              : '${countOf(failed, 'download')} could not be checked',
        );
      },
    );
  }
}

/// An album of the storage by artist. It opens the album, and its own download can be removed here; songs that another download holds stay.
class _AlbumUsageRow extends ConsumerWidget {
  const _AlbumUsageRow(this.album);

  final AlbumUsage album;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = album.id;
    final manager = ref.watch(downloadManagerProvider);
    final pinned =
        id != null &&
        (ref.watch(pinStateProvider((PinKind.album, id))).value?.pinned ??
            false);
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.only(left: 32, right: 4),
      title: Text(album.name),
      onTap: id == null ? null : () => context.push('/album/$id'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            formatBytes(album.bytes),
            style: TextStyle(color: context.muted),
          ),
          // The button keeps its room on every row, so the sizes line up.
          SizedBox.square(
            dimension: 48,
            child: pinned && manager != null
                ? IconButton(
                    tooltip: 'Remove download',
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: () async {
                      if (await confirmRemoveDownload(context)) {
                        await manager.unpin(PinKind.album, id);
                      }
                    },
                  )
                : null,
          ),
        ],
      ),
    );
  }
}

/// The library folder a person picks, on the desktop.
class _LibraryFolder extends ConsumerWidget {
  const _LibraryFolder();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final folder = ref.watch(libraryFolderProvider);
    // Without a server there is no download manager to move the files.
    final ready = ref.watch(downloadManagerProvider) != null;
    final hint = Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Text(
        'Songs go in Music/Artist/Album/01 Title with the album cover, an M3U8 file for each downloaded playlist in Playlists, and an iTunes library at the top for other players and DJ software. Changing the folder moves the songs already downloaded.',
        style: TextStyle(color: context.muted, fontSize: 13),
      ),
    );
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.folder_outlined),
          title: const Text('Folder'),
          subtitle: Text(folder ?? 'None: downloads stay inside Puffer'),
          trailing: folder == null
              ? null
              : TextButton(
                  onPressed: ready ? () => _move(context, ref, null) : null,
                  child: const Text('Turn off'),
                ),
          enabled: ready,
          onTap: () async {
            final picked = await getDirectoryPath(
              initialDirectory: folder,
              confirmButtonText: 'Use this folder',
            );
            if (picked != null && context.mounted) {
              await _move(context, ref, picked);
            }
          },
        ),
        hint,
      ],
    );
  }

  /// Moves the downloads with a dialog that stays while the files move, and reports a folder that cannot be written.
  Future<void> _move(
    BuildContext context,
    WidgetRef ref,
    String? folder,
  ) async {
    final move = ref.read(setLibraryFolderProvider)(folder);
    final navigator = Navigator.of(context, rootNavigator: true);
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        useRootNavigator: true,
        builder: (_) => const PopScope(
          canPop: false,
          child: AlertDialog(
            content: Row(
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 24),
                Expanded(child: Text('Moving downloads…')),
              ],
            ),
          ),
        ),
      ),
    );
    try {
      await move;
    } on FileSystemException {
      showMessage('Puffer cannot write to that folder');
    } finally {
      navigator.pop();
    }
  }
}
