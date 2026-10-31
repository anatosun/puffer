import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/playback_providers.dart';
import '../../data/music_assistant/ma_client.dart';
import '../../data/music_assistant/ma_models.dart';
import '../../playback/ma_playback_controller.dart';
import '../../ui/messages.dart';
import '../../ui/player_icons.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/playing_bars.dart';

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
    final queues = ref.watch(maQueuesProvider).value ?? const {};
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
      // The sheet closes before the switch ends, so the switch runs on the notifier rather than on the ref of this widget.
      final output = ref.read(outputProvider.notifier);
      Navigator.pop(context);
      runPlayback(() async {
        // A player that follows another plays the whole group; picking it alone takes it out first.
        if (player != null && player.syncedTo != null) {
          await client?.command('players/cmd/ungroup', {
            'player_id': player.id,
          });
        }
        await output.switchTo(player?.id);
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
      final selected = output == leader.id;
      final active =
          leader.state == MaPlaybackState.playing ||
          leader.state == MaPlaybackState.paused;
      // Volume sliders show for the output and for players that have something loaded, so idle speakers keep the list short.
      final showVolume = selected || active;
      rows.add(
        _OutputTile(
          icon: playerIcon(leader.icon),
          title: leader.name,
          detail: members.isEmpty
              ? null
              : 'With ${members.map((m) => m.name).join(', ')}',
          state: leader.state,
          item: queues[leader.id]?.currentItem,
          selected: selected,
          onTap: () => select(leader),
          volume: showVolume ? leader : null,
          trailing: selected
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
            icon: playerIcon(member.icon),
            title: member.name,
            detail: 'In group with ${leader.name}',
            indent: true,
            selected: false,
            onTap: () => select(member),
            volume: showVolume ? member : null,
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
            const SizedBox(height: 4),
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

/// A player in the sheet: its icon, its name, what it plays and, with [volume], a volume slider.
class _OutputTile extends StatelessWidget {
  const _OutputTile({
    required this.icon,
    required this.title,
    this.detail,
    this.state,
    this.item,
    required this.selected,
    required this.onTap,
    this.volume,
    this.trailing,
    this.indent = false,
  });

  final IconData icon;
  final String title;

  /// The group the player leads or follows.
  final String? detail;
  final MaPlaybackState? state;

  /// What the queue of the player has loaded.
  final MaQueueItem? item;
  final bool selected;
  final VoidCallback onTap;

  /// The player whose volume the slider sets.
  final MaPlayer? volume;
  final Widget? trailing;

  /// Indents the row under its group leader.
  final bool indent;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final accent = selected ? colors.primary : colors.onSurface;
    final playing = state == MaPlaybackState.playing;
    final loaded = item != null && (playing || state == MaPlaybackState.paused);
    final media = loaded
        ? [item!.title, item!.artist].nonNulls.join(' · ')
        : null;
    final left = indent ? 40.0 : 12.0;
    return Padding(
      padding: EdgeInsets.fromLTRB(left, 2, 12, 2),
      child: Material(
        color: selected
            ? colors.primary.withValues(alpha: 0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: selected
                            ? colors.primary
                            : colors.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        icon,
                        size: 22,
                        color: selected ? colors.onPrimary : colors.onSurface,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: accent,
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                          if (media != null && media.isNotEmpty)
                            Row(
                              children: [
                                PlayingBars(
                                  playing: playing,
                                  color: accent,
                                  size: 11,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    playing ? media : 'Paused · $media',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: context.muted,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          if (detail != null)
                            Text(
                              detail!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: context.muted,
                                fontSize: 13,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (selected)
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Icon(Icons.check, color: accent),
                      )
                    else
                      ?trailing,
                  ],
                ),
                if (volume case final player? when player.sliderVolume != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 46),
                    child: _PlayerVolume(player, color: accent),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The volume of a Music Assistant player, or of every member while it leads a group. The value goes to Music Assistant when the drag ends.
class _PlayerVolume extends ConsumerStatefulWidget {
  const _PlayerVolume(this.player, {required this.color});

  final MaPlayer player;
  final Color color;

  @override
  ConsumerState<_PlayerVolume> createState() => _PlayerVolumeState();
}

class _PlayerVolumeState extends ConsumerState<_PlayerVolume> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final volume = widget.player.sliderVolume ?? 0;
    return Row(
      children: [
        Icon(
          widget.player.muted ? Icons.volume_off : Icons.volume_down,
          size: 18,
          color: context.muted,
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: SliderComponentShape.noOverlay,
            ),
            child: Slider(
              value: (_dragValue ?? volume.toDouble()).clamp(0, 100),
              max: 100,
              activeColor: widget.color,
              inactiveColor: context.subtle,
              semanticFormatterCallback: (v) =>
                  '${widget.player.name} volume ${v.round()}',
              onChanged: (v) => setState(() => _dragValue = v),
              onChangeEnd: (v) async {
                final client = ref.read(maClientProvider);
                if (client != null) {
                  await runPlayback(
                    () => client.setVolume(widget.player, v.round()),
                  );
                }
                if (mounted) setState(() => _dragValue = null);
              },
            ),
          ),
        ),
        SizedBox(
          width: 32,
          child: Text(
            '${(_dragValue ?? volume).round()}',
            textAlign: TextAlign.end,
            style: TextStyle(
              color: context.muted,
              fontSize: 12,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}
