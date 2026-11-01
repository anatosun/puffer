import 'dart:math' as math;

import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/experience.dart';
import '../../app/playback_providers.dart';
import '../../app/providers.dart';
import '../../data/subsonic/models.dart';
import '../../playback/audio_format.dart';
import '../../playback/playback_controller.dart';
import '../../ui/messages.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/artwork.dart';
import '../../ui/widgets/item_actions.dart';
import '../../ui/widgets/playing_bars.dart';
import '../../ui/widgets/tiles.dart';
import '../cast/output_sheet.dart';
import '../collection/album_page.dart';
import '../collection/artist_page.dart';
import '../collection/collection_header.dart';
import '../collection/playlist_edit.dart';
import 'song_info.dart';
import 'waveform.dart';

/// The artwork image of what is playing: the Subsonic cover when the track is known, otherwise the Music Assistant image.
ImageProvider? _image(WidgetRef ref, NowPlaying np, {int size = 300}) {
  final subsonic = artworkImage(ref, np.coverArt, size: size);
  if (subsonic != null) return subsonic;
  return np.imageUrl == null
      ? null
      : CachedNetworkImageProvider(np.imageUrl.toString());
}

ColorScheme? _scheme(BuildContext context, WidgetRef ref, NowPlaying? np) {
  if (np == null || !ref.watch(artworkColoursProvider)) return null;
  final brightness = Theme.of(context).brightness;
  if (np.coverArt != null) return artworkScheme(ref, np.coverArt, brightness);
  final image = _image(ref, np);
  if (image == null || np.imageUrl == null) return null;
  return ref
      .watch(artworkSchemeProvider((np.imageUrl.toString(), image, brightness)))
      .value;
}

/// The Subsonic cover when [coverArt] is known, otherwise the Music Assistant image at [imageUrl].
class _NowPlayingArtwork extends ConsumerWidget {
  const _NowPlayingArtwork(
    this.coverArt,
    this.imageUrl, {
    required this.size,
    this.radius = 6,
  });

  final String? coverArt;
  final Uri? imageUrl;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (coverArt != null || imageUrl == null) {
      return Artwork(coverArt, size: size, radius: radius);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image(
        image: CachedNetworkImageProvider(imageUrl.toString()),
        width: size,
        height: size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => Artwork(null, size: size, radius: 0),
      ),
    );
  }
}

const _artworkHeroTag = 'now-playing-artwork';

/// The gradient of the artwork colours, with the artwork blurred over it as in Plexamp.
class _NowPlayingBackground extends ConsumerWidget {
  const _NowPlayingBackground({
    required this.np,
    required this.top,
    required this.child,
  });

  final NowPlaying? np;
  final Color top;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final background = context.background;
    final np = this.np;
    final image = np == null || !ref.watch(artworkColoursProvider)
        ? null
        : _image(ref, np);
    return Stack(
      fit: StackFit.expand,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 600),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [top, Color.lerp(top, background, 0.75)!, background],
            ),
          ),
        ),
        if (image != null)
          BlurredArtwork(image: image, id: np!.coverArt ?? np.imageUrl!),
        child,
      ],
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
    final scheme = _scheme(context, ref, np);
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
            (scheme?.primaryContainer ?? context.colors.surfaceContainerHighest)
                .withValues(alpha: 0.6),
            context.colors.surfaceContainer,
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
                  Hero(
                    tag: _artworkHeroTag,
                    child: _NowPlayingArtwork(
                      np.coverArt,
                      np.imageUrl,
                      size: 44,
                      radius: 4,
                    ),
                  ),
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
                          style: TextStyle(color: context.muted, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  _StopOnLongPress(
                    child: IconButton(
                      icon: Icon(
                        np.playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        size: 32,
                      ),
                      onPressed: np.playing
                          ? controller.pause
                          : controller.play,
                    ),
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
              backgroundColor: context.colors.onSurface.withValues(alpha: 0.1),
              color: scheme?.primary ?? context.colors.primary,
            ),
          ],
        ),
      ),
    );
  }
}

/// The name of the route of the now-playing screen, so keyboard shortcuts can tell whether it is open.
const nowPlayingRouteName = 'now-playing';

