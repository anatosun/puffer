import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../theme.dart';

/// The image for [coverArt]: the downloaded file when there is one, otherwise the server image unless offline.
ImageProvider? artworkImage(WidgetRef ref, String? coverArt, {int size = 600}) {
  if (coverArt == null) return null;
  final local = ref.watch(artworkStoreProvider)?.existing(coverArt);
  if (local != null) return FileImage(local);
  if (ref.watch(isOfflineProvider)) return null;
  final client = ref.watch(clientProvider);
  if (client == null) return null;
  return CachedNetworkImageProvider(
    client.unsignedCoverArtUri(coverArt, size: size).toString(),
    cacheKey: 'art:$coverArt:$size',
    cacheManager: ref.watch(artworkCacheProvider),
  );
}

/// Colours extracted from the artwork, for the album and now-playing backgrounds.
final artworkSchemeProvider =
    FutureProvider.family<ColorScheme?, (String, ImageProvider, Brightness)>((
      ref,
      key,
    ) async {
      try {
        return await ColorScheme.fromImageProvider(
          provider: key.$2,
          brightness: key.$3,
        );
      } on Exception {
        return null;
      }
    });

ColorScheme? artworkScheme(
  WidgetRef ref,
  String? coverArt,
  Brightness brightness,
) {
  if (!ref.watch(artworkColoursProvider)) return null;
  final image = artworkImage(ref, coverArt, size: 300);
  if (coverArt == null || image == null) return null;
  return ref.watch(artworkSchemeProvider((coverArt, image, brightness))).value;
}

/// A cross-fade for [AnimatedSwitcher] that leaves the key of the child out of the transition. The default transition takes the child's key, so switching back and forth faster than the fade leaves two fading copies with one key; without it, the switcher numbers each copy.
Widget fadeWithoutKey(Widget child, Animation<double> animation) =>
    FadeTransition(opacity: animation, child: child);

/// [image] blurred to fill its parent, fading to the background towards the bottom, as in Plexamp. A change of [id] cross-fades to the new image.
class BlurredArtwork extends StatelessWidget {
  const BlurredArtwork({
    super.key,
    required ImageProvider this.image,
    required this.id,
    this.top = 0.25,
  }) : colours = const [];

  /// Patches of [colours] blurred in place of an image, for when there is no artwork to show.
  BlurredArtwork.colours(this.colours, {super.key, this.top = 0.25})
    : image = null,
      id = Object.hashAll(colours);

  final ImageProvider? image;
  final List<Color> colours;
  final Object id;

  /// The opacity of the background over the top of the image.
  final double top;

  @override
  Widget build(BuildContext context) {
    final background = context.background;
    // The page above repaints often, with the clock of the seek bar or a scroll; the backdrop keeps its own layer.
    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 600),
            transitionBuilder: fadeWithoutKey,
            // The default layout gives the child loose constraints, which leaves the image at its own size; the backdrop fills its parent.
            layoutBuilder: (current, previous) =>
                Stack(fit: StackFit.expand, children: [...previous, ?current]),
            child: _Blurred(key: ValueKey(id), image: image, colours: colours),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  background.withValues(alpha: top),
                  background.withValues(alpha: 0.6),
                  background,
                ],
                stops: const [0, 0.55, 1],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The blur of the backdrop, in logical pixels.
const _blurSigma = 60.0;

/// The longer side of the blurred picture, in pixels. The blur leaves nothing finer than this, so the picture stretched to the screen looks as a blur of the full screen would.
const _blurSide = 128.0;

/// Blurred pictures by source and size, shared by the pages that show the same backdrop.
final _blurCache = <(Object, int, int), ui.Image>{};
const _blurCacheSize = 6;

/// [image], or [colours] as round patches, covering its parent and blurred. The blur runs once, into a small picture that is then stretched, since a blur filter on the widget would run again on every frame the screen redraws.
class _Blurred extends StatefulWidget {
  const _Blurred({super.key, this.image, this.colours = const []});

  final ImageProvider? image;
  final List<Color> colours;

  @override
  State<_Blurred> createState() => _BlurredState();
}

class _BlurredState extends State<_Blurred> {
  ui.Image? _picture;
  (Object, int, int)? _key;

  @override
  void dispose() {
    _picture?.dispose();
    super.dispose();
  }

