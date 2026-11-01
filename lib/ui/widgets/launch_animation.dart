// Puffer launch animation — a Flutter port of the approved launch film.
//
// A round line-drawn body with an eye at the top right appears and puffs up,
// spines rise all round like a waveform, the eye glides to the centre and
// becomes the record's spindle, the grooves draw in while the record turns
// into place, and the "puffer" wordmark settles beneath.
//
// No dependencies beyond Flutter. The wordmark uses the bundled
// "InterTight" font family (fonts/InterTight-SemiBold.ttf, weight 600);
// declare it in pubspec.yaml or pass another [fontFamily].
//
// Usage:
//   PufferLaunchAnimation(onFinished: () => Navigator.of(context).pushReplacement(...))

import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';

class PufferLaunchAnimation extends StatefulWidget {
  const PufferLaunchAnimation({
    super.key,
    this.markSize = 200,
    this.color = const Color(0xFFF5F5F7),
    this.background = const Color(0xFF0D0E11),
    this.fontFamily = 'InterTight',
    this.showWordmark = true,
    this.onFinished,
  });

  /// Size of the mark's 100×100 drawing box, in logical pixels.
  final double markSize;
  final Color color;
  final Color background;
  final String fontFamily;
  final bool showWordmark;

  /// Called once, when the animation has finished (after 3.6 s).
  final VoidCallback? onFinished;

  /// Total length of the animation.
  static const Duration duration = Duration(milliseconds: 3600);

  @override
  State<PufferLaunchAnimation> createState() => _PufferLaunchAnimationState();
}

