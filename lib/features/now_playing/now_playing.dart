import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/artwork.dart';
import '../../ui/widgets/item_actions.dart';

final mediaItemProvider = StreamProvider<MediaItem?>(
  (ref) => ref.watch(playbackProvider).mediaItem,
);
final playbackStateProvider = StreamProvider<PlaybackState>(
  (ref) => ref.watch(playbackProvider).playbackState,
);
final positionProvider = StreamProvider<Duration>(
  (ref) => ref.watch(playbackProvider).player.positionStream,
);
final queueProvider = StreamProvider<List<MediaItem>>(
  (ref) => ref.watch(playbackProvider).queue,
);

String? _coverArtOf(WidgetRef ref) =>
    ref.read(playbackProvider).currentTrack?.coverArt;

/// The bar above the navigation bar. A tap opens the now-playing screen.
class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = ref.watch(mediaItemProvider).value;
    if (item == null) return const SizedBox.shrink();
    final playing = ref.watch(playbackStateProvider).value?.playing ?? false;
    final position = ref.watch(positionProvider).value ?? Duration.zero;
    final duration = item.duration ?? Duration.zero;
    final coverArt = _coverArtOf(ref);
    final scheme = artworkScheme(ref, coverArt);
    final handler = ref.read(playbackProvider);

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
                  Artwork(coverArt, size: 44, radius: 4),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          item.artist ?? '',
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
                  IconButton(
                    icon: Icon(
                      playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      size: 32,
                    ),
                    onPressed: playing ? handler.pause : handler.play,
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_next_rounded, size: 28),
                    onPressed: handler.skipToNext,
                  ),
                ],
              ),
            ),
            LinearProgressIndicator(
              value: duration.inMilliseconds == 0
                  ? 0
                  : (position.inMilliseconds / duration.inMilliseconds).clamp(
                      0,
                      1,
                    ),
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
    final item = ref.watch(mediaItemProvider).value;
    final state = ref.watch(playbackStateProvider).value;
    final handler = ref.read(playbackProvider);
    final track = handler.currentTrack;
    final scheme = artworkScheme(ref, track?.coverArt);
    final top = scheme?.primaryContainer ?? const Color(0xFF333333);
    final highlight = scheme?.primary ?? accent;

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
            child: item == null
                ? const Center(child: Text('Nothing playing'))
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final artSize = (constraints.maxWidth - 48).clamp(
                        0.0,
                        constraints.maxHeight * 0.48,
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
                                    item.album ?? '',
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
                                key: ValueKey(item.id),
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
                                child: Artwork(
                                  track?.coverArt,
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
                                item.title,
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
                                item.artist ?? '',
                                style: TextStyle(
                                  color: highlight,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            _SeekBar(
                              duration: item.duration ?? Duration.zero,
                              color: highlight,
                            ),
                            _Controls(state: state, color: highlight),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                IconButton(
                                  tooltip: 'Shuffle',
                                  color:
                                      state?.shuffleMode ==
                                          AudioServiceShuffleMode.all
                                      ? highlight
                                      : Colors.white54,
                                  icon: const Icon(Icons.shuffle),
                                  onPressed: () => handler.setShuffleMode(
                                    state?.shuffleMode ==
                                            AudioServiceShuffleMode.all
                                        ? AudioServiceShuffleMode.none
                                        : AudioServiceShuffleMode.all,
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Queue',
                                  icon: const Icon(Icons.queue_music),
                                  onPressed: () => _showQueue(context),
                                ),
                                IconButton(
                                  tooltip: 'Repeat',
                                  color:
                                      state?.repeatMode ==
                                          AudioServiceRepeatMode.none
                                      ? Colors.white54
                                      : highlight,
                                  icon: Icon(
                                    state?.repeatMode ==
                                            AudioServiceRepeatMode.one
                                        ? Icons.repeat_one
                                        : Icons.repeat,
                                  ),
                                  onPressed: () => handler.setRepeatMode(
                                    switch (state?.repeatMode) {
                                      AudioServiceRepeatMode.all =>
                                        AudioServiceRepeatMode.one,
                                      AudioServiceRepeatMode.one =>
                                        AudioServiceRepeatMode.none,
                                      _ => AudioServiceRepeatMode.all,
                                    },
                                  ),
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
  const _SeekBar({required this.duration, required this.color});

  final Duration duration;
  final Color color;

  @override
  ConsumerState<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends ConsumerState<_SeekBar> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final position = ref.watch(positionProvider).value ?? Duration.zero;
    final max = widget.duration.inMilliseconds.toDouble();
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
                  .read(playbackProvider)
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
              '-${formatDuration(widget.duration - Duration(milliseconds: value.round()))}',
              style: style,
            ),
          ],
        ),
      ],
    );
  }
}

class _Controls extends ConsumerWidget {
  const _Controls({required this.state, required this.color});

  final PlaybackState? state;
  final Color color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final handler = ref.read(playbackProvider);
    final playing = state?.playing ?? false;
    final buffering =
        state?.processingState == AudioProcessingState.loading ||
        state?.processingState == AudioProcessingState.buffering;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IconButton(
          iconSize: 44,
          icon: const Icon(Icons.skip_previous_rounded),
          onPressed: handler.skipToPrevious,
        ),
        SizedBox.square(
          dimension: 80,
          child: IconButton.filled(
            iconSize: 48,
            style: IconButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
            ),
            icon: buffering && !playing
                ? const SizedBox.square(
                    dimension: 32,
                    child: CircularProgressIndicator(
                      color: Colors.black,
                      strokeWidth: 3,
                    ),
                  )
                : Icon(
                    playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  ),
            onPressed: playing ? handler.pause : handler.play,
          ),
        ),
        IconButton(
          iconSize: 44,
          icon: const Icon(Icons.skip_next_rounded),
          onPressed: handler.skipToNext,
        ),
      ],
    );
  }
}

class _QueueSheet extends ConsumerWidget {
  const _QueueSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(queueProvider).value ?? const [];
    final current = ref.watch(playbackStateProvider).value?.queueIndex;
    final handler = ref.read(playbackProvider);
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
            onReorderItem: handler.moveQueueItem,
            itemBuilder: (context, i) {
              final item = queue[i];
              return Dismissible(
                key: ValueKey('${item.id}-$i'),
                direction: DismissDirection.endToStart,
                onDismissed: (_) => handler.removeQueueItemAt(i),
                background: Container(
                  color: Colors.red.shade900,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 16),
                  child: const Icon(Icons.delete),
                ),
                child: ListTile(
                  selected: i == current,
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
                  onTap: () => handler.skipToQueueItem(i),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
