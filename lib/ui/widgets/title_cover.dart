import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'artwork.dart';
import 'puffer_shape.dart';

/// How many covers lend their colours to a title cover. Each is a colour extraction on the main isolate, kept for the session, so the count stays small.
const _maxColourSources = 3;

/// A cover made of [title] in large type over glowing colours, with the Puffer mark of the launch animation as a record in the middle, its spines rippling like a sound wave. The colours come from [artIds], the covers of the playlist, and from the name when there is no artwork, so each playlist looks its own. The ring takes its shape from [seed], so a playlist keeps its cover. Large covers also show [label] at the top and [detail] at the bottom.
class TitleCover extends ConsumerWidget {
  const TitleCover(
    this.title, {
    super.key,
    this.seed,
    this.artIds = const [],
    this.label,
    this.detail,
    this.size,
    this.radius = 4,
  });

  final String title;

  /// What the shape of the ring follows, such as the ID of the playlist; the title without one.
  final String? seed;

  /// Cover-art IDs whose colours the cover takes, the most important first.
  final List<String> artIds;

  /// A small line in capitals at the top, such as "Playlist · owner".
  final String? label;

  /// A small line under the title, such as the number of songs.
  final String? detail;
  final double? size;
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = _palette(ref, title, artIds);
    final grain = ref.watch(_grainProvider).value;
    final seed = _hash(this.seed ?? title);
    return SizedBox.square(
      dimension: size,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final side = math.min(constraints.maxWidth, constraints.maxHeight);
          final large = side >= 160;
          final inset = side * 0.07;
          return ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            // The cover is painted once and kept in its own layer, so scrolling a list of covers does not paint them again.
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _CoverPainter(
                  palette: palette,
                  seed: seed,
                  small: side < 64,
                  grain: side >= 120 ? grain : null,
                ),
                child: side < 64
                    ? Semantics(label: title, child: const SizedBox.expand())
                    : Padding(
                        padding: EdgeInsets.all(inset),
                        child: _CoverText(
                          title: title,
                          label: large ? label : null,
                          detail: large ? detail : null,
                          side: side,
                          mark: palette.first.primary,
                        ),
                      ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The text of a cover: the label at the top, the title and the detail at the bottom left.
class _CoverText extends StatelessWidget {
  const _CoverText({
    required this.title,
    required this.label,
    required this.detail,
    required this.side,
    required this.mark,
  });

  final String title;
  final String? label;
  final String? detail;
  final double side;

  /// The colour of the short bar under the label.
  final Color mark;

  @override
  Widget build(BuildContext context) {
    const shadow = [Shadow(color: Color(0x66000000), blurRadius: 12)];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label case final label?) ...[
          Text(
            label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textScaler: TextScaler.noScaling,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: side * 0.032,
              fontWeight: FontWeight.w600,
              letterSpacing: side * 0.006,
            ),
          ),
          SizedBox(height: side * 0.012),
          Container(width: side * 0.05, height: side * 0.006, color: mark),
        ],
        const Spacer(),
        Text(
          title,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          // The size follows the cover and not the text size of the system, as on printed artwork.
          textScaler: TextScaler.noScaling,
          style: TextStyle(
            color: Colors.white,
            fontSize: side * 0.135,
            fontWeight: FontWeight.w800,
            height: 1.02,
            letterSpacing: -side * 0.003,
            shadows: shadow,
          ),
        ),
        if (detail case final detail?) ...[
          SizedBox(height: side * 0.02),
          Text(
            detail,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textScaler: TextScaler.noScaling,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: side * 0.034,
              shadows: shadow,
            ),
          ),
        ],
      ],
    );
  }
}

/// The colours of a cover: one dark scheme per cover in [artIds] whose colours are known, or, without any, schemes from hues the name picks.
List<ColorScheme> _palette(WidgetRef ref, String name, List<String> artIds) {
  final schemes = <ColorScheme>[];
  for (final id in artIds.toSet().take(_maxColourSources)) {
    final image = artworkImage(ref, id, size: 300);
    if (image == null) continue;
    final scheme = ref
        .watch(artworkSchemeProvider((id, image, Brightness.dark)))
        .value;
    if (scheme != null) schemes.add(scheme);
  }
  return schemes.isNotEmpty ? schemes : ref.watch(_nameSchemesProvider(name));
}

/// Three dark schemes from hues apart from each other, picked by the name.
final _nameSchemesProvider = Provider.family<List<ColorScheme>, String>((
  ref,
  name,
) {
  final hue = (_hash(name) % 360).toDouble();
  return [
    for (final shift in const [0.0, 55.0, 200.0])
      ColorScheme.fromSeed(
        seedColor: HSVColor.fromAHSV(
          1,
          (hue + shift) % 360,
          0.65,
          0.85,
        ).toColor(),
        brightness: Brightness.dark,
      ),
  ];
});

