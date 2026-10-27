import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/playback_providers.dart';
import '../../data/music_assistant/ma_client.dart';
import '../../data/music_assistant/ma_models.dart';
import '../../ui/messages.dart';

/// Opens the output picker. Its icon shows when a Music Assistant player is the output.
class OutputButton extends ConsumerWidget {
  const OutputButton({super.key, this.showName = false});

  final bool showName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final output = ref.watch(outputProvider);
    final configured = ref.watch(maCredentialsProvider) != null;
    if (!configured && !showName) return const SizedBox.shrink();
    final color = output == null ? null : Theme.of(context).colorScheme.primary;
    final icon = Icon(
      output == null ? Icons.speaker_group_outlined : Icons.speaker_group,
      color: color,
    );
    final name = ref.watch(nowPlayingProvider).value?.outputName;
    if (showName && name != null) {
      return TextButton.icon(
        onPressed: () => showOutputSheet(context),
        icon: icon,
        label: Text(name, style: TextStyle(color: color)),
      );
    }
    return IconButton(
      tooltip: 'Play on',
      icon: icon,
      onPressed: () => showOutputSheet(context),
    );
  }
}

Future<void> showOutputSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      builder: (_) => const _OutputSheet(),
    );

class _OutputSheet extends ConsumerWidget {
  const _OutputSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final output = ref.watch(outputProvider);
    final credentials = ref.watch(maCredentialsProvider);
    final status = ref.watch(maStatusProvider).value;
    final players = ref.watch(maPlayersProvider).value ?? const [];
    final router = GoRouter.of(context);

    return SafeArea(
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
                'Play on',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            _OutputTile(
              icon: Icons.smartphone,
              title: 'This device',
              selected: output == null,
              onTap: () {
                runPlayback(() => switchOutput(ref, null));
                Navigator.pop(context);
              },
            ),
            if (credentials == null)
              ListTile(
                leading: const Icon(Icons.add),
                title: const Text('Connect Music Assistant'),
                subtitle: const Text('Play on your speakers in sync'),
                onTap: () {
                  Navigator.pop(context);
                  router.push('/settings/music-assistant');
                },
              )
            else if (status != MaConnectionStatus.connected)
              ListTile(
                leading: status == MaConnectionStatus.connecting
                    ? const SizedBox.square(
                        dimension: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(
                        Icons.error_outline,
                        color: Colors.orangeAccent,
                      ),
                title: Text(switch (status) {
                  MaConnectionStatus.unauthorized =>
                    'Music Assistant rejected the sign-in',
                  MaConnectionStatus.connecting =>
                    'Connecting to Music Assistant…',
                  _ => 'Music Assistant is not reachable',
                }),
                onTap: () {
                  Navigator.pop(context);
                  router.push('/settings/music-assistant');
                },
              )
            else
              for (final player in players)
                _OutputTile(
                  icon: player.isGroup ? Icons.speaker_group : Icons.speaker,
                  title: player.name,
                  subtitle: switch (player.state) {
                    MaPlaybackState.playing => 'Playing',
                    MaPlaybackState.paused => 'Paused',
                    _ => null,
                  },
                  selected: output == player.id,
                  onTap: () {
                    runPlayback(() => switchOutput(ref, player.id));
                    Navigator.pop(context);
                  },
                ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _OutputTile extends StatelessWidget {
  const _OutputTile({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? Theme.of(context).colorScheme.primary : null;
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(
        title,
        style: TextStyle(
          color: color,
          fontWeight: selected ? FontWeight.w700 : null,
        ),
      ),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: selected ? Icon(Icons.check, color: color) : null,
      onTap: onTap,
    );
  }
}
