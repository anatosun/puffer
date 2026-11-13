import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/playback_providers.dart';
import '../../app/providers.dart';
import '../../app/sendspin_providers.dart';
import '../../data/music_assistant/ma_client.dart';
import '../../data/music_assistant/ma_models.dart';
import '../../ui/messages.dart';
import '../../ui/player_icons.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/playing_bars.dart';

/// Opens the output picker. It shows once Music Assistant is set up, highlighted while a player is the output.
class OutputButton extends ConsumerWidget {
  const OutputButton({
    super.key,
    this.showName = false,
    this.activeColor,
    this.idleColor,
  });

  final bool showName;

  /// The colour while a speaker plays, the theme's primary colour when null; the player passes the colour of the artwork.
  final Color? activeColor;

  /// The colour while this device plays, the theme's icon colour when null.
  final Color? idleColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Offline, nothing can play on a speaker; an icon in the place of the button tells why.
    if (ref.watch(isOfflineProvider)) {
      return Tooltip(
        message: 'Offline',
        child: SizedBox.square(
          dimension: 48,
          child: Icon(Icons.cloud_off, color: idleColor),
        ),
      );
    }
    if (ref.watch(maCredentialsProvider) == null) {
      return const SizedBox.shrink();
    }
    // The phone as a speaker counts as this device.
    final output = ref.watch(outputProvider);
    final remote =
        output != null && !ref.watch(ownPlayerIdsProvider).contains(output);
    final color = remote
        ? activeColor ?? Theme.of(context).colorScheme.primary
        : idleColor;
    final icon = Icon(
      remote ? Icons.speaker_group : Icons.speaker_group_outlined,
      color: color,
    );
    final name = remote
        ? ref.watch(nowPlayingProvider).value?.outputName
        : null;
    if (showName && name != null) {
      // The icon comes after the name and sits 24 pixels from the end of the button, the centre of an icon button, so it lines up with icon buttons above and below it.
      return TextButton.icon(
        style: TextButton.styleFrom(
          padding: const EdgeInsets.only(left: 8, right: 12),
        ),
        iconAlignment: IconAlignment.end,
        onPressed: () => showOutputSheet(context),
        icon: icon,
        label: Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: color),
        ),
      );
    }
    return IconButton(
      tooltip: 'Play on',
      icon: icon,
      onPressed: () => showOutputSheet(context),
    );
  }
}

/// The state a player shows in the sheet. Many players report idle rather than paused, so a player with a current item in its queue counts as paused.
MaPlaybackState sheetState(MaPlayer player, MaQueue? queue) {
  if (player.state == MaPlaybackState.playing) return MaPlaybackState.playing;
  if (player.state == MaPlaybackState.paused || queue?.currentItem != null) {
    return MaPlaybackState.paused;
  }
  return player.state;
}

extension on String {
  String? get nullIfEmpty => isEmpty ? null : this;
}

String? _describe(MaQueueItem? item) =>
    item == null ? null : [item.title, item.artist].nonNulls.join(' · ');

Future<void> showOutputSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      builder: (_) => const _WaitForMusicAssistant(child: _OutputSheet()),
    );

/// Keeps Music Assistant retrying every few seconds while [child] shows, rather than backing off to half a minute, so an unreachable server is found as soon as it answers again. Opening it also retries at once.
class _WaitForMusicAssistant extends ConsumerStatefulWidget {
  const _WaitForMusicAssistant({required this.child});

  final Widget child;

  @override
  ConsumerState<_WaitForMusicAssistant> createState() =>
      _WaitForMusicAssistantState();
}

class _WaitForMusicAssistantState
    extends ConsumerState<_WaitForMusicAssistant> {
  MusicAssistantClient? _client;

  void _wait(MusicAssistantClient? client) {
    if (identical(client, _client)) return;
    _client?.stopWaiting();
    _client = client?..startWaiting();
  }

  @override
  void dispose() {
    _client?.stopWaiting();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // A new client, as after signing in again, is waited on in turn.
    _wait(ref.watch(maClientProvider));
    return widget.child;
  }
}

/// A tap on a player moves playback there. While a player is the output, the checkbox of another player adds it to the group or removes it.
/// Players are listed by group: each player that leads, or plays on its own, followed by the players that follow it. A tap on a player moves playback there, taking a following player out of its group first. While a player is the output, the checkbox of another player adds it to the group or removes it; the unlink button ungroups.
class _OutputSheet extends ConsumerWidget {
  const _OutputSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final output = ref.watch(outputProvider);
    final status = ref.watch(maStatusProvider).value;
    // This phone as a speaker is the "This device" row rather than a player of its own.
    final own = ref.watch(ownPlayerIdsProvider);
    final onThisDevice = output == null || own.contains(output);
    // What plays or is paused on this phone, itself or as a speaker.
    final here = onThisDevice ? ref.watch(nowPlayingProvider).value : null;
    final players = [
      for (final p in ref.watch(maPlayersProvider).value ?? const <MaPlayer>[])
        if (!own.contains(p.id)) p,
    ];
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