void openNowPlaying(BuildContext context) =>
    Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder<void>(
        settings: const RouteSettings(name: nowPlayingRouteName),
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
    final scheme = _scheme(context, ref, np);
    final top =
        scheme?.primaryContainer ?? context.colors.surfaceContainerHighest;
    final background = context.background;
    final highlight = scheme?.primary ?? context.colors.primary;
    final track = np?.track;
    final online = !ref.watch(isOfflineProvider);
    final showRating =
        track != null && ref.watch(playerRatingProvider) && online;
    // The format badges sit centred above the title.
    final format = ref.watch(playerFormatProvider)
        ? ref.watch(playingFormatProvider)
        : null;
    // Under the artwork, only the stars.
    final showTrackRow = showRating;
    return _CloseWhenEmpty(
      child: Scaffold(
        backgroundColor: background,
        body: _NowPlayingBackground(
          np: np,
          top: top,
          child: SafeArea(
            child: np == null
                ? const SizedBox.shrink()
                : LayoutBuilder(
                    builder: (context, constraints) {
                      return _PlayerScroll(
                        player: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  IconButton(
                                    color: context.muted,
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
                                      style: TextStyle(
                                        color: context.colors.onSurface
                                            .withValues(alpha: 0.7),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    color: context.muted,
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
                              const SizedBox(height: 8),
                              // The artwork takes the height the rest leaves, up to the width of the page. The bottom padding keeps its shadow clear of what follows.
                              Expanded(
                                child: LayoutBuilder(
                                  builder: (context, box) {
                                    // Under the artwork, the stars take 14 pixels and the 48 of their row; without them, the padding keeps the shadow of the artwork clear of the title.
                                    const rowsHeight = 48.0;
                                    final below = showTrackRow
                                        ? 14 + rowsHeight
                                        : 22.0;
                                    final artSize = math.max(
                                      0.0,
                                      math.min(
                                        box.maxWidth,
                                        box.maxHeight - below,
                                      ),
                                    );
                                    // The stars span the artwork, or 300 pixels when the artwork is narrower, so they keep full-size touch targets.
                                    final rowWidth = math.max(
                                      artSize,
                                      math.min(box.maxWidth, 300.0),
                                    );
                                    final artwork = _CoverGestures(
                                      swipeToSkip: ref.watch(
                                        swipeToSkipProvider,
                                      ),
                                      onNext: controller.next,
                                      onPrevious: controller.previous,
                                      // A double tap adds the song to the library; it needs the connection.
                                      onDoubleTap: track != null && online
                                          ? () => saveStar(
                                              ref,
                                              (
                                                trackId: track.id,
                                                albumId: null,
                                                artistId: null,
                                              ),
                                              true,
                                              json: track.json,
                                            )
                                          : null,
                                      child: Hero(
                                        tag: _artworkHeroTag,
                                        child: AnimatedSwitcher(
                                          duration: const Duration(
                                            milliseconds: 300,
                                          ),
                                          transitionBuilder: fadeWithoutKey,
                                          child: DecoratedBox(
                                            key: ValueKey(
                                              np.title + (np.album ?? ''),
                                            ),
                                            // The shadow follows the rounded corners of the artwork and sits slightly inside its edges, so no square shows behind it.
                                            decoration: BoxDecoration(
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.black
                                                      .withValues(
                                                        alpha:
                                                            Theme.of(
                                                                  context,
                                                                ).brightness ==
                                                                Brightness.dark
                                                            ? 0.35
                                                            : 0.15,
                                                      ),
                                                  blurRadius: 20,
                                                  spreadRadius: -4,
                                                  offset: const Offset(0, 8),
                                                ),
                                              ],
                                            ),
                                            child: _NowPlayingArtwork(
                                              np.coverArt,
                                              np.imageUrl,
                                              size: artSize,
                                              radius: 10,
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                    // Half the free height goes above the artwork; the rest is shared around the row, so it sits halfway between the artwork and the title.
                                    final slack = math.max(
                                      0.0,
                                      box.maxHeight - artSize - below,
                                    );
                                    return Column(
                                      children: [
                                        SizedBox(height: slack / 2),
                                        // Held to the size of the artwork: while it cross-fades to the next song, the outgoing artwork keeps the size it had, which no longer fits if the window shrank meanwhile.
                                        SizedBox.square(
                                          dimension: artSize,
                                          child: artwork,
                                        ),
                                        if (showTrackRow) ...[
                                          SizedBox(height: 14 + slack / 4),
                                          SizedBox(
                                            width: rowWidth,
                                            height: rowsHeight,
                                            child: Center(
                                              child: RatingStars(
                                                key: ValueKey(track.id),
                                                rating: track.rating,
                                                color: highlight,
                                                large: true,
                                                onChanged: (value) async {
                                                  if (await rate(
                                                    ref,
                                                    track.id,
                                                    value,
                                                  )) {
                                                    rememberRating(
                                                      track.json,
                                                      value,
                                                    );
                                                  }
                                                },
                                              ),
                                            ),
                                          ),
                                        ] else
                                          const SizedBox(height: 22),
                                      ],
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(height: 18),
                              // The codec and quality, centred above the title; a tap opens the song info.
                              if (format != null && track != null) ...[
                                _FormatBadges(
                                  format: format,
                                  track: track,
                                  color: highlight,
                                ),
                                const SizedBox(height: 6),
                              ],
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
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
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
                              _Controls(np: np, color: highlight),
                              if (np.volume != null)
                                _VolumeSlider(
                                  volume: np.volume!,
                                  color: highlight,
                                ),
                              const SizedBox(height: 8),
                              // "Add to playlist", the next song and the speaker button. The speaker button shows once Music Assistant is set up.
                              _BottomRow(
                                np: np,
                                color: highlight,
                                speaker:
                                    ref.watch(maCredentialsProvider) != null,
                                upNext: ref.watch(upNextProvider),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ),
    );
  }
}

/// Closes the player as soon as nothing plays, but not while the output is switching, when the new output can report nothing for a moment.
class _CloseWhenEmpty extends ConsumerStatefulWidget {
  const _CloseWhenEmpty({required this.child});

  final Widget child;

  @override
  ConsumerState<_CloseWhenEmpty> createState() => _CloseWhenEmptyState();
}

class _CloseWhenEmptyState extends ConsumerState<_CloseWhenEmpty> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _update();
  }

  void _update() {
    final empty =
        ref.read(nowPlayingProvider).value == null &&
        !ref.read(outputSwitchingProvider);
    if (!empty) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    // The next turn of the event loop, since this can run while widgets build.
    _timer ??= Timer(Duration.zero, () {
      _timer = null;
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route == null || !route.isActive) return;
      // A sheet or dialog may lie over the player, so the player route itself goes.
      route.isCurrent
          ? Navigator.of(context).pop()
          : Navigator.of(context).removeRoute(route);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(nowPlayingProvider, (_, _) => _update());
    ref.listen(outputSwitchingProvider, (_, _) => _update());
    return widget.child;
  }
}

class _SeekBar extends ConsumerStatefulWidget {
  const _SeekBar({required this.np, required this.color});

  final NowPlaying np;
  final Color color;

  @override
  ConsumerState<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends ConsumerState<_SeekBar> {
  static const _thumbRadius = 6.0;
  static const _waveformHeight = 40.0;

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
    final style = TextStyle(
      color: context.muted,
      fontSize: 12,
      fontFeatures: [FontFeature.tabularFigures()],
    );
    final trackId = widget.np.track?.id;
    // The seek bar keeps the height of the waveform while it loads, so the layout does not move.
    final showWaveform =
        trackId != null &&
        (ref.watch(waveformSupportedProvider).value ?? false);
    final peaks = showWaveform
        ? ref.watch(waveformProvider(trackId)).value
        : null;
    final slider = SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 3,
        // With a waveform, the colour of the bars marks the position, so there is no thumb.
        thumbShape: peaks == null
            ? const RoundSliderThumbShape(enabledThumbRadius: _thumbRadius)
            : SliderComponentShape.noThumb,
        overlayShape: SliderComponentShape.noOverlay,
        // With a waveform, the waveform shows the progress and the track is hidden behind it.
        activeTrackColor: peaks == null ? widget.color : Colors.transparent,
        thumbColor: context.colors.onSurface,
        inactiveTrackColor: peaks == null ? context.subtle : Colors.transparent,
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
    );
    return Column(
      children: [
        if (!showWaveform)
          slider
        else
          SizedBox(
            height: _waveformHeight,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Without a thumb the slider track spans the full width, as the bars do.
                if (peaks != null)
                  Positioned.fill(
                    child: CustomPaint(
                      painter: WaveformPainter(
                        peaks: peaks,
                        progress: max == 0 ? 0 : value / max,
                        played: widget.color,
                        smooth:
                            ref.watch(waveformStyleProvider) ==
                            WaveformStyle.smooth,
                        unplayed: context.subtle,
                      ),
                    ),
                  ),
                slider,
              ],
            ),
          ),
        const SizedBox(height: 6),
        Row(
          children: [
            Text(
              formatDuration(Duration(milliseconds: value.round())),
              style: style,
            ),
            const Spacer(),
            // A tap switches between the time that remains and the length of the song.
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => ref
                  .read(remainingTimeProvider.notifier)
                  .set(!ref.read(remainingTimeProvider)),
              child: Padding(
                padding: const EdgeInsets.only(left: 16, top: 4, bottom: 4),
                child: Text(
                  ref.watch(remainingTimeProvider)
                      ? '-${formatDuration(duration - Duration(milliseconds: value.round()))}'
                      : formatDuration(duration),
                  style: style,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The gestures of the artwork. Sideways swipes skip, with [swipeToSkip]. A swipe up scrolls to the queue and a swipe down closes the player. A double tap calls [onDoubleTap] and shows a heart over the artwork.
class _CoverGestures extends StatefulWidget {
  const _CoverGestures({
    required this.child,
    required this.swipeToSkip,
    required this.onNext,
    required this.onPrevious,
    this.onDoubleTap,
  });

  final Widget child;
  final bool swipeToSkip;
  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final VoidCallback? onDoubleTap;

  @override
  State<_CoverGestures> createState() => _CoverGesturesState();
}

class _CoverGesturesState extends State<_CoverGestures>
    with SingleTickerProviderStateMixin {
  late final _heart = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  @override
  void dispose() {
    _heart.dispose();
    super.dispose();
  }

  void _toQueue() => showQueue(context, ProviderScope.containerOf(context));

  @override
  Widget build(BuildContext context) => GestureDetector(
    onHorizontalDragEnd: widget.swipeToSkip
        ? (d) {
            final v = d.primaryVelocity ?? 0;
            if (v < -300) widget.onNext();
            if (v > 300) widget.onPrevious();
          }
        : null,
    onVerticalDragEnd: (d) {
      final v = d.primaryVelocity ?? 0;
      if (v < -300) _toQueue();
      if (v > 300) Navigator.maybePop(context);
    },
    onDoubleTap: widget.onDoubleTap == null
        ? null
        : () {
            HapticFeedback.lightImpact();
            widget.onDoubleTap!();
            _heart.forward(from: 0);
          },
    child: Stack(
      alignment: Alignment.center,
      children: [
        widget.child,
        // The heart grows in, holds, then fades out.
        IgnorePointer(
          child: AnimatedBuilder(
            animation: _heart,
            builder: (context, _) {
              final t = _heart.value;
              if (t == 0 || t == 1) return const SizedBox.shrink();
              final scale = Curves.elasticOut.transform(
                (t / 0.4).clamp(0.0, 1.0),
              );
              final opacity = t < 0.6 ? 1.0 : (1 - (t - 0.6) / 0.4);
              return Opacity(
                opacity: opacity.clamp(0.0, 1.0),
                child: Transform.scale(
                  scale: 0.5 + scale * 0.5,
                  child: const Icon(
                    Icons.favorite,
                    size: 96,
                    color: Colors.white,
                    shadows: [Shadow(blurRadius: 24, color: Colors.black54)],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    ),
  );
}

/// The codec and quality badges of what plays. A tap opens the song info, with the streaming quality on top.
class _FormatBadges extends StatelessWidget {
  const _FormatBadges({
    required this.format,
    required this.track,
    required this.color,
  });

  final PlayingFormat format;
  final Track track;
  final Color color;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Song info',
    child: InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: () => showSongInfo(context, track),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Badge(format.codec, color: color),
            if (format.quality case final quality?) ...[
              const SizedBox(width: 6),
              _Badge(quality, color: color),
            ],
          ],
        ),
      ),
    ),
  );
}

/// A small outlined label for the format of what plays.
class _Badge extends StatelessWidget {
  const _Badge(this.text, {required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      border: Border.all(color: color.withValues(alpha: 0.6)),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      text,
      style: TextStyle(
        color: color,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    ),
  );
}

/// Shuffle, previous, play, next and repeat.
class _Controls extends ConsumerWidget {
  const _Controls({required this.np, required this.color});

  final NowPlaying np;

  /// The colour of shuffle and repeat while they are on.
  final Color color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(playbackControllerProvider);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          tooltip: 'Shuffle',
          color: np.shuffle ? color : context.muted,
          icon: const Icon(Icons.shuffle),
          onPressed: () => controller.setShuffle(!np.shuffle),
        ),
        IconButton(
          iconSize: 44,
          color: context.colors.onSurface,
          icon: const Icon(Icons.skip_previous_rounded),
          onPressed: controller.previous,
        ),
        _StopOnLongPress(
          child: SizedBox.square(
            dimension: 80,
            child: IconButton.filled(
              iconSize: 48,
              style: IconButton.styleFrom(
                backgroundColor: context.colors.onSurface,
                foregroundColor: context.colors.surface,
              ),
              icon: np.buffering && !np.playing
                  ? SizedBox.square(
                      dimension: 32,
                      child: CircularProgressIndicator(
                        color: context.colors.surface,
                        strokeWidth: 3,
                      ),
                    )
                  : Icon(
                      np.playing
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                    ),
              onPressed: np.playing ? controller.pause : controller.play,
            ),
          ),
        ),
        IconButton(
          iconSize: 44,
          color: context.colors.onSurface,
          icon: const Icon(Icons.skip_next_rounded),
          onPressed: controller.next,
        ),
        IconButton(
          tooltip: 'Repeat',
          color: np.repeat == Repeat.off ? context.muted : color,
          icon: Icon(np.repeat == Repeat.one ? Icons.repeat_one : Icons.repeat),
          onPressed: () => controller.setRepeat(switch (np.repeat) {
            Repeat.off => Repeat.all,
            Repeat.all => Repeat.one,
            Repeat.one => Repeat.off,
          }),
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
      Icon(Icons.volume_down, color: context.muted, size: 20),
      Expanded(
        child: Slider(
          value: _dragValue ?? widget.volume.toDouble(),
          max: 100,
          activeColor: widget.color,
          inactiveColor: context.subtle,
          onChanged: (v) => setState(() => _dragValue = v),
          onChangeEnd: (v) async {
            await ref.read(playbackControllerProvider).setVolume(v.round());
            if (mounted) setState(() => _dragValue = null);
          },
        ),
      ),
      Icon(Icons.volume_up, color: context.muted, size: 20),
    ],
  );
}

/// The player on the first screen, then the queue below it. Pulling down from the top closes the player.
class _PlayerScroll extends StatefulWidget {
  const _PlayerScroll({required this.player});

  final Widget player;

  @override
  State<_PlayerScroll> createState() => _PlayerScrollState();
}

class _PlayerScrollState extends State<_PlayerScroll> {
  bool _closing = false;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) =>
        NotificationListener<ScrollUpdateNotification>(
          onNotification: (n) {
            if (!_closing && n.dragDetails != null && n.metrics.pixels < -90) {
              _closing = true;
              Navigator.pop(context);
            }
            return false;
          },
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            slivers: [
              SliverToBoxAdapter(
                child: SizedBox(
                  height: constraints.maxHeight,
                  child: widget.player,
                ),
              ),
              const SliverToBoxAdapter(child: _BelowTabBar()),
              const _BelowContent(),
              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ],
          ),
        ),
  );
}

/// The last row of the player: "Add to playlist" on the far left, the next song in the middle and the speaker button on the far right. The sides have equal widths, so the next song stays centred; the speaker button shrinks to its icon when its name does not fit.
class _BottomRow extends ConsumerWidget {
  const _BottomRow({
    required this.np,
    required this.speaker,
    required this.upNext,
    required this.color,
  });

  final NowPlaying np;
  final bool speaker;
  final bool upNext;

  /// The colour of the speaker button while a speaker plays.
  final Color color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = np.track;
    // Playlists live on the server, so adding to one needs the connection.
    final addToPlaylist = track != null && !ref.watch(isOfflineProvider);
    if (!speaker && !upNext && !addToPlaylist) {
      return const SizedBox(height: 8);
    }
    return Row(
      children: [
        Expanded(
          flex: 5,
          child: Align(
            alignment: Alignment.centerLeft,
            child: addToPlaylist
                ? IconButton(
                    tooltip: 'Add to playlist',
                    color: context.muted,
                    icon: const Icon(Icons.playlist_add),
                    onPressed: () =>
                        showAddToPlaylist(context, ref, () async => [track]),
                  )
                : null,
          ),
        ),
        Expanded(flex: 6, child: upNext ? _UpNext(np: np) : const SizedBox()),
        Expanded(
          flex: 5,
          child: Align(
            alignment: Alignment.centerRight,
            child: speaker
                ? OutputButton(
                    showName: true,
                    activeColor: color,
                    idleColor: context.muted,
                  )
                : null,
          ),
        ),
      ],
    );
  }
}

class _UpNext extends ConsumerWidget {
  const _UpNext({required this.np});

  final NowPlaying np;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = np.index;
    final next = index != null && index + 1 < np.queue.length
        ? np.queue[index + 1]
        : null;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => showQueue(context, ProviderScope.containerOf(context)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.keyboard_arrow_up,
              size: 22,
              color: context.muted,
              semanticLabel: next == null ? 'Queue' : 'Up next',
            ),
            if (next != null) ...[
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  next.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.muted,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The tabs below the player. Queue always shows; the others show when the server has something for them.
enum BelowTab {
  played('Played'),
  queue('Queue'),
  album('Album'),
  artist('Artist'),
  about('About'),
  similar('Similar');

  const BelowTab(this.label);

  final String label;
}

class BelowTabNotifier extends Notifier<BelowTab> {
  @override
  BelowTab build() => BelowTab.queue;

  void set(BelowTab tab) => state = tab;
}

/// The tab below the player that shows. It goes back to the queue whenever the player opens, since it lives only while the player shows.
final belowTabProvider =
    NotifierProvider.autoDispose<BelowTabNotifier, BelowTab>(
      BelowTabNotifier.new,
    );

/// Switches to the queue tab and scrolls down to it, from the "Up next" row or a swipe up on the artwork.
void showQueue(BuildContext context, ProviderContainer container) {
  container.read(belowTabProvider.notifier).set(BelowTab.queue);
  final position = Scrollable.maybeOf(context)?.position;
  position?.animateTo(
    position.viewportDimension,
    duration: const Duration(milliseconds: 400),
    curve: Curves.easeOutCubic,
  );
}

/// What the tabs other than the queue show for the current song, from the server. Offline, or before the server answers, they are empty and their tabs hide.
typedef _Below = ({
  Track? track,
  Album? album,
  List<Album> artistAlbums,
  ArtistInfo? info,
});

_Below _below(WidgetRef ref) {
  final track = ref.watch(nowPlayingProvider.select((s) => s.value?.track));
  if (track == null || ref.watch(isOfflineProvider)) {
    return (track: track, album: null, artistAlbums: const [], info: null);
  }
  final album = track.albumId == null
      ? null
      : ref.watch(albumProvider(track.albumId!)).value;
  final artist = track.artistId == null
      ? null
      : ref.watch(artistProvider(track.artistId!)).value;
  final info = track.artistId == null
      ? null
      : ref.watch(artistInfoProvider(track.artistId!)).value;
  return (
    track: track,
    album: album,
    // The album that plays has its own tab.
    artistAlbums: [
      for (final a in artist?.albums ?? const <Album>[])
        if (a.id != track.albumId) a,
    ],
    info: info,
  );
}

List<BelowTab> _available(_Below below, {required bool played}) => [
  if (played) BelowTab.played,
  BelowTab.queue,
  if ((below.album?.songs.length ?? 0) > 1) BelowTab.album,
  if (below.artistAlbums.isNotEmpty) BelowTab.artist,
  if (below.info?.biography != null || below.info?.imageUrl != null)
    BelowTab.about,
  if (below.info?.similarArtists.isNotEmpty ?? false) BelowTab.similar,
];

/// Whether songs before the current one are in the queue, for the "Played" tab.
bool _hasPlayed(WidgetRef ref) =>
    (ref.watch(nowPlayingProvider.select((s) => s.value?.index)) ?? 0) > 0;

/// The tab bar below the player, with instant mix at its end.
class _BelowTabBar extends ConsumerWidget {
  const _BelowTabBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final below = _below(ref);
    final tabs = _available(below, played: _hasPlayed(ref));
    final selected = ref.watch(belowTabProvider);
    final index = math.max(0, tabs.indexOf(selected));
    final track = below.track;
    // An instant mix asks the server for similar songs, so it needs the connection.
    final mix = track != null && !ref.watch(isOfflineProvider);
    return Padding(
      // The right padding matches the player's, so instant mix sits under the speaker button.
      padding: const EdgeInsets.only(top: 8, left: 12, right: 24),
      child: Row(
        children: [
          Expanded(
            child: DefaultTabController(
              // A new controller when the tabs change with the song, or when another control picks a tab, such as "Up next" picking the queue.
              key: ValueKey('${tabs.join()}$index'),
              length: tabs.length,
              initialIndex: index,
              // Six tabs do not fit a narrow phone at a readable size, so the bar scrolls sideways; the queue, second, shows from the start.
              child: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelPadding: const EdgeInsets.symmetric(horizontal: 12),
                dividerColor: Colors.transparent,
                tabs: [for (final t in tabs) Tab(text: t.label)],
                onTap: (i) => ref.read(belowTabProvider.notifier).set(tabs[i]),
              ),
            ),
          ),
          if (mix)
            IconButton(
              tooltip: 'Instant mix',
              color: context.muted,
              icon: const Icon(Icons.radio),
              onPressed: () => runPlayback(() async {
                final tracks = await ref
                    .read(repositoryProvider)!
                    .instantMix(track);
                if (tracks.length < 2) {
                  showMessage('The server found no similar songs');
                  return;
                }
                await ref.read(playbackControllerProvider).playTracks(tracks);
              }),
            ),
        ],
      ),
    );
  }
}

/// The content of the selected tab below the player.
class _BelowContent extends ConsumerWidget {
  const _BelowContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final below = _below(ref);
    final tabs = _available(below, played: _hasPlayed(ref));
    final selected = ref.watch(belowTabProvider);
    final tab = tabs.contains(selected) ? selected : BelowTab.queue;

    // Links leave the player for the page they open.
    void open(String path) {
      final router = GoRouter.of(context);
      Navigator.pop(context);
      router.push(path);
    }

    switch (tab) {
      case BelowTab.played:
        return const _QueueSliver(played: true);
      case BelowTab.queue:
        return const _QueueSliver();
      case BelowTab.album:
        final album = below.album!;
        final songs = album.songs;
        return SliverList.list(
          children: [
            ListTile(
              title: Text(
                album.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              onTap: () => open('/album/${album.id}'),
              // The queue becomes the album, carrying on from the song and position that play.
              trailing: FilledButton.tonalIcon(
                icon: const Icon(Icons.queue_music),
                label: const Text('Play album'),
                onPressed: () => runPlayback(() async {
                  final np = ref.read(nowPlayingProvider).value;
                  final at = songs.indexWhere((t) => t.id == np?.track?.id);
                  final controller = ref.read(playbackControllerProvider);
                  await controller.playTracks(songs, index: math.max(0, at));
                  final position = np?.positionNow() ?? Duration.zero;
                  if (at >= 0 && position > const Duration(seconds: 1)) {
                    await controller.seek(position);
                  }
                }),
              ),
            ),
            for (var i = 0; i < songs.length; i++)
              TrackTile(
                tracks: songs,
                index: i,
                showArtwork: false,
                showNumber: true,
              ),
          ],
        );
      case BelowTab.artist:
        final albums = below.artistAlbums;
        return SliverList.builder(
          itemCount: albums.length,
          itemBuilder: (context, i) {
            final album = albums[i];
            return ListTile(
              leading: Artwork(album.coverArt, size: 52, radius: 4),
              title: Text(
                album.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: album.year == null
                  ? null
                  : Text(
                      '${album.year}',
                      style: TextStyle(color: context.muted),
                    ),
              onTap: () => open('/album/${album.id}'),
            );
          },
        );
      case BelowTab.about:
        final info = below.info!;
        final track = below.track!;
        return SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // A small photo of the artist with the name, which opens the artist page.
              ListTile(
                leading: ClipOval(
                  child: SizedBox.square(
                    dimension: 56,
                    child: info.imageUrl == null
                        ? const Artwork(null, size: 56, icon: Icons.person)
                        : CachedNetworkImage(
                            imageUrl: info.imageUrl!,
                            fit: BoxFit.cover,
                            errorWidget: (_, _, _) => const Artwork(
                              null,
                              size: 56,
                              icon: Icons.person,
                            ),
                          ),
                  ),
                ),
                title: Text(
                  track.artist ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                trailing: Icon(Icons.chevron_right, color: context.faint),
                onTap: () => open('/artist/${track.artistId}'),
              ),
              if (info.biography case final biography?) Biography(biography),
            ],
          ),
        );
      case BelowTab.similar:
        final similar = below.info!.similarArtists;
        return SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          sliver: SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 96,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.78,
            ),
            itemCount: similar.length,
            itemBuilder: (context, i) {
              final artist = similar[i];
              return InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => open('/artist/${artist.id}'),
                child: LayoutBuilder(
                  builder: (context, box) => Column(
                    children: [
                      ClipOval(
                        // The portrait leaves room for one line of name under it.
                        child: Artwork(
                          artist.coverArt,
                          size: math.max(
                            0.0,
                            math.min(box.maxWidth, box.maxHeight - 28),
                          ),
                          radius: 0,
                          icon: Icons.person,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        artist.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
    }
  }
}

/// The queue: played tracks dimmed, the current one marked, upcoming ones below. Pressing and dragging a track moves it; swiping it away removes it.
class _QueueSliver extends ConsumerStatefulWidget {
  const _QueueSliver({this.played = false});

  /// The songs played before the current one, most recent first; otherwise the current song and those after it.
  final bool played;

  @override
  ConsumerState<_QueueSliver> createState() => _QueueSliverState();
}

bool _sameOrder(List<QueueEntry> a, List<QueueEntry> b) =>
    a.length == b.length &&
    Iterable.generate(a.length).every((i) => a[i].id == b[i].id);

class _QueueSliverState extends ConsumerState<_QueueSliver> {
  /// The order after a move, shown until the output reports the new queue.
  List<QueueEntry>? _moved;
  List<QueueEntry>? _movedFrom;

  @override
  Widget build(BuildContext context) {
    final np = ref.watch(nowPlayingProvider).value;
    final reported = np?.queue ?? const <QueueEntry>[];
    if (_movedFrom != null && !_sameOrder(reported, _movedFrom!)) {
      _moved = null;
      _movedFrom = null;
    }
    final queue = _moved ?? reported;
    final current = np?.index ?? 0;
    final controller = ref.read(playbackControllerProvider);
    final downloaded = ref.watch(downloadedTrackIdSetProvider);

    Widget tile(int i, {required bool removable}) {
      final item = queue[i];
      final playing = i == np?.index;
      final row = ListTile(
        leading: Stack(
          alignment: Alignment.center,
          children: [
            _NowPlayingArtwork(
              item.coverArt,
              item.imageUrl,
              size: 44,
              radius: 4,
            ),
            if (playing) ...[
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              PlayingBars(playing: np?.playing ?? false, color: Colors.white),
            ],
          ],
        ),
        selected: playing,
        title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Row(
          children: [
            if (downloaded.contains(item.id))
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(
                  Icons.arrow_circle_down,
                  size: 14,
                  color: context.colors.primary,
                ),
              ),
            Expanded(
              child: Text(
                item.artist ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        onTap: playing ? null : () => controller.skipTo(i),
      );
      if (!removable) return row;
      return Dismissible(
        key: ValueKey('dismiss-${item.id}-$i'),
        direction: DismissDirection.endToStart,
        onDismissed: (_) => controller.removeAt(i),
        background: Container(
          color: Colors.red.shade900,
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 16),
          child: const Icon(Icons.delete, color: Colors.white),
        ),
        child: row,
      );
    }

    if (widget.played) {
      // Most recent first; a tap plays the song again from the queue.
      return SliverList.builder(
        itemCount: math.min(current, queue.length),
        itemBuilder: (context, j) => tile(current - 1 - j, removable: true),
      );
    }

    // The current song comes first and stays there; the songs after it can be moved and removed.
    final start = math.min(current, queue.length);
    final count = queue.length - start;
    return SliverReorderableList(
      itemCount: count,
      onReorderItem: (from, to) {
        if (from == 0) return;
        final target = math.max(1, to);
        final moved = [...queue];
        moved.insert(start + target, moved.removeAt(start + from));
        setState(() {
          _movedFrom = reported;
          _moved = moved;
        });
        controller.move(start + from, start + target);
      },
      itemBuilder: (context, j) {
        final i = start + j;
        final item = queue[i];
        if (j == 0) {
          return KeyedSubtree(
            key: ValueKey('${item.id}-$i'),
            child: tile(i, removable: false),
          );
        }
        return ReorderableDelayedDragStartListener(
          key: ValueKey('${item.id}-$i'),
          index: j,
          child: tile(i, removable: true),
        );
      },
    );
  }
}

/// Stops playback on a long press of the play button.
class _StopOnLongPress extends ConsumerWidget {
  const _StopOnLongPress({required this.child});

  final Widget child;

  @override
  // The tooltip also opens on a long press, so it wraps the detector: the inner recognizer wins the gesture.
  Widget build(BuildContext context, WidgetRef ref) => Tooltip(
    message: 'Long press to stop',
    child: GestureDetector(
      onLongPress: () {
        HapticFeedback.mediumImpact();
        ref.read(playbackControllerProvider).stop();
      },
      child: child,
    ),
  );
}