class _PufferLaunchAnimationState extends State<PufferLaunchAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _reported = false;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(
          vsync: this,
          duration: PufferLaunchAnimation.duration,
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed && !_reported) {
            _reported = true;
            widget.onFinished?.call();
          }
        });
    // Respect the system "reduce motion" setting: jump to the final frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
        _controller.value = 1;
      } else {
        _controller.forward();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.markSize;
    return ColoredBox(
      color: widget.background,
      child: Center(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final t =
                _controller.value * 3.6; // seconds, same timeline as the film
            final puff = _lerp(0.88, 1, _eob(_seg(t, 0.85, 1.5), 1.6));
            final rise = _lerp(110 / 520, 0, _eio(_seg(t, 2.55, 3.1))) * s;
            final breathe = t > 3.1
                ? 1 + 0.008 * math.sin(2 * math.pi * (t - 3.1) / 3)
                : 1.0;
            final w = _eo(_seg(t, 2.75, 3.25));
            final fontSize = s * 150 / 520;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Transform.translate(
                  offset: Offset(0, rise),
                  child: Transform.scale(
                    scale: puff * breathe,
                    child: SizedBox.square(
                      dimension: s,
                      child: CustomPaint(
                        painter: _PufferPainter(t, widget.color),
                      ),
                    ),
                  ),
                ),
                if (widget.showWordmark) ...[
                  SizedBox(height: s * 50 / 520),
                  Opacity(
                    opacity: w.clamp(0.0, 1.0),
                    child: Transform.translate(
                      offset: Offset(0, _lerp(30 / 520, 0, w) * s),
                      child: Text(
                        'puffer',
                        textHeightBehavior: const TextHeightBehavior(
                          applyHeightToFirstAscent: false,
                          applyHeightToLastDescent: false,
                        ),
                        style: TextStyle(
                          fontFamily: widget.fontFamily,
                          fontWeight: FontWeight.w600,
                          fontSize: fontSize,
                          height: 1,
                          letterSpacing: -0.045 * fontSize,
                          color: widget.color,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PufferPainter extends CustomPainter {
  _PufferPainter(this.t, this.color);

  final double t;
  final Color color;

  static const int n = 28;
  static const List<double> pattern = [13, 4.5, 8, 4.5];
  static const double r = 26;
  static final double d = 2 * math.pi / n * 0.2;
  static const Offset c = Offset(50, 50);

  static double _ang(int i) => 2 * math.pi * i / n - math.pi / 2;
  static Offset _p(double a, double rad) =>
      Offset(50 + rad * math.cos(a), 50 + rad * math.sin(a));

  Path _body(double amp, double wob, double ph) {
    final pts = <Offset>[];
    for (var i = 0; i < n; i++) {
      final a = _ang(i);
      final len =
          pattern[i % 4] * amp * (1 + wob * math.sin(ph + i * 0.9)) + 0.001;
      pts
        ..add(_p(a - d, r))
        ..add(_p(a, r + len))
        ..add(_p(a + d, r));
    }
    final path = Path()..moveTo(pts[0].dx, pts[0].dy);
    for (var k = 1; k < pts.length; k++) {
      if (k % 3 == 0) {
        path.arcToPoint(pts[k], radius: const Radius.circular(r));
      } else {
        path.lineTo(pts[k].dx, pts[k].dy);
      }
    }
    path
      ..arcToPoint(pts[0], radius: const Radius.circular(r))
      ..close();
    return path;
  }

  static Path _grooves() {
    Path arc(double rad, double a0, double a1) {
      final sweep = ((a1 - a0) % 360 + 360) % 360;
      return Path()..addArc(
        Rect.fromCircle(center: c, radius: rad),
        a0 * math.pi / 180,
        sweep * math.pi / 180,
      );
    }

    return Path()
      ..addPath(arc(19, -150, 40), Offset.zero)
      ..addPath(arc(19, 70, 150), Offset.zero)
      ..addPath(arc(13, 20, 200), Offset.zero);
  }

  static Path _label() =>
      Path()..addOval(Rect.fromCircle(center: c, radius: 6));

  /// The first [f] (0..1) of [path]'s total length, for draw-on strokes.
  static Path _partial(Path path, double f) {
    if (f >= 1) return path;
    final out = Path();
    if (f <= 0) return out;
    final metrics = path.computeMetrics().toList();
    final total = metrics.fold<double>(
      0,
      (sum, PathMetric m) => sum + m.length,
    );
    var left = total * f;
    for (final m in metrics) {
      if (left <= 0) break;
      final take = math.min(left, m.length);
      out.addPath(m.extractPath(0, take), Offset.zero);
      left -= take;
    }
    return out;
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 100, size.height / 100);
    Paint stroke(double w) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    // Body: draws on, then spines spring out and ripple like a waveform.
    final amp = _eob(_seg(t, 1.45, 2.3), 1.6);
    final wob = math.sin(math.pi * _seg(t, 2.0, 3.2)) * 0.35;
    final ph = t * 2 * math.pi * 1.6;
    canvas.drawPath(
      _partial(_body(amp, wob, ph), _eio(_seg(t, -0.5, 0.55))),
      stroke(2.8),
    );

    // Record: label ring and grooves draw in while the disc turns into place.
    canvas.save();
    canvas.translate(50, 50);
    canvas.rotate(_lerp(-90, 0, _eo(_seg(t, 2.1, 3.1))) * math.pi / 180);
    canvas.translate(-50, -50);
    canvas.drawPath(_partial(_label(), _eio(_seg(t, 2.05, 2.5))), stroke(2.2));
    canvas.drawPath(
      _partial(_grooves(), _eio(_seg(t, 2.15, 2.8))),
      stroke(1.5),
    );
    canvas.restore();

    // Eye: pops in at the top right, glides to the centre and becomes the spindle.
    final pop = math.max(0.0, _eob(_seg(t, 0.55, 0.85), 1.8));
    if (pop > 0) {
      final p = _eio(_seg(t, 1.45, 2.25));
      final ex = _lerp(62, 50, p);
      final ey = _lerp(40, 50, p) - math.sin(math.pi * p) * 4;
      final er = _lerp(3.6, 1.6, _eio(_seg(t, 1.95, 2.35))) * pop;
      canvas.drawCircle(Offset(ex, ey), er, Paint()..color = color);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PufferPainter old) => old.t != t || old.color != color;
}

// Timing helpers, identical to the film's.
double _seg(double t, double a, double b) =>
    ((t - a) / (b - a)).clamp(0.0, 1.0);
double _lerp(double a, double b, double k) => a + (b - a) * k;
double _eo(double x) => 1 - math.pow(1 - x, 3).toDouble();
double _eio(double x) =>
    x < 0.5 ? 4 * x * x * x : 1 - math.pow(-2 * x + 2, 3).toDouble() / 2;
double _eob(double x, [double s = 1.4]) {
  final y = x - 1;
  return 1 + (s + 1) * y * y * y + s * y * y;
}
