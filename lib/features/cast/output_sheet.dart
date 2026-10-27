import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/playback_providers.dart';
import '../../data/music_assistant/ma_client.dart';
import '../../data/music_assistant/ma_models.dart';
import '../../playback/ma_playback_controller.dart';
import '../../ui/messages.dart';

/// Opens the output picker. It shows once Music Assistant is set up, highlighted while a player is the output.
class OutputButton extends ConsumerWidget {
  const OutputButton({super.key, this.showName = false});

  final bool showName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(maCredentialsProvider) == null) {
      return const SizedBox.shrink();
    }
    final output = ref.watch(outputProvider);
    final color = output == null ? null : Theme.of(context).colorScheme.primary;
    final icon = Icon(
      output == null ? Icons.cast : Icons.cast_connected,
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

/// A tap on a player moves playback there. While a player is the output, the checkbox of another player adds it to the group or removes it.
class _OutputSheet extends ConsumerWidget {
  const _OutputSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final output = ref.watch(outputProvider);
    final status = ref.watch(maStatusProvider).value;
    final players = ref.watch(maPlayersProvider).value ?? const [];
    final router = GoRouter.of(context);

    final leader = players.where((p) => p.id == output).firstOrNull;
    bool isMember(MaPlayer p) =>
        leader != null &&
        (p.syncedTo == leader.id ||
            (p.id != leader.id && leader.groupMembers.contains(p.id)));
    final shown = players.where((p) => p.selectable || isMember(p)).toList();

    void select(String? id) {
      Navigator.pop(context);
      runPlayback(() => switchOutput(ref, id));
    }

    Future<void> toggleMember(MaPlayer p, bool add) async {
      final controller = ref.read(playbackControllerProvider);
      if (controller is MusicAssistantPlaybackController) {
        await controller.setMembers(
          add: add ? [p.id] : const [],
          remove: add ? const [] : [p.id],
        );
      }
    }

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
              onTap: () => select(null),
            ),
            if (status != MaConnectionStatus.connected)
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
              for (final player in shown)
                _OutputTile(
                  icon: player.isGroup ? Icons.speaker_group : Icons.speaker,
                  title: player.name,
                  subtitle: isMember(player)
                      ? 'In group'
                      : switch (player.state) {
                          MaPlaybackState.playing => 'Playing',
                          MaPlaybackState.paused => 'Paused',
                          _ => null,
                        },
                  selected: output == player.id,
                  onTap: () => select(player.id),
                  member:
                      leader == null ||
                          player.id == leader.id ||
                          !(isMember(player) ||
                              leader.canGroupWith.contains(player.id))
                      ? null
                      : isMember(player),
                  onMemberChanged: (add) => toggleMember(player, add),
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
    this.member,
    this.onMemberChanged,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  /// Whether the player is in the group of the output; null when it cannot join it.
  final bool? member;
  final ValueChanged<bool>? onMemberChanged;

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
      trailing: selected
          ? Icon(Icons.check, color: color)
          : member == null
          ? null
          : Checkbox(
              value: member,
              onChanged: (v) => onMemberChanged?.call(v ?? false),
            ),
      onTap: onTap,
    );
  }
}
