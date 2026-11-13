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
import '../../playback/radio.dart';
import '../../ui/messages.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/artwork.dart';
import '../../ui/widgets/item_actions.dart';
import '../cast/output_sheet.dart';
import '../../ui/widgets/star_button.dart';
import '../collection/playlist_edit.dart';
import 'lyrics_view.dart';
import 'now_playing_below.dart';
import 'sleep_timer_sheet.dart';
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
    ref.watch(positionClockProvider);
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
                    child: NowPlayingArtwork(
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
                      // Loading, as when a Music Assistant player is starting.
                      // The spinner sits in a box the size of the icon, so the mini player keeps its height while loading.
                      icon: np.buffering && !np.playing
                          ? const SizedBox.square(
                              dimension: 32,
                              child: Padding(
                                padding: EdgeInsets.all(4),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                ),
                              ),
                            )
                          : Icon(
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
    final lyricsShown = ref.watch(lyricsShownProvider);
    final showRating =
        track != null && ref.watch(playerRatingProvider) && online;
    final format = ref.watch(playerFormatProvider)
        ? ref.watch(playingFormatProvider)
        : null;
    void open(String path) {
      Navigator.pop(context);
      GoRouter.of(context).push(path);
    }

    return _CloseWhenEmpty(
      child: Scaffold(
        backgroundColor: background,
        body: _NowPlayingBackground(
          np: np,
          top: top,
          child: SafeArea(
            child: np == null
                ? const SizedBox.shrink()
                : _PlayerScroll(
                    // One focal point, the artwork, as in Plexamp; what is rarely needed lives in the menu of the toolbar.
                    player: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: LayoutBuilder(
                        builder: (context, box) {
                          // The artwork sits near the top and takes what the rest leaves, up to the width of the page; the leftover height is shared between the rows below rather than gathered around the artwork, as in Plexamp.
                          final artSize = math.max(
                            0.0,
                            math.min(
                              box.maxWidth,
                              box.maxHeight - _belowArtwork(context),
                            ),
                          );
                          final artwork = _CoverGestures(
                            swipeToSkip: ref.watch(swipeToSkipProvider),
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
                            onTap: track == null
                                ? null
                                : () => ref
                                      .read(lyricsShownProvider.notifier)
                                      .set(!lyricsShown),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Hero(
                                  tag: _artworkHeroTag,
                                  child: AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 300),
                                    transitionBuilder: fadeWithoutKey,
                                    child: DecoratedBox(
                                      key: ValueKey(
                                        np.title + (np.album ?? ''),
                                      ),
                                      // The shadow follows the rounded corners of the artwork and sits slightly inside its edges, so no square shows behind it.
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(10),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(
                                              alpha:
                                                  Theme.of(context)
                                                          .brightness ==
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
                                      child: NowPlayingArtwork(
                                        np.coverArt,
                                        np.imageUrl,
                                        size: artSize,
                                        radius: 10,
                                      ),
                                    ),
                                  ),
                                ),
                                if (lyricsShown)
                                  Positioned.fill(child: LyricsPanel(np: np)),
                              ],
                            ),
                          );
                          return Column(
                            children: [
                              const _DragHandle(),
                              // Held to the size of the artwork: while it cross-fades to the next song, the outgoing artwork keeps the size it had, which no longer fits if the window shrank meanwhile.
                              SizedBox.square(
                                dimension: artSize,
                                child: artwork,
                              ),
                              const SizedBox(height: _minGap),
                              const Spacer(),
                              _SeekBar(np: np, color: highlight),
                              const SizedBox(height: _minGap),
                              const Spacer(),
                              _TrackText(
                                np: np,
                                onArtist: track?.artistId == null
                                    ? null
                                    : () => open('/artist/${track!.artistId}'),
                                onAlbum: track?.albumId == null
                                    ? null
                                    : () => open('/album/${track!.albumId}'),
                              ),
                              const SizedBox(height: 8),
                              // The codec, the rating and the quality on one line, which keeps its height while the format of a new song loads, so nothing below jumps.
                              SizedBox(
                                height: _FormatBadges.height,
                                // On a narrow screen the whole line scales down together rather than overflowing.
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      // A song from an external provider, whose ID starts with `ext-`, shows a globe: the server fetches it from the internet rather than from its own library.
                                      if (track != null &&
                                          isExternalId(track.id))
                                        Padding(
                                          padding: const EdgeInsets.all(4),
                                          child: Tooltip(
                                            message:
                                                'From an external provider',
                                            child: Icon(
                                              Icons.public,
                                              size: 16,
                                              color: highlight,
                                            ),
                                          ),
                                        ),
                                      if (format != null && track != null)
                                        _FormatBadges(
                                          format: format,
                                          track: track,
                                          color: highlight,
                                          part: _BadgePart.codec,
                                        ),
                                      if (showRating)
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                          ),
                                          child: RatingStars(
                                            key: ValueKey(track.id),
                                            rating: track.rating,
                                            color: highlight,
                                            dense: true,
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
                                      if (format != null && track != null)
                                        _FormatBadges(
                                          format: format,
                                          track: track,
                                          color: highlight,
                                          part: _BadgePart.quality,
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: _minGap),
                              const Spacer(),
                              _Transport(np: np, color: highlight),
                              // The room of the volume slider stays when this device plays, which has none.
                              SizedBox(
                                height: kMinInteractiveDimension,
                                child: np.volume == null
                                    ? null
                                    : _VolumeSlider(
                                        volume: np.volume!,
                                        color: highlight,
                                      ),
                              ),
                              _Toolbar(np: np, color: highlight),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// The smallest space between the rows of the player; the spacers share what is left beyond it.
const _minGap = 12.0;

/// The height the player needs below the top of the page besides the artwork: the handle, the waveform, the three lines of text at the person's text size, the badges, the controls, the volume slot, the toolbar and the gaps between them.
double _belowArtwork(BuildContext context) {
  final scale = MediaQuery.textScalerOf(context);
  // Line heights of the artist, the title and the album, with the spacing of the font.
  final text = (scale.scale(16) * 2 + scale.scale(20)) * 1.4 + 4;
  return 32 + // handle
      40 + // waveform
      text +
      8 +
      30 + // badges and stars
      72 + // transport
      kMinInteractiveDimension + // volume slot
      kMinInteractiveDimension + // toolbar
      4 * _minGap;
}

/// The handle at the top of the player, which closes it on a tap; a swipe down anywhere closes it too.
class _DragHandle extends StatelessWidget {
  const _DragHandle();

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Close the player',
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.pop(context),
      child: SizedBox(
        height: 32,
        child: Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: context.subtle,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    ),
  );
}

/// The artist, the title and the album with its year, on three centred lines. The artist and the album open their pages.
class _TrackText extends StatelessWidget {
  const _TrackText({required this.np, this.onArtist, this.onAlbum});

  final NowPlaying np;
  final VoidCallback? onArtist;
  final VoidCallback? onAlbum;

  @override
  Widget build(BuildContext context) {
    final year = np.track?.year;
    final album = [
      if (np.album case final album? when album.isNotEmpty) album,
      if (year != null) '($year)',
    ].join(' ');
    Widget line(String text, TextStyle style, VoidCallback? onTap) =>
        GestureDetector(
          onTap: onTap,
          child: Text(
            text,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        );
    return Column(
      children: [
        line(
          np.artist ?? '',
          TextStyle(color: context.colors.onSurface, fontSize: 16),
          onArtist,
        ),
        const SizedBox(height: 2),
        line(
          np.title,
          TextStyle(
            color: context.colors.onSurface,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
          null,
        ),
        const SizedBox(height: 2),
        line(album, TextStyle(color: context.muted, fontSize: 16), onAlbum),
      ],
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
  static const _waveformHeight = 40.0;

  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    ref.watch(positionClockProvider);
    final position = widget.np.positionNow();
    final duration = widget.np.duration;
    final buffered = widget.np.buffered;
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
    final showWaveform =
        trackId != null &&
        (ref.watch(waveformSupportedProvider).value ?? false);
    final peaks = showWaveform
        ? ref.watch(waveformProvider(trackId)).value
        : null;
    // The slider takes the gestures; the timeline below it draws the position, so the slider itself shows nothing.
    final slider = SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: TimelinePainter.lineWidth,
        thumbShape: SliderComponentShape.noThumb,
        overlayShape: SliderComponentShape.noOverlay,
        activeTrackColor: Colors.transparent,
        inactiveTrackColor: Colors.transparent,
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
    final remaining = ref.watch(remainingTimeProvider);
    // The times sit at either end of the waveform, in columns of a fixed width so the waveform does not shift as they change.
    return Row(
      children: [
        SizedBox(
          width: 44,
          child: Text(
            formatDuration(Duration(milliseconds: value.round())),
            style: style,
          ),
        ),
        // The seek bar always takes the height of the waveform, so the layout stays the same with a waveform, without one, and while one loads.
        Expanded(
          child: SizedBox(
            height: _waveformHeight,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Without a thumb the slider track spans the full width, as the timeline does.
                Positioned.fill(
                  child: CustomPaint(
                    painter: TimelinePainter(
                      peaks: peaks,
                      progress: max == 0 ? 0 : value / max,
                      // An output that reports no loading, such as Music Assistant, counts as having loaded the song.
                      loaded: max == 0 || buffered == null
                          ? 1
                          : buffered.inMilliseconds / max,
                      played: widget.color,
                      loadedColour: context.muted,
                      unplayed: context.subtle,
                      smooth:
                          ref.watch(waveformStyleProvider) ==
                          WaveformStyle.smooth,
                    ),
                  ),
                ),
                slider,
              ],
            ),
          ),
        ),
        // A tap switches between the time that remains and the length of the song.
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => ref
              .read(remainingTimeProvider.notifier)
              .set(!ref.read(remainingTimeProvider)),
          child: SizedBox(
            width: 48,
            height: _waveformHeight,
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                remaining
                    ? '-${formatDuration(duration - Duration(milliseconds: value.round()))}'
                    : formatDuration(duration),
                style: style,
              ),
            ),
          ),
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
    this.onTap,
  });

  final Widget child;
  final bool swipeToSkip;
  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final VoidCallback? onDoubleTap;

  /// A tap on the artwork, which shows or hides the lyrics.
  final VoidCallback? onTap;

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
    onTap: widget.onTap,
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

enum _BadgePart { codec, quality }

/// The codec or the quality badge of what plays, either side of the rating. A tap opens the song info, with the streaming quality on top.
class _FormatBadges extends StatelessWidget {
  /// The height of the badges with their touch padding, which the player keeps while they load.
  static const height = 30.0;

  const _FormatBadges({
    required this.format,
    required this.track,
    required this.color,
    required this.part,
  });

  final PlayingFormat format;
  final Track track;
  final Color color;
  final _BadgePart part;

  @override
  Widget build(BuildContext context) {
    final text = switch (part) {
      _BadgePart.codec => format.codec,
      _BadgePart.quality => format.quality,
    };
    if (text == null) return const SizedBox.shrink();
    return Semantics(
      button: true,
      label: 'Song info',
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: () => showSongInfo(context, track),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: _Badge(text, color: color),
        ),
      ),
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

/// Previous, play and next. Shuffle and repeat live in the toolbar below.
class _Transport extends ConsumerWidget {
  const _Transport({required this.np, required this.color});

  final NowPlaying np;

  /// The colour of the artwork, which tints the play button.
  final Color color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(playbackControllerProvider);
    final onSurface = context.colors.onSurface;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          tooltip: 'Previous',
          iconSize: 44,
          color: onSurface,
          icon: const Icon(Icons.skip_previous_rounded),
          onPressed: controller.previous,
        ),
        const SizedBox(width: 28),
        _StopOnLongPress(
          child: SizedBox.square(
            dimension: 72,
            // A soft circle tinted by the artwork rather than a stark one, so the artwork stays the focal point.
            child: IconButton.filled(
              iconSize: 44,
              style: IconButton.styleFrom(
                backgroundColor: Color.alphaBlend(
                  color.withValues(alpha: 0.35),
                  context.colors.surfaceContainerHighest.withValues(alpha: 0.6),
                ),
                foregroundColor: onSurface,
              ),
              icon: np.buffering && !np.playing
                  ? SizedBox.square(
                      dimension: 30,
                      child: CircularProgressIndicator(
                        color: onSurface,
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
        const SizedBox(width: 28),
        IconButton(
          tooltip: 'Next',
          iconSize: 44,
          color: onSurface,
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
      _VolumeEnd(Icons.volume_down),
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
      _VolumeEnd(Icons.volume_up),
    ],
  );
}

/// An icon at an end of the volume slider, in the box of an icon button so it stands above the first or last button of the toolbar at any density.
class _VolumeEnd extends StatelessWidget {
  const _VolumeEnd(this.icon);

  final IconData icon;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: IconButton(
      onPressed: null,
      iconSize: 20,
      disabledColor: context.muted,
      icon: Icon(icon),
    ),
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
              const SliverToBoxAdapter(child: BelowTabBar()),
              const BelowContent(),
              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ],
          ),
        ),
  );
}

/// The last row of the player, small icons on either side of the menu: the queue, endless radio and shuffle on the left; repeat, instant mix and the speaker on the right. Toggles stay faint unless on.
class _Toolbar extends ConsumerWidget {
  const _Toolbar({required this.np, required this.color});

  final NowPlaying np;

  /// The colour of the toggles that are on, and of the speaker button while a speaker plays.
  final Color color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(playbackControllerProvider);
    final track = np.track;
    final faint = context.muted;
    // On a Music Assistant player, its Autoplay.
    final radio = ref.watch(outputEndlessRadioProvider);
    // An instant mix asks the server for songs that sound alike, so it needs the connection and the `sonicSimilarity` extension.
    final mix =
        track != null &&
        ref.watch(canMixProvider) &&
        !ref.watch(isOfflineProvider);
    // The left group hugs the left edge and the right group the right edge, with the menu centred between them, as in Plexamp. On a phone narrower than 384 points, three buttons do not fit beside the menu, and the group shrinks.
    return Row(
      children: [
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Queue',
                  color: faint,
                  icon: const Icon(Icons.queue_music),
                  onPressed: () =>
                      showQueue(context, ProviderScope.containerOf(context)),
                ),
                // Greyed out while repeat is on: a queue that repeats never runs out, so there is nothing to extend.
                if (radio.available)
                  IconButton(
                    tooltip: radio.blocked
                        ? 'Endless radio is off while repeat is on'
                        : radio.on
                        ? 'Endless radio on'
                        : 'Endless radio off',
                    color: radio.on ? color : faint,
                    icon: const Icon(Icons.all_inclusive),
                    onPressed: radio.blocked
                        ? null
                        : () => runPlayback(
                            () => ref.read(setEndlessRadioProvider)(!radio.on),
                          ),
                  ),
                IconButton(
                  tooltip: 'Shuffle',
                  color: np.shuffle ? color : faint,
                  icon: const Icon(Icons.shuffle),
                  onPressed: () => controller.setShuffle(!np.shuffle),
                ),
              ],
            ),
          ),
        ),
        _PlayerMenuButton(np: np, track: track),
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Repeat',
                  color: np.repeat == Repeat.off ? faint : color,
                  icon: Icon(
                    np.repeat == Repeat.one ? Icons.repeat_one : Icons.repeat,
                  ),
                  onPressed: () => controller.setRepeat(switch (np.repeat) {
                    Repeat.off => Repeat.all,
                    Repeat.all => Repeat.one,
                    Repeat.one => Repeat.off,
                  }),
                ),
                if (mix)
                  IconButton(
                    tooltip: 'Instant mix',
                    color: faint,
                    icon: const Icon(Icons.radio),
                    // The song plays on, and the mix follows it.
                    onPressed: () => runPlayback(() async {
                      final songs = await ref
                          .read(repositoryProvider)!
                          .instantMix(track);
                      if (!await playRadio(controller, songs)) {
                        showMessage('The server found no similar songs');
                      }
                    }),
                  ),
                OutputButton(activeColor: color, idleColor: faint),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The menu of the player: the actions of the song, then the sleep timer and the queue. A running sleep timer marks the button.
class _PlayerMenuButton extends ConsumerWidget {
  const _PlayerMenuButton({required this.np, required this.track});

  final NowPlaying np;
  final Track? track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sleep = ref.watch(sleepTimerProvider);
    final track = this.track;
    final songIds = [for (final e in np.queue) ?e.trackId];
    final online = !ref.watch(isOfflineProvider);
    return IconButton(
      tooltip: sleep == null ? 'More' : 'More, sleep timer on',
      color: context.muted,
      icon: Badge(
        isLabelVisible: sleep != null,
        smallSize: 7,
        child: const Icon(Icons.more_horiz),
      ),
      onPressed: track == null
          ? null
          : () => showTrackActions(
              context,
              ref,
              track,
              extras: [
                (
                  icon: sleep == null ? Icons.bedtime_outlined : Icons.bedtime,
                  label: 'Sleep timer',
                  detail: sleep == null ? null : 'On',
                  onTap: () => showSleepTimerSheet(context),
                ),
                if (online && songIds.isNotEmpty)
                  (
                    icon: Icons.save_outlined,
                    label: 'Save queue as playlist',
                    detail: null,
                    onTap: () => createPlaylistFrom(context, ref, songIds),
                  ),
                (
                  icon: Icons.clear_all,
                  label: 'Clear queue',
                  detail: null,
                  onTap: () => ref.read(playbackControllerProvider).stop(),
                ),
              ],
            ),
    );
  }
}

/// The tabs below the player. Queue always shows; the others show when the server has something for them.
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
