import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/db/database.dart';
import '../../downloads/download_settings.dart';
import '../../ui/theme.dart';
import 'settings_section.dart';

class _ArtistUsage {
  const _ArtistUsage(this.artist, this.bytes, this.albums);

  final String artist;
  final int bytes;
  final Map<String, int> albums;
}

/// Downloaded bytes per artist and album, largest first.
final _usageProvider = FutureProvider.autoDispose<(int, List<_ArtistUsage>)>((
  ref,
) async {
  ref.watch(completeTrackIdsProvider);
  final db = ref.watch(databaseProvider);
  final repository = ref.watch(repositoryProvider);
  if (repository == null) return (0, const <_ArtistUsage>[]);
  final files = await (db.select(
    db.trackFiles,
  )..where((t) => t.status.equalsValue(FileStatus.complete))).get();
  final sizes = {for (final f in files) f.trackId: f.size ?? 0};
  final tracks = await repository.cachedTracks(sizes.keys);
  final usage = [
    for (final byArtist in groupBy(
      tracks,
      (t) => t.artist ?? 'Unknown artist',
    ).entries)
      _ArtistUsage(byArtist.key, byArtist.value.map((t) => sizes[t.id]!).sum, {
        for (final byAlbum in groupBy(
          byArtist.value,
          (t) => t.album ?? 'Unknown album',
        ).entries)
          byAlbum.key: byAlbum.value.map((t) => sizes[t.id]!).sum,
      }),
  ]..sort((a, b) => b.bytes.compareTo(a.bytes));
  return (sizes.values.sum, usage);
});

final _failedCountProvider = StreamProvider.autoDispose<int>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.trackFiles)
        ..where((t) => t.status.equalsValue(FileStatus.failed)))
      .watch()
      .map((r) => r.length);
});

const _limits = [2, 4, 8, 16, 32, 64];

class DownloadsSettingsPage extends ConsumerWidget {
  const DownloadsSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(downloadSettingsProvider);
    final notifier = ref.read(downloadSettingsProvider.notifier);
    final usage = ref.watch(_usageProvider).value;
    final failed = ref.watch(_failedCountProvider).value ?? 0;
    final manager = ref.watch(downloadManagerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Downloads')),
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
            onChanged: (q) => notifier.update(settings.copyWith(quality: q)),
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
                notifier.update(settings.copyWith(overCellular: v)),
          ),
          SwitchListTile(
            title: const Text('Automatic downloads'),
            subtitle: const Text(
              'Download songs, albums and artists when you add them to your library',
            ),
            value: settings.automaticDownloads,
            onChanged: (v) =>
                notifier.update(settings.copyWith(automaticDownloads: v)),
          ),
          SwitchListTile(
            title: const Text('Optimize storage'),
            subtitle: const Text(
              'Remove automatically downloaded songs you have not played recently when downloads exceed the limit',
            ),
            value: settings.optimizeStorage,
            onChanged: (v) =>
                notifier.update(settings.copyWith(optimizeStorage: v)),
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
                onChanged: (gb) => notifier.update(
                  settings.copyWith(storageLimitBytes: gb! << 30),
                ),
              ),
            ),
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
                  for (final album in artist.albums.entries)
                    ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.only(
                        left: 32,
                        right: 16,
                      ),
                      title: Text(album.key),
                      trailing: Text(
                        formatBytes(album.value),
                        style: TextStyle(color: context.muted),
                      ),
                    ),
                ],
              ),
          ],
          const Divider(height: 32),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
            title: const Text(
              'Remove all downloads',
              style: TextStyle(color: Colors.redAccent),
            ),
            onTap: manager == null
                ? null
                : () async {
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
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Remove all'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed ?? false) {
                      await manager.removeAll();
                      await ref.read(artworkStoreProvider)?.clear();
                    }
                  },
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
