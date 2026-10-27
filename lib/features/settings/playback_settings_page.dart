import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../downloads/download_settings.dart';
import 'settings_section.dart';

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

    return Scaffold(
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
    );
  }
}
