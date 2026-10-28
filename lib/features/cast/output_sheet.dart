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

/// A tap on a player moves playback there. While a player is the output, the checkbox of another player adds it to the group or removes it.
/// Players are listed by group: each player that leads, or plays on its own, followed by the players that follow it. A tap on a player moves playback there, taking a following player out of its group first. While a player is the output, the checkbox of another player adds it to the group or removes it; the unlink button ungroups.
class _OutputSheet extends ConsumerWidget {
  const _OutputSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final output = ref.watch(outputProvider);
    final status = ref.watch(maStatusProvider).value;
    final players = ref.watch(maPlayersProvider).value ?? const <MaPlayer>[];
    final client = ref.watch(maClientProvider);
    final router = GoRouter.maybeOf(context);
    final byId = {for (final p in players) p.id: p};

    /// The players following [leader], from their own state and from the member list of the leader.
    List<MaPlayer> membersOf(MaPlayer leader) => {
      for (final p in players)
        if (p.syncedTo == leader.id) p.id: p,
      for (final id in leader.groupMembers)
        if (id != leader.id && byId[id] != null) id: byId[id]!,
    }.values.toList();

    final current = byId[output];
    bool inCurrentGroup(MaPlayer p) =>
        current != null && membersOf(current).any((m) => m.id == p.id);

    void select(MaPlayer? player) {
      Navigator.pop(context);
      runPlayback(() async {
        // A player that follows another plays the whole group; picking it alone takes it out first.
        if (player != null && player.syncedTo != null) {
          await client?.command('players/cmd/ungroup', {
            'player_id': player.id,
          });
        }
        await switchOutput(ref, player?.id);
      });
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

    Future<void> ungroup(List<String> ids) => runPlayback(() async {
      await client?.command('players/cmd/ungroup_many', {'player_ids': ids});
    });

    Widget? groupControl(MaPlayer player, {required bool following}) {
      if (current != null &&
          player.id != current.id &&
          (inCurrentGroup(player) ||
              current.canGroupWith.contains(player.id))) {
        return Checkbox(
          value: inCurrentGroup(player),
          onChanged: (v) => toggleMember(player, v ?? false),
        );
      }
      if (following) {
        return IconButton(
          tooltip: 'Ungroup',
          icon: const Icon(Icons.link_off),
          onPressed: () => ungroup([player.id]),
        );
      }
      return null;
    }

    final rows = <Widget>[];
    final followers = {
      for (final p in players)
        if (p.selectable && p.type != 'group') ...membersOf(p).map((m) => m.id),
    };
    for (final leader in players.where(
      (p) => p.selectable && !followers.contains(p.id),
    )) {
      final members = membersOf(leader);
      // A group player is a fixed group configured in Music Assistant; its members cannot be released one by one.
      final fixed = leader.type == 'group';
      rows.add(
        _OutputTile(
          icon: leader.isGroup || members.isNotEmpty
              ? Icons.speaker_group
              : Icons.speaker,
          title: leader.name,
          subtitle: [
            if (members.isNotEmpty)
              'With ${members.map((m) => m.name).join(', ')}',
            switch (leader.state) {
              MaPlaybackState.playing => 'Playing',
              MaPlaybackState.paused => 'Paused',
              _ => null,
            },
          ].nonNulls.join(' · '),
          selected: output == leader.id,
          onTap: () => select(leader),
          trailing: output == leader.id
              ? null
              : groupControl(leader, following: false) ??
                    (members.isNotEmpty && !fixed
                        ? IconButton(
                            tooltip: 'Ungroup',
                            icon: const Icon(Icons.link_off),
                            onPressed: () =>
                                ungroup([for (final m in members) m.id]),
                          )
                        : null),
        ),
      );
      if (fixed) continue;
      for (final member in members) {
        rows.add(
          _OutputTile(
            icon: Icons.subdirectory_arrow_right,
            title: member.name,
            subtitle: 'In group with ${leader.name}',
            indent: true,
            selected: false,
            onTap: () => select(member),
            trailing: groupControl(member, following: true),
          ),
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
                  router?.push('/settings/music-assistant');
                },
              )
            else
              ...rows,
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
    this.trailing,
    this.indent = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;
  final Widget? trailing;

  /// Indents the row under its group leader.
  final bool indent;

  @override
  Widget build(BuildContext context) {
    final color = selected ? Theme.of(context).colorScheme.primary : null;
    return ListTile(
      contentPadding: EdgeInsets.only(left: indent ? 40 : 16, right: 16),
      leading: Icon(icon, color: color),
      title: Text(
        title,
        style: TextStyle(
          color: color,
          fontWeight: selected ? FontWeight.w700 : null,
        ),
      ),
      subtitle: subtitle == null || subtitle!.isEmpty ? null : Text(subtitle!),
      trailing: selected ? Icon(Icons.check, color: color) : trailing,
      onTap: onTap,
    );
  }
}
