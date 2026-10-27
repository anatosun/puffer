import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/playback_providers.dart';
import '../../playback/playback_controller.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/artwork.dart';
import '../../ui/widgets/item_actions.dart';
import '../cast/output_sheet.dart';

/// The artwork image of what is playing: the Subsonic cover when the track is known, otherwise the Music Assistant image.
ImageProvider? _image(WidgetRef ref, NowPlaying np, {int size = 300}) {
  final subsonic = artworkImage(ref, np.coverArt, size: size);
  if (subsonic != null) return subsonic;
  return np.imageUrl == null
      ? null
      : CachedNetworkImageProvider(np.imageUrl.toString());
}

ColorScheme? _scheme(WidgetRef ref, NowPlaying? np) {
  if (np == null) return null;
  if (np.coverArt != null) return artworkScheme(ref, np.coverArt);
  final image = _image(ref, np);
  if (image == null || np.imageUrl == null) return null;
  return ref
      .watch(artworkSchemeProvider((np.imageUrl.toString(), image)))
      .value;
}

class _NowPlayingArtwork extends ConsumerWidget {
  const _NowPlayingArtwork(this.np, {required this.size, this.radius = 6});

  final NowPlaying np;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (np.coverArt != null || np.imageUrl == null) {
      return Artwork(np.coverArt, size: size, radius: radius);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image(
        image: _image(ref, np, size: 800)!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
      ),
    );
  }
}

/// The bar above the navigation bar. A tap opens the now-playing screen.
class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final np = ref.watch(nowPlayingProvider).value;
    if (np == null) return const SizedBox.shrink();
    ref.watch(clockProvider);
    final controller = ref.read(playbackControllerProvider);
    final scheme = _scheme(ref, np);
    final position = np.positionNow();

    return GestureDetector(
      onTap: () => openNowPlaying(context),
      onVerticalDragEnd: (d) {
        if ((d.primaryVelocity ?? 0) < -200) openNowPlaying(context);
      },
      child: Container(
        margin: const EdgeInsets.fromLTRB(8, 0, 8, 6),
        decoration: BoxDecoration(
          color: Color.alphaBlend(
            (scheme?.primaryContainer ?? const Color(0xFF2A2A2A)).withValues(
              alpha: 0.6,
            ),
            const Color(0xFF151515),
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  _NowPlayingArtwork(np, size: 44, radius: 4),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
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
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const OutputButton(),
                  IconButton(
                    icon: Icon(
                      np.playing
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      size: 32,
                    ),
                    onPressed: np.playing ? controller.pause : controller.play,
                  ),
                ],
              ),
            ),
            LinearProgressIndicator(
              value: np.duration.inMilliseconds == 0
                  ? 0
                  : (position.inMilliseconds / np.duration.inMilliseconds)
                        .clamp(0, 1),
              minHeight: 2,
              backgroundColor: Colors.white10,
              color: scheme?.primary ?? accent,
            ),
          ],
        ),
      ),
    );
  }
}

void openNowPlaying(BuildContext context) =>
    Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder<void>(
        opaque: false,
        pageBuilder: (_, _, _) => const NowPlayingPage(),
        transitionsBuilder: (_, animation, _, child) => SlideTransition(
          position: Tween(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).chain(CurveTween(curve: Curves.easeOutCubic)).animate(animation),
          child: child,
        ),
      ),
    );

class NowPlayingPage extends ConsumerWidget {
  const NowPlayingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final np = ref.watch(nowPlayingProvider).value;
    final controller = ref.read(playbackControllerProvider);
    final scheme = _scheme(ref, np);
    final top = scheme?.primaryContainer ?? const Color(0xFF333333);
    final highlight = scheme?.primary ?? accent;
    final track = np?.track;