/// A tile of film grain, made once per session and repeated over large covers.
final _grainProvider = FutureProvider<ui.Image>((ref) async {
  const side = 128;
  final random = math.Random(7);
  final pixels = Uint8List(side * side * 4);
  // The pixels are premultiplied: a light speck has its colour scaled by its opacity.
  for (var i = 0; i < pixels.length; i += 4) {
    final light = random.nextBool();
    final alpha = random.nextInt(light ? 18 : 26);
    final value = light ? alpha : 0;
    pixels[i] = value;
    pixels[i + 1] = value;
    pixels[i + 2] = value;
    pixels[i + 3] = alpha;
  }
  final image = await _decode(pixels, side);
  ref.onDispose(image.dispose);
  return image;
});

Future<ui.Image> _decode(Uint8List pixels, int side) {
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    pixels,
    side,
    side,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

/// [colour] with its saturation raised and its lightness set, so the colours of a cover glow like printed artwork rather than look washed out.
Color _vivid(Color colour, {required double lightness}) {
  final hsl = HSLColor.fromColor(colour);
  return hsl
      .withSaturation(math.max(hsl.saturation, 0.7).clamp(0, 0.9))
      .withLightness(lightness)
      .toColor();
}

/// A hash of [text] that stays the same from run to run, unlike [String.hashCode].
int _hash(String text) {
  var h = 0x811c9dc5;
  for (final unit in text.codeUnits) {
    h = ((h ^ unit) * 0x01000193) & 0x7fffffff;
  }
  return h;
}

class _CoverPainter extends CustomPainter {
  _CoverPainter({
    required this.palette,
    required this.seed,
    required this.small,
    required this.grain,
  });

  final List<ColorScheme> palette;
  final int seed;

  /// Draws the mark larger and bolder, for covers too small for the title.
  final bool small;
  final ui.Image? grain;

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide;
    final random = math.Random(seed);
    final rect = Offset.zero & size;

    // The ground: the darkest colour, with glows of the others over it.
    canvas.drawRect(
      rect,
      Paint()..color = _vivid(palette.first.primary, lightness: 0.16),
    );
    final glows = [
      for (final s in palette) ...[
        _vivid(s.primary, lightness: 0.38),
        _vivid(s.tertiary, lightness: 0.32),
      ],
    ];
    for (var i = 0; i < math.min(glows.length, 4); i++) {
      final centre = Offset(
        size.width * random.nextDouble(),
        size.height * random.nextDouble(),
      );
      final radius = side * (0.6 + 0.4 * random.nextDouble());
      canvas.drawRect(
        rect,
        Paint()
          ..shader = ui.Gradient.radial(centre, radius, [
            glows[i].withValues(alpha: 0.9),
            glows[i].withValues(alpha: 0),
          ]),
      );
    }

    // The Puffer mark as the launch animation leaves it, a record in the middle of the cover: its spines ripple along a wave of the playlist's own, and the outline runs through the light colours.
    final small = this.small;
    final box = side * (small ? 0.95 : 0.76);
    canvas.save();
    canvas.translate(size.width / 2 - box / 2, size.height / 2 - box / 2);
    canvas.scale(box / 100);
    final body = PufferShape.body(
      amp: 1.15,
      wobble: 0.3 + 0.2 * random.nextDouble(),
      phase: random.nextDouble() * math.pi * 2,
    );
    // The light colour of each source, and a second one of the first, so a cover with one source still has two.
    final inks = [
      for (final s in palette) _vivid(s.primary, lightness: 0.74),
      _vivid(palette.first.tertiary, lightness: 0.7),
    ];
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..strokeWidth = PufferShape.bodyStroke * (small ? 1.6 : 0.85)
      ..shader = SweepGradient(
        colors: [...inks, inks.first],
        transform: GradientRotation(random.nextDouble() * math.pi * 2),
      ).createShader(Rect.fromCircle(center: PufferShape.centre, radius: 50));
    canvas.drawPath(body, outline);
    final white = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..color = Colors.white;
    canvas.drawPath(
      PufferShape.grooves(),
      white
        ..strokeWidth = PufferShape.grooveStroke * (small ? 1.6 : 1)
        ..color = Colors.white.withValues(alpha: 0.7),
    );
    canvas.drawPath(
      PufferShape.label(),
      white
        ..strokeWidth = PufferShape.labelStroke * (small ? 1.4 : 1)
        ..color = Colors.white,
    );
    canvas.drawCircle(
      PufferShape.centre,
      PufferShape.spindle,
      Paint()..color = Colors.white,
    );
    canvas.restore();

    // A shade towards the bottom left, where the title stands.
    if (!small) {
      canvas.drawRect(
        rect,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(size.width * 0.7, size.height * 0.3),
            Offset(0, size.height),
            [
              Colors.black.withValues(alpha: 0),
              Colors.black.withValues(alpha: 0.45),
            ],
          ),
      );
    }

    if (grain case final grain?) {
      canvas.drawRect(
        rect,
        Paint()
          ..shader = ImageShader(
            grain,
            TileMode.repeated,
            TileMode.repeated,
            Matrix4.identity().storage,
          ),
      );
    }
  }

  @override
  bool shouldRepaint(_CoverPainter old) =>
      old.seed != seed ||
      old.small != small ||
      old.grain != grain ||
      !_samePalette(old.palette, palette);

  static bool _samePalette(List<ColorScheme> a, List<ColorScheme> b) =>
      a.length == b.length &&
      Iterable.generate(a.length).every((i) => a[i] == b[i]);
}
