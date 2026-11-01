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
import '../cast/output_sheet.dart';
import '../collection/collection_header.dart';
import '../collection/playlist_edit.dart';
import 'quality_sheet.dart';
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
    // The format badges, the stars and the heart share a row between the artwork and the title. Offline, only the badges show.
    final format = ref.watch(playerFormatProvider)
        ? ref.watch(playingFormatProvider)
        : null;
    final showFavourite = online && ref.watch(playerFavouriteProvider);
    // An instant mix asks the server for similar songs, so it needs the connection.
    final showMix = online;
    final showTrackRow =
        track != null &&
        (showRating || showFavourite || showMix || format != null);
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
                                    // Under the artwork, the row of badges, stars and heart takes 14 + 40 pixels; without it, the padding keeps the shadow of the artwork clear of the title.
                                    final below = showTrackRow ? 54.0 : 22.0;
                                    final artSize = math.max(
                                      0.0,
                                      math.min(
                                        box.maxWidth,
                                        box.maxHeight - below,
                                      ),
                                    );
                                    // The row spans the artwork, or 300 pixels when the artwork is narrower, so its badges still fit.
                                    final rowWidth = math.max(
                                      artSize,
                                      math.min(box.maxWidth, 300.0),
                                    );
                                    final artwork = GestureDetector(
                                      // Swiping the artwork skips to the next or previous track.
                                      onHorizontalDragEnd:
                                          ref.watch(swipeToSkipProvider)
                                          ? (d) {
                                              final v = d.primaryVelocity ?? 0;
                                              if (v < -300) {
                                                controller.next();
                                              }
                                              if (v > 300) {
                                                controller.previous();
                                              }
                                            }
                                          : null,
                                      child: Hero(
                                        tag: _artworkHeroTag,
                                        child: AnimatedSwitcher(
                                          duration: const Duration(
                                            milliseconds: 300,
                                          ),
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
                                        artwork,
                                        if (showTrackRow) ...[
                                          SizedBox(height: 14 + slack / 4),
                                          SizedBox(
                                            width: rowWidth,
                                            height: 40,
                                            child: _TrackRow(
                                              track: track,
                                              format: format,
                                              rating: showRating,
                                              favourite: showFavourite,
                                              mix: showMix,
                                              color: highlight,
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
            Text(
              ref.watch(remainingTimeProvider)
                  ? '-${formatDuration(duration - Duration(milliseconds: value.round()))}'
                  : formatDuration(duration),
              style: style,
            ),
          ],
        ),
      ],
    );
  }
}

/// The row under the artwork: the codec and quality badges at its left edge, the stars in the middle and the heart at its right edge. The sides have equal widths, so the stars stay centred, and a side shrinks its content rather than overflow.
class _TrackRow extends ConsumerWidget {
  const _TrackRow({
    required this.track,
    required this.format,
    required this.rating,
    required this.favourite,
    required this.mix,
    required this.color,
  });

  final Track track;
  final PlayingFormat? format;
  final bool rating;
  final bool favourite;

  /// The instant mix button, left of the heart.
  final bool mix;
  final Color color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final format = this.format;
    Widget side(Alignment alignment, List<Widget> children) => Expanded(
      child: Align(
        alignment: alignment,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(mainAxisSize: MainAxisSize.min, children: children),
        ),
      ),
    );
    return Row(
      children: [
        // A tap on the badges opens the streaming quality, to transcode or not.
        side(Alignment.centerLeft, [
          if (format != null)
            Semantics(
              button: true,
              label: 'Streaming quality',
              child: InkWell(
                borderRadius: BorderRadius.circular(4),
                onTap: () => showQualitySheet(context),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
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
            ),
          const SizedBox(width: 8),
        ]),
        if (rating)
          RatingStars(
            key: ValueKey(track.id),
            rating: track.rating,
            color: color,
            dense: true,
            onChanged: (value) async {
              if (await rate(ref, track.id, value)) {
                rememberRating(track.json, value);
              }
            },
          ),
        side(Alignment.centerRight, [
          const SizedBox(width: 8),
          if (mix)
            IconButton(
              tooltip: 'Instant mix',
              icon: Icon(Icons.radio, color: context.muted),
              iconSize: 22,
              style: IconButton.styleFrom(
                minimumSize: const Size(32, 40),
                fixedSize: const Size(32, 40),
                padding: EdgeInsets.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
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
          if (mix && favourite) const SizedBox(width: 4),
          if (favourite)
            StarButton(
              key: ValueKey('heart-${track.id}'),
              starred: track.starred,
              trackId: track.id,
              json: track.json,
              color: color,
              dense: true,
            ),
        ]),
      ],
    );
  }
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
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Text(
                    'Queue',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ),
              const _QueueSliver(),
              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ],
          ),
        ),
  );
}

/// The next track at the bottom of the player. A tap scrolls to the queue.
/// The last row of the player: the speaker button and the next song. Alone, the speaker button keeps to the left and the next song to the centre.
/// The last row of the player: "Add to playlist" on the far left, the next song in the middle and the speaker button on the far right. The sides have equal widths, so the next song stays centred; the speaker button shrinks to its icon when its name does not fit.
class _BottomRow extends ConsumerWidget {
  const _BottomRow({
    required this.np,
    required this.speaker,
    required this.upNext,
  });

  final NowPlaying np;
  final bool speaker;
  final bool upNext;

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
            child: speaker ? const OutputButton(showName: true) : null,
          ),
        ),
      ],
    );
  }
}

class _UpNext extends StatelessWidget {
  const _UpNext({required this.np});

  final NowPlaying np;

  @override
  Widget build(BuildContext context) {
    final index = np.index;
    final next = index != null && index + 1 < np.queue.length
        ? np.queue[index + 1]
        : null;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () {
        final position = Scrollable.of(context).position;
        position.animateTo(
          position.viewportDimension,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
        );
      },
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

/// The queue: played tracks dimmed, the current one marked, upcoming ones below. Pressing and dragging a track moves it; swiping it away removes it.
class _QueueSliver extends ConsumerStatefulWidget {
  const _QueueSliver();

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
    final current = np?.index;
    final controller = ref.read(playbackControllerProvider);
    final downloaded = ref.watch(downloadedTrackIdSetProvider);

    return SliverReorderableList(
      itemCount: queue.length,
      onReorderItem: (from, to) {
        final moved = [...queue];
        moved.insert(to, moved.removeAt(from));
        setState(() {
          _movedFrom = reported;
          _moved = moved;
        });
        controller.move(from, to);
      },
      itemBuilder: (context, i) {
        final item = queue[i];
        final playing = i == current;
        return ReorderableDelayedDragStartListener(
          key: ValueKey('${item.id}-$i'),
          index: i,
          child: Dismissible(
            key: ValueKey('dismiss-${item.id}-$i'),
            direction: DismissDirection.endToStart,
            onDismissed: (_) => controller.removeAt(i),
            background: Container(
              color: Colors.red.shade900,
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 16),
              child: const Icon(Icons.delete, color: Colors.white),
            ),
            child: Opacity(
              // Played tracks are dimmed.
              opacity: current != null && i < current ? 0.5 : 1,
              child: ListTile(
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
                      PlayingBars(
                        playing: np?.playing ?? false,
                        color: Colors.white,
                      ),
                    ],
                  ],
                ),
                selected: playing,
                title: Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
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
                onTap: () => controller.skipTo(i),
              ),
            ),
          ),
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
