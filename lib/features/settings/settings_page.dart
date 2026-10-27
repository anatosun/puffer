import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/playback_providers.dart';
import '../../app/providers.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final credentials = ref.watch(credentialsProvider);
    final client = ref.watch(clientProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.dns_outlined),
            title: Text(credentials?.baseUrl ?? ''),
            subtitle: Text(
              [
                credentials?.username,
                if (client != null && client.extensions.isNotEmpty)
                  'OpenSubsonic',
              ].nonNulls.join(' · '),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('Experience'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/experience'),
          ),
          ListTile(
            leading: const Icon(Icons.play_circle_outline),
            title: const Text('Playback'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/playback'),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.cloud_off),
            title: const Text('Offline mode'),
            subtitle: const Text('Show and play only downloaded music'),
            value: ref.watch(manualOfflineProvider),
            onChanged: (v) => ref.read(manualOfflineProvider.notifier).set(v),
          ),
          ListTile(
            leading: const Icon(Icons.speaker_group_outlined),
            title: const Text('Music Assistant'),
            subtitle: Text(
              ref.watch(maCredentialsProvider)?.baseUrl.host ??
                  'Play on your speakers',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/music-assistant'),
          ),
          ListTile(
            leading: const Icon(Icons.arrow_circle_down_outlined),
            title: const Text('Downloads'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/downloads'),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.redAccent),
            title: const Text(
              'Sign out',
              style: TextStyle(color: Colors.redAccent),
            ),
            subtitle: const Text('Removes all downloads from this device'),
            onTap: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Sign out?'),
                  content: const Text(
                    'All downloads are removed from this device.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Sign out'),
                    ),
                  ],
                ),
              );
              if (confirmed ?? false) {
                await ref.read(playbackProvider).stop();
                await ref.read(credentialsProvider.notifier).signOut();
              }
            },
          ),
        ],
      ),
    );
  }
}