    return GestureDetector(
      onVerticalDragEnd: (d) {
        if ((d.primaryVelocity ?? 0) > 300) Navigator.pop(context);
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: AnimatedContainer(
          duration: const Duration(milliseconds: 600),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [top, Color.lerp(top, Colors.black, 0.75)!, Colors.black],
            ),
          ),
          child: SafeArea(
            child: np == null
                ? const Center(child: Text('Nothing playing'))
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final artSize = (constraints.maxWidth - 48).clamp(
                        0.0,
                        constraints.maxHeight * 0.45,
                      );
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                IconButton(
                                  icon: const Icon(
                                    Icons.keyboard_arrow_down_rounded,
                                    size: 32,
                                  ),
                                  onPressed: () => Navigator.pop(context),
                                ),
                                Expanded(
                                  child: Text(
                                    np.album ?? '',
                                    textAlign: TextAlign.center,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.more_horiz),
                                  onPressed: track == null
                                      ? null
                                      : () => showTrackActions(
                                          context,
                                          ref,
                                          track,
                                        ),
                                ),
                              ],
                            ),
                            const Spacer(),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 300),
                              child: DecoratedBox(
                                key: ValueKey(np.title + (np.album ?? '')),
                                decoration: BoxDecoration(
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.5,
                                      ),
                                      blurRadius: 40,
                                      offset: const Offset(0, 20),
                                    ),
                                  ],
                                ),
                                child: _NowPlayingArtwork(
                                  np,
                                  size: artSize,
                                  radius: 10,
                                ),
                              ),
                            ),
                            const Spacer(),
                            GestureDetector(
                              onTap: track?.albumId == null
                                  ? null
                                  : () {
                                      Navigator.pop(context);
                                      GoRouter.of(context)
                                          .push('/album/${track!.albumId}');
                                    },
                              child: Text(
                                np.title,
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.headlineSmall
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                            ),
                            const SizedBox(height: 4),
                            GestureDetector(
                              onTap: track?.artistId == null
                                  ? null
                                  : () {
                                      Navigator.pop(context);
                                      GoRouter.of(context)
                                          .push('/artist/${track!.artistId}');
                                    },
                              child: Text(
                                np.artist ?? '',
                                style: TextStyle(
                                  color: highlight,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            _SeekBar(np: np, color: highlight),
                            _Controls(np: np),
                            if (np.volume != null)
                              _VolumeSlider(
                                volume: np.volume!,
                                color: highlight,
                              ),
                            const SizedBox(height: 4),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                IconButton(
                                  tooltip: 'Shuffle',
                                  color: np.shuffle
                                      ? highlight
                                      : Colors.white54,
                                  icon: const Icon(Icons.shuffle),
                                  onPressed: () =>
                                      controller.setShuffle(!np.shuffle),
                                ),
                                const OutputButton(showName: true),
                                IconButton(
                                  tooltip: 'Queue',
                                  icon: const Icon(Icons.queue_music),
                                  onPressed: () => _showQueue(context),
                                ),
                                IconButton(
                                  tooltip: 'Repeat',
                                  color: np.repeat == Repeat.off
                                      ? Colors.white54
                                      : highlight,
                                  icon: Icon(
                                    np.repeat == Repeat.one
                                        ? Icons.repeat_one
                                        : Icons.repeat,
                                  ),
                                  onPressed: () =>
                                      controller.setRepeat(switch (np.repeat) {
                                        Repeat.off => Repeat.all,
                                        Repeat.all => Repeat.one,
                                        Repeat.one => Repeat.off,
                                      }),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ),
      ),
    );
  }

  void _showQueue(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) =>
        const FractionallySizedBox(heightFactor: 0.75, child: _QueueSheet()),
  );
}

class _SeekBar extends ConsumerStatefulWidget {
  const _SeekBar({required this.np, required this.color});

  final NowPlaying np;
  final Color color;

