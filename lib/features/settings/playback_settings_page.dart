import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../downloads/download_settings.dart';
import '../../playback/prefetch_cache.dart';
import '../../playback/replay_gain.dart';
import 'settings_section.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/backdrop.dart';

class PlaybackSettingsPage extends ConsumerWidget {
  const PlaybackSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget quality(
      String title,
      NotifierProvider<StreamingQualityNotifier, DownloadQuality> provider,
    ) => ListTile(
      title: Text(title),
      trailing: DropdownButton<DownloadQuality>(
        value: ref.watch(provider),
        underline: const SizedBox.shrink(),
        items: [
          for (final q in DownloadQuality.values)
            DropdownMenuItem(value: q, child: Text(q.label)),
        ],
        onChanged: (q) => ref.read(provider.notifier).set(q!),
      ),
    );

    return Backdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: const Text('Playback')),
        body: ListView(
          children: [
            const SettingsSection('Streaming quality'),
            quality('On Wi-Fi', wifiQualityProvider),
            quality('On cellular', cellularQualityProvider),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Downloaded music always plays from the file. The server transcodes streams below the original quality.',
                style: TextStyle(fontSize: 13),
              ),
            ),
            const SettingsSection('Songs ahead'),
            ListTile(
              title: const Text('Fetch upcoming songs'),
              subtitle: const Text(
                'The next three songs of the queue are fetched in full, so they play through gaps in the connection',
              ),
              trailing: DropdownButton<PrefetchMode>(
                value: ref.watch(prefetchModeProvider),
                underline: const SizedBox.shrink(),
                items: [
                  for (final m in PrefetchMode.values)
                    DropdownMenuItem(value: m, child: Text(m.label)),
                ],
                onChanged: (m) =>
                    ref.read(prefetchModeProvider.notifier).set(m!),
              ),
            ),
            ListTile(
              title: const Text('Space for songs ahead'),
              subtitle: const Text(
                'Above it, the songs played longest ago are deleted first',
              ),
              trailing: DropdownButton<int>(
                value: ref.watch(prefetchLimitProvider),
                underline: const SizedBox.shrink(),
                items: [
                  for (final b in prefetchLimits)
                    DropdownMenuItem(value: b, child: Text(formatBytes(b))),
                ],
                onChanged: (b) =>
                    ref.read(prefetchLimitProvider.notifier).set(b!),
              ),
            ),
            ListTile(
              title: const Text('Clear songs ahead'),
              subtitle: Text(switch (ref.watch(prefetchSizeProvider)) {
                AsyncData(:final value) => '${formatBytes(value)} in use',
                _ => '…',
              }),
              onTap: () => ref.read(clearPrefetchCacheProvider)(),
            ),
            const SettingsSection('Loudness'),
            ListTile(
              title: const Text('Normalise volume'),
              subtitle: const Text(
                'Uses the ReplayGain values the server reports. Album keeps the differences between the songs of an album.',
              ),
              trailing: DropdownButton<ReplayGainMode>(
                value: ref.watch(replayGainProvider),
                underline: const SizedBox.shrink(),
                items: [
                  for (final m in ReplayGainMode.values)
                    DropdownMenuItem(value: m, child: Text(m.label)),
                ],
                onChanged: (m) => ref.read(replayGainProvider.notifier).set(m!),
              ),
            ),
            const SettingsSection('Transitions'),
            ListTile(
              title: const Text('Crossfade'),
              subtitle: const Text(
                'One song fades into the next. Songs of the same album always follow each other without a fade.',
              ),
              trailing: DropdownButton<int>(
                value: ref.watch(crossfadeProvider),
                underline: const SizedBox.shrink(),
                items: [
                  for (final s in CrossfadeNotifier.choices)
                    DropdownMenuItem(
                      value: s,
                      child: Text(s == 0 ? 'Off' : '$s s'),
                    ),
                ],
                onChanged: (s) => ref.read(crossfadeProvider.notifier).set(s!),
              ),
            ),
            const SettingsSection('Listening history'),
            SwitchListTile(
              title: const Text('Report plays to the server'),
              subtitle: const Text(
                'Keeps "Recently played" and "Most played" up to date',
              ),
              value: ref.watch(scrobblingProvider),
              onChanged: (v) => ref.read(scrobblingProvider.notifier).set(v),
            ),
          ],
        ),
      ),
    );
  }
}