    // The Music Assistant player of this phone as a speaker: the one in use, or else a shown one before the hidden protocol player under it.
    final ownPlayers =
        [
          for (final p
              in ref.watch(maAllPlayersProvider).value ?? const <MaPlayer>[])
            if (own.contains(p.id)) p,
        ]..sort(
          (a, b) =>
              (a.id == output
                      ? 0
                      : a.usable
                      ? 1
                      : 2)
                  .compareTo(
                    b.id == output
                        ? 0
                        : b.usable
                        ? 1
                        : 2,
                  ),
        );
    final ownPlayer = ownPlayers.firstOrNull;
    // On this device, other speakers sync with the phone's own player, provided Music Assistant knows it.
    final current = onThisDevice ? ownPlayer : byId[output];
    bool inCurrentGroup(MaPlayer p) =>
        current != null && membersOf(current).any((m) => m.id == p.id);

    void select(MaPlayer? player) {
      // The sheet closes before the switch ends, so the switch runs on a provider rather than on the ref of this widget.
      final switcher = ref.read(outputSwitcherProvider);
      Navigator.pop(context);
      // Music Assistant already plays on this phone.
      if (player == null && own.contains(output)) return;
      runPlayback(() async {
        // A player that follows another plays the whole group; picking it alone takes it out first.
        if (player != null && player.syncedTo != null) {
          await client?.command('players/cmd/ungroup', {
            'player_id': player.id,
          });
        }
        await switcher.switchTo(player?.id);
      });
    }

    /// Syncs [p] with the current output, or stops syncing it. Music playing on the phone itself moves to the phone's Music Assistant player first, since only that player plays in sync with others.
    Future<void> toggleMember(MaPlayer p, bool add) => runPlayback(() async {
      final leader = current;
      if (leader == null || client == null) return;
      if (add && output == null) {
        await ref.read(outputSwitcherProvider).switchTo(leader.id);
      }
      await client.command('players/cmd/set_members', {
        'target_player': leader.id,
        if (add)
          'player_ids_to_add': [p.id]
        else
          'player_ids_to_remove': [p.id],
      });
    });

    Future<void> ungroup(List<String> ids) => runPlayback(() async {
      await client?.command('players/cmd/ungroup_many', {'player_ids': ids});
    });