  @override
  ConsumerState<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends ConsumerState<_SeekBar> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    ref.watch(clockProvider);
    final position = widget.np.positionNow();
    final duration = widget.np.duration;
    final max = duration.inMilliseconds.toDouble();
    final value = (_dragValue ?? position.inMilliseconds.toDouble()).clamp(
      0.0,
      max == 0 ? 1.0 : max,
    );
    const style = TextStyle(
      color: Colors.white54,
      fontSize: 12,
      fontFeatures: [FontFeature.tabularFigures()],
    );
    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: SliderComponentShape.noOverlay,
            activeTrackColor: widget.color,
            thumbColor: Colors.white,
            inactiveTrackColor: Colors.white24,
          ),
          child: Slider(
            value: value,
            max: max == 0 ? 1 : max,
            onChanged: (v) => setState(() => _dragValue = v),
            onChangeEnd: (v) {
              ref
                  .read(playbackControllerProvider)
                  .seek(Duration(milliseconds: v.round()));
              setState(() => _dragValue = null);
            },
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              formatDuration(Duration(milliseconds: value.round())),
              style: style,
            ),
            Text(
              '-${formatDuration(duration - Duration(milliseconds: value.round()))}',
              style: style,
            ),
          ],
        ),
      ],
    );
  }
}

class _Controls extends ConsumerWidget {
  const _Controls({required this.np});

  final NowPlaying np;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(playbackControllerProvider);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IconButton(
          iconSize: 44,
          icon: const Icon(Icons.skip_previous_rounded),
          onPressed: controller.previous,
        ),
        SizedBox.square(
          dimension: 80,
          child: IconButton.filled(
            iconSize: 48,
            style: IconButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
            ),
            icon: np.buffering && !np.playing
                ? const SizedBox.square(
                    dimension: 32,
                    child: CircularProgressIndicator(
                      color: Colors.black,
                      strokeWidth: 3,
                    ),
                  )
                : Icon(
                    np.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  ),
            onPressed: np.playing ? controller.pause : controller.play,
          ),
        ),
        IconButton(
          iconSize: 44,
          icon: const Icon(Icons.skip_next_rounded),
          onPressed: controller.next,
        ),
      ],
    );
  }
}

class _VolumeSlider extends ConsumerStatefulWidget {
  const _VolumeSlider({required this.volume, required this.color});

  final int volume;
  final Color color;

  @override
  ConsumerState<_VolumeSlider> createState() => _VolumeSliderState();
}

class _VolumeSliderState extends ConsumerState<_VolumeSlider> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Icon(Icons.volume_down, color: Colors.white54, size: 20),
      Expanded(
        child: Slider(
          value: _dragValue ?? widget.volume.toDouble(),
          max: 100,
          activeColor: widget.color,
          inactiveColor: Colors.white24,
          onChanged: (v) => setState(() => _dragValue = v),
          onChangeEnd: (v) async {
            await ref.read(playbackControllerProvider).setVolume(v.round());
            if (mounted) setState(() => _dragValue = null);
          },
        ),
      ),
      const Icon(Icons.volume_up, color: Colors.white54, size: 20),
    ],
  );
}

class _QueueSheet extends ConsumerWidget {
  const _QueueSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final np = ref.watch(nowPlayingProvider).value;
    final queue = np?.queue ?? const [];
    final controller = ref.read(playbackControllerProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text('Queue', style: Theme.of(context).textTheme.titleLarge),
        ),
        Expanded(
          child: ReorderableListView.builder(
            itemCount: queue.length,
            onReorderItem: controller.move,
            itemBuilder: (context, i) {
              final item = queue[i];
              return Dismissible(
                key: ValueKey('${item.id}-$i'),
                direction: DismissDirection.endToStart,
                onDismissed: (_) => controller.removeAt(i),
                background: Container(
                  color: Colors.red.shade900,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 16),
                  child: const Icon(Icons.delete),
                ),
                child: ListTile(
                  selected: i == np?.index,
                  title: Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    item.artist ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => controller.skipTo(i),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