  void _show(ui.Image picture) {
    if (!mounted) {
      picture.dispose();
      return;
    }
    setState(() {
      _picture?.dispose();
      _picture = picture;
    });
  }

  Future<void> _render((Object, int, int) key, Size size) async {
    final source = widget.image;
    final ui.Image? art;
    try {
      art = source == null ? null : await _resolve(source);
    } on Object {
      return;
    }
    if (source != null && art == null) return;
    final width = key.$2.toDouble(), height = key.$3.toDouble();
    final scale = width / size.width;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final bounds = Rect.fromLTWH(0, 0, width, height);
    canvas.saveLayer(
      bounds,
      Paint()
        ..imageFilter = ui.ImageFilter.blur(
          sigmaX: _blurSigma * scale,
          sigmaY: _blurSigma * scale,
          tileMode: TileMode.clamp,
        ),
    );
    if (art != null) {
      paintImage(
        canvas: canvas,
        rect: bounds,
        image: art,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
      );
      art.dispose();
    } else {
      _ColourPatches.paint(canvas, bounds.size, widget.colours);
    }
    canvas.restore();
    final picture = recorder.endRecording();
    final blurred = await picture.toImage(key.$2, key.$3);
    picture.dispose();
    _blurCache[key] = blurred.clone();
    while (_blurCache.length > _blurCacheSize) {
      _blurCache.remove(_blurCache.keys.first)?.dispose();
    }
    // The size may have changed while the picture rendered.
    if (key != _key) return blurred.dispose();
    _show(blurred);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final size = constraints.biggest;
      if (size.isEmpty || !size.isFinite) return const SizedBox.expand();
      final scale = _blurSide / math.max(size.width, size.height);
      final key = (
        widget.image ?? Object.hashAll(widget.colours),
        math.max(1, (size.width * scale).round()),
        math.max(1, (size.height * scale).round()),
      );
      if (key != _key) {
        _key = key;
        final cached = _blurCache.remove(key);
        if (cached != null) {
          // Most recently used last.
          _blurCache[key] = cached;
          _picture?.dispose();
          _picture = cached.clone();
        } else {
          unawaited(_render(key, size));
        }
      }
      final picture = _picture;
      if (picture == null) return const SizedBox.expand();
      return RawImage(
        image: picture,
        width: size.width,
        height: size.height,
        fit: BoxFit.fill,
        filterQuality: FilterQuality.medium,
      );
    },
  );
}

/// The image of [provider], decoded.
Future<ui.Image?> _resolve(ImageProvider provider) {
  final done = Completer<ui.Image?>();
  final stream = provider.resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      stream.removeListener(listener);
      if (done.isCompleted) {
        info.dispose();
        return;
      }
      done.complete(info.image.clone());
      info.dispose();
    },
    onError: (_, _) {
      stream.removeListener(listener);
      if (!done.isCompleted) done.complete(null);
    },
  );
  stream.addListener(listener);
  return done.future;
}

/// Round patches of colour spread over the top of the screen, which the blur turns into soft light.
abstract final class _ColourPatches {
  static const _spots = [
    (Alignment(-1, -1), 0.9),
    (Alignment(1, -0.7), 0.75),
    (Alignment(-0.2, -0.1), 0.6),
  ];

  /// Each patch is a circle as wide as its share of [size], placed at its alignment.
  static void paint(Canvas canvas, Size size, List<Color> colours) {
    for (final (i, colour) in colours.indexed) {
      final (alignment, widthFactor) = _spots[i % _spots.length];
      final diameter = size.width * widthFactor;
      final rect = alignment.inscribe(
        Size.square(diameter),
        Offset.zero & size,
      );
      canvas.drawOval(rect, Paint()..color = colour);
    }
  }
}

class Artwork extends ConsumerWidget {
  const Artwork(
    this.coverArt, {
    super.key,
    this.size,
    this.radius = 6,
    this.icon = Icons.album,
  });

  final String? coverArt;
  final double? size;
  final double radius;
  final IconData icon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final image = artworkImage(
      ref,
      coverArt,
      size: (size ?? 600) > 200 ? 800 : 300,
    );
    final placeholder = Container(
      color: context.colors.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(icon, color: context.subtle, size: (size ?? 120) * 0.4),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox.square(
        dimension: size,
        child: AspectRatio(
          aspectRatio: 1,
          child: image == null
              ? placeholder
              : Image(
                  image: image,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => placeholder,
                ),
        ),
      ),
    );
  }
}
