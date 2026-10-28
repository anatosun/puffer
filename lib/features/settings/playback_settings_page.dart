import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/sendspin_providers.dart';
import '../../sendspin/session.dart';
import '../../downloads/download_settings.dart';
import '../../playback/replay_gain.dart';
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
          const SettingsSection('Speaker'),
          const _SpeakerSettings(),
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

/// The phone as a Sendspin speaker of Music Assistant.
class _SpeakerSettings extends ConsumerWidget {
  const _SpeakerSettings();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(sendspinEnabledProvider);
    final name = ref.watch(sendspinNameProvider);
    final status =
        ref.watch(sendspinStatusProvider).value ?? const SendspinStatus();
    return Column(
      children: [
        SwitchListTile(
          title: const Text('Play as a speaker'),
          subtitle: const Text(
            'Music Assistant can play on this phone in sync with your other speakers, over Sendspin.',
          ),
          value: enabled,
          onChanged: (v) => ref.read(sendspinEnabledProvider.notifier).set(v),
        ),
        if (enabled) ...[
          ListTile(
            title: const Text('Speaker name'),
            subtitle: Text(name),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () async {
              final controller = TextEditingController(text: name);
              final value = await showDialog<String>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Speaker name'),
                  content: TextField(
                    controller: controller,
                    autofocus: true,
                    onSubmitted: (v) => Navigator.pop(context, v),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, controller.text),
                      child: const Text('Save'),
                    ),
                  ],
                ),
              );
              controller.dispose();
              if (value != null) {
                await ref.read(sendspinNameProvider.notifier).set(value);
              }
            },
          ),
          ListTile(
            leading: Icon(
              status.connected ? Icons.check_circle : Icons.wifi_tethering,
              color: status.connected ? Colors.green : null,
            ),
            title: Text(
              status.connected
                  ? 'Connected to ${status.serverName ?? 'Music Assistant'}'
                  : 'Waiting for Music Assistant',
            ),
            subtitle: Text(
              status.connected
                  ? [
                      if (status.groupName != null) 'Group ${status.groupName}',
                      if (status.playing) 'playing',
                    ].join(' · ')
                  : 'Music Assistant finds the phone on the local network. Approve "$name" there the first time.',
            ),
          ),
        ],
      ],
    );
  }
}