    Widget? groupControl(MaPlayer player, {required bool following}) {
      if (current != null &&
          player.id != current.id &&
          (inCurrentGroup(player) ||
              current.canGroupWith.contains(player.id))) {
        final member = inCurrentGroup(player);
        final leaderName = onThisDevice ? 'this device' : current.name;
        return IconButton(
          tooltip: member
              ? 'Stop syncing ${player.name}'
              : 'Sync ${player.name} with $leaderName',
          icon: Icon(member ? Icons.link_off : Icons.link),
          onPressed: () => toggleMember(player, !member),
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

    // While another speaker is the output, the phone's own Music Assistant player (this device as a Sendspin speaker) can join it. The players above leave the phone out, so its membership is read from the output itself.
    final ownSynced =
        !onThisDevice &&
        ownPlayer != null &&
        current != null &&
        (ownPlayer.syncedTo == current.id ||
            current.groupMembers.contains(ownPlayer.id));
    final ownSyncable =
        !onThisDevice &&
        ownPlayer != null &&
        ownPlayer.available &&
        current != null &&
        (ownSynced || current.canGroupWith.contains(ownPlayer.id));

    final rows = <Widget>[];
    // Set when This device is listed under a group, which then is its only place in the sheet.
    var phoneListed = false;
    final followers = {
      for (final p in players)
        if (p.selectable && p.type != 'group') ...membersOf(p).map((m) => m.id),
      // The speakers synced with this phone show under This device.
      if (ownPlayer != null) ...membersOf(ownPlayer).map((m) => m.id),
    };
    for (final leader in players.where(
      (p) => p.selectable && !followers.contains(p.id),
    )) {
      final members = membersOf(leader);
      // A group player is a fixed group configured in Music Assistant; its members cannot be released one by one.
      final fixed = leader.type == 'group';
      final selected = output == leader.id;
      final queue = queues[leader.id];
      final state = sheetState(leader, queue);
      final active =
          state == MaPlaybackState.playing || state == MaPlaybackState.paused;
      // Volume sliders show for the output and for players that have something loaded, so idle speakers keep the list short.
      final showVolume = selected || active;
      // The phone, as a Sendspin speaker, can follow this group too; the players above leave it out, so it is added here as This device.
      final phoneInGroup =
          ownPlayer != null &&
          ownPlayer.id != leader.id &&
          (ownPlayer.syncedTo == leader.id ||
              leader.groupMembers.contains(ownPlayer.id));
      // A sync group is the speakers listed under it, so its row has no name of its own: the group icon, what it plays, the volume of the group. Idle, it names its speakers so the row is not empty. A fixed group keeps the name it was given in Music Assistant.
      final syncGroup = (members.isNotEmpty || phoneInGroup) && !fixed;
      final speakerNames = [
        leader.name,
        for (final m in members) m.name,
        if (phoneInGroup) 'This device',
      ].join(', ');
      rows.add(
        _OutputTile(
          icon: syncGroup ? 'speakers' : leader.icon,
          title: syncGroup ? null : leader.name,
          label: syncGroup ? speakerNames : null,
          detail: syncGroup && !active ? speakerNames : null,
          state: state,
          media: active ? _describe(queue?.currentItem) : null,
          selected: selected,
          onTap: () => select(leader),
          onPlayPause: active && client != null
              ? () => runPlayback(() => client.playPause(leader, queue))
              : null,
          volume: showVolume ? leader : null,
          trailing: selected
              ? null
              : groupControl(leader, following: false) ??
                    (syncGroup
                        ? IconButton(
                            tooltip: 'Ungroup',
                            icon: const Icon(Icons.link_off),
                            onPressed: () => ungroup([
                              for (final m in members) m.id,
                              if (phoneInGroup) ownPlayer.id,
                            ]),
                          )
                        : null),
        ),
      );
      if (members.isEmpty && !phoneInGroup) continue;
      // Every speaker of the group under it, the leading one first, each with a volume of its own, so the balance between them can be set. A fixed group's own player is virtual, so only its members are listed; they cannot be taken out one by one, so a tap plays on the group.
      for (final p in [if (!fixed) leader, ...members]) {
        final leads = p.id == leader.id;
        rows.add(
          _OutputTile(
            icon: p.icon,
            title: p.name,
            indent: true,
            selected: false,
            onTap: () => select(leads || fixed ? leader : p),
            volume: showVolume ? p : null,
            volumeAlone: true,
            trailing: leads || fixed ? null : groupControl(p, following: true),
          ),
        );
      }
      if (phoneInGroup) {
        phoneListed = true;
        rows.add(
          _OutputTile(
            icon: 'smartphone',
            title: 'This device',
            indent: true,
            selected: false,
            // Plays the group here: the phone follows it as the output.
            onTap: () => select(leader),
            volume: showVolume ? ownPlayer : null,
            volumeAlone: true,
            trailing: fixed
                ? null
                : IconButton(
                    tooltip: 'Stop syncing this device',
                    icon: const Icon(Icons.link_off),
                    onPressed: () => runPlayback(() async {
                      await client?.command('players/cmd/set_members', {
                        'target_player': leader.id,
                        'player_ids_to_remove': [ownPlayer.id],
                      });
                    }),
                  ),
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
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Play on',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  // Leaves the speaker playing and returns to this device without moving the music, unlike a tap on "This device".
                  if (output != null && !own.contains(output))
                    TextButton.icon(
                      icon: const Icon(Icons.link_off),
                      label: const Text('Disconnect'),
                      onPressed: () {
                        ref.read(outputSwitcherProvider).disconnect();
                        Navigator.pop(context);
                      },
                    ),
                ],
              ),
            ),
            // Under a group it follows, This device is listed there only; the group rows show only while Music Assistant is connected.
            if (!(phoneListed && status == MaConnectionStatus.connected))
              _OutputTile(
                icon: 'smartphone',
                title: 'This device',
                // While the phone is a speaker, the name Music Assistant shows for it.
                detail: [
                  if (ref.watch(sendspinEnabledProvider))
                    '"${ref.watch(sendspinNameProvider)}" in Music Assistant',
                  if (onThisDevice && ownPlayer != null)
                    if (membersOf(ownPlayer) case final members
                        when members.isNotEmpty)
                      'with ${members.map((m) => m.name).join(', ')}',
                ].join(' · ').nullIfEmpty,
                state: here == null
                    ? null
                    : here.playing
                    ? MaPlaybackState.playing
                    : MaPlaybackState.paused,
                media: here == null
                    ? null
                    : [here.title, here.artist].nonNulls.join(' · '),
                selected: onThisDevice,
                onTap: () => select(null),
                trailing: ownSyncable && !ownSynced
                    ? IconButton(
                        tooltip: ownSynced
                            ? 'Stop syncing this device'
                            : 'Sync this device with ${current.name}',
                        icon: Icon(ownSynced ? Icons.link_off : Icons.link),
                        onPressed: () => toggleMember(ownPlayer, !ownSynced),
                      )
                    : null,
                onPlayPause: here == null
                    ? null
                    : () => runPlayback(() {
                        final controller = ref.read(playbackControllerProvider);
                        return here.playing
                            ? controller.pause()
                            : controller.play();
                      }),
              ),
            // The speakers synced with this phone, under it as under any group leader, the phone first with a volume of its own.
            if (ownPlayer != null &&
                status == MaConnectionStatus.connected &&
                membersOf(ownPlayer).isNotEmpty)
              _OutputTile(
                icon: 'smartphone',
                title: 'This device',
                indent: true,
                selected: false,
                onTap: () => select(null),
                volume: onThisDevice ? ownPlayer : null,
                volumeAlone: true,
              ),
            if (ownPlayer != null && status == MaConnectionStatus.connected)
              for (final member in membersOf(ownPlayer))
                _OutputTile(
                  icon: member.icon,
                  title: member.name,
                  indent: true,
                  selected: false,
                  onTap: () => select(member),
                  volume: onThisDevice ? member : null,
                  volumeAlone: true,
                  trailing: groupControl(member, following: true),
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
    this.title,
    this.label,
    this.detail,
    this.state,
    this.media,
    required this.selected,
    required this.onTap,
    this.onPlayPause,
    this.volume,
    this.volumeAlone = false,
    this.trailing,
    this.indent = false,
  });

  /// The icon ID of the shared Music Assistant icon set.
  final String icon;

  /// The name of the player; null for a sync group, which shows no name.
  final String? title;

  /// What screen readers and tooltips call a row without [title].
  final String? label;

  /// The group the player leads or follows.
  final String? detail;
  final MaPlaybackState? state;

  /// What the player has loaded, playing or paused, as title and artist.
  final String? media;
  final bool selected;
  final VoidCallback onTap;

  /// Pauses or resumes the player, without making it the output.
  final VoidCallback? onPlayPause;

  /// The player whose volume the slider sets.
  final MaPlayer? volume;

  /// The slider sets the volume of [volume] itself, not that of the group it leads.
  final bool volumeAlone;
  final Widget? trailing;

  /// Indents the row under its group leader.
  final bool indent;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final accent = selected ? colors.primary : colors.onSurface;
    final playing = state == MaPlaybackState.playing;
    final name = title ?? label ?? 'group';
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
                      alignment: Alignment.center,
                      child: PlayerIcon(
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
                          if (title case final title?)
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
                          if (media case final media? when media.isNotEmpty)
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
                                    media,
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
                    // Two columns of the same width on every row, play/pause then the chain, so the buttons line up whether a row has them or not.
                    SizedBox(
                      width: kMinInteractiveDimension,
                      child: onPlayPause == null
                          ? null
                          : IconButton(
                              tooltip: playing ? 'Pause $name' : 'Play $name',
                              icon: Icon(
                                playing
                                    ? Icons.pause_circle_filled
                                    : Icons.play_circle_filled,
                                color: accent,
                              ),
                              onPressed: onPlayPause,
                            ),
                    ),
                    SizedBox(
                      width: kMinInteractiveDimension,
                      // The highlight marks the selected output.
                      child: selected ? null : trailing,
                    ),
                  ],
                ),
                if (volume case final player?
                    when (volumeAlone ? player.volume : player.sliderVolume) !=
                        null)
                  Padding(
                    padding: const EdgeInsets.only(left: 46),
                    child: _PlayerVolume(
                      player,
                      color: accent,
                      alone: volumeAlone,
                    ),
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
  const _PlayerVolume(this.player, {required this.color, this.alone = false});

  final MaPlayer player;
  final Color color;

  /// The volume of the player itself, even while it leads a group.
  final bool alone;

  @override
  ConsumerState<_PlayerVolume> createState() => _PlayerVolumeState();
}

class _PlayerVolumeState extends ConsumerState<_PlayerVolume> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final volume =
        (widget.alone ? widget.player.volume : widget.player.sliderVolume) ?? 0;
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
                    () => client.setVolume(
                      widget.player,
                      v.round(),
                      alone: widget.alone,
                    ),
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
