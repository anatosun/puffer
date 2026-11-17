import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/playback_providers.dart';
import '../../playback/playback_controller.dart';
import '../../ui/theme.dart';
import '../cast/output_sheet.dart';
import 'now_playing.dart';
import 'now_playing_below.dart';

/// The player along the bottom of a wide window: the song, the seek bar and the controls, and the volume and the output. A click on the song opens the full player.
class PlayerBar extends ConsumerWidget {
  const PlayerBar({super.key});

  static const height = 80.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final np = ref.watch(nowPlayingProvider).value;
    if (np == null) return const SizedBox.shrink();
    final scheme = playerScheme(context, ref, np);
    final accent = scheme?.primary ?? context.colors.primary;
    return Material(
      color: Color.alphaBlend(
        (scheme?.primaryContainer ?? context.colors.surfaceContainerHighest)
            .withValues(alpha: 0.35),
        context.colors.surfaceContainer,
      ),
      child: SizedBox(
        height: height,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Expanded(flex: 3, child: _Song(np)),
              Expanded(
                flex: 6,
                child: _Controls(np: np, accent: accent),
              ),
              Expanded(
                flex: 3,
                child: _Extras(np: np, accent: accent),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Song extends StatelessWidget {
  const _Song(this.np);

  final NowPlaying np;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => openNowPlaying(context),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            NowPlayingArtwork(np.coverArt, np.imageUrl, size: 56, radius: 4),
            const SizedBox(width: 12),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    np.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    np.outputName == null
                        ? (np.artist ?? '')
                        : '${np.artist ?? ''} · ${np.outputName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: context.muted, fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Controls extends ConsumerWidget {
  const _Controls({required this.np, required this.accent});

  final NowPlaying np;
  final Color accent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(playbackControllerProvider);
    final onSurface = context.colors.onSurface;
    // The seek bar first, then the buttons, on one line. Compact buttons keep the line narrow on a touch screen too, whose buttons are larger.
    return Row(
      children: [
        Expanded(
          child: SeekBar(np: np, color: accent, height: 36),
        ),
        const SizedBox(width: 12),
        IconButtonTheme(
          data: IconButtonThemeData(
            style: IconButton.styleFrom(visualDensity: VisualDensity.compact),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Shuffle',
                iconSize: 20,
                color: np.shuffle ? accent : context.muted,
                icon: const Icon(Icons.shuffle_rounded),
                onPressed: () => controller.setShuffle(!np.shuffle),
              ),
              IconButton(
                tooltip: 'Previous',
                color: onSurface,
                icon: const Icon(Icons.skip_previous_rounded),
                onPressed: controller.previous,
              ),
              IconButton.filled(
                tooltip: np.playing ? 'Pause' : 'Play',
                style: IconButton.styleFrom(
                  backgroundColor: onSurface,
                  foregroundColor: context.colors.surface,
                ),
                icon: np.buffering && !np.playing
                    ? SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: context.colors.surface,
                        ),
                      )
                    : Icon(
                        np.playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                      ),
                onPressed: np.playing ? controller.pause : controller.play,
              ),
              IconButton(
                tooltip: 'Next',
                color: onSurface,
                icon: const Icon(Icons.skip_next_rounded),
                onPressed: controller.next,
              ),
              IconButton(
                tooltip: switch (np.repeat) {
                  Repeat.off => 'Repeat',
                  Repeat.all => 'Repeat one',
                  Repeat.one => 'Repeat off',
                },
                iconSize: 20,
                color: np.repeat == Repeat.off ? context.muted : accent,
                icon: Icon(
                  np.repeat == Repeat.one
                      ? Icons.repeat_one_rounded
                      : Icons.repeat_rounded,
                ),
                onPressed: () => controller.setRepeat(switch (np.repeat) {
                  Repeat.off => Repeat.all,
                  Repeat.all => Repeat.one,
                  Repeat.one => Repeat.off,
                }),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Extras extends ConsumerWidget {
  const _Extras({required this.np, required this.accent});

  final NowPlaying np;
  final Color accent;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Row(
    mainAxisAlignment: MainAxisAlignment.end,
    children: [
      IconButton(
        tooltip: 'Queue',
        isSelected: ref.watch(queuePanelProvider),
        color: context.muted,
        selectedIcon: Icon(Icons.queue_music_rounded, color: accent),
        icon: const Icon(Icons.queue_music_rounded),
        onPressed: () => ref
            .read(queuePanelProvider.notifier)
            .set(!ref.read(queuePanelProvider)),
      ),
      if (np.volume case final volume?)
        SizedBox(
          width: 140,
          child: _Volume(volume: volume, accent: accent),
        ),
      OutputButton(activeColor: accent),
    ],
  );
}

/// The volume of a Music Assistant player. This device follows the volume of the system, so it has none.
class _Volume extends ConsumerStatefulWidget {
  const _Volume({required this.volume, required this.accent});

  final int volume;
  final Color accent;

  @override
  ConsumerState<_Volume> createState() => _VolumeState();
}

class _VolumeState extends ConsumerState<_Volume> {
  double? _drag;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(Icons.volume_up_rounded, size: 18, color: context.muted),
      Expanded(
        child: SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
          ),
          child: Slider(
            value: _drag ?? widget.volume.toDouble(),
            max: 100,
            activeColor: widget.accent,
            inactiveColor: context.subtle,
            onChanged: (v) => setState(() => _drag = v),
            onChangeEnd: (v) async {
              await ref.read(playbackControllerProvider).setVolume(v.round());
              if (mounted) setState(() => _drag = null);
            },
          ),
        ),
      ),
    ],
  );
}
