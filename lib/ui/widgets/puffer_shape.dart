import 'dart:math' as math;

import 'package:flutter/painting.dart';

/// The drawing of the Puffer mark in its 100×100 box: a round body whose spines rise like a waveform, the grooves of a record inside it, the label ring and the spindle at the centre. The launch animation draws it on stroke by stroke, and the title covers of playlists draw its final frame.
abstract final class PufferShape {
  /// The number of spines around the body.
  static const int spines = 28;

  /// The lengths of the spines, repeated around the body: long, short, medium, short.
  static const List<double> pattern = [13, 4.5, 8, 4.5];

  /// The radius of the body.
  static const double radius = 26;
  static const Offset centre = Offset(50, 50);

  /// The stroke widths of the body, the label ring and the grooves.
  static const double bodyStroke = 2.8;
  static const double labelStroke = 2.2;
  static const double grooveStroke = 1.5;

  /// The radius of the spindle in the final frame.
  static const double spindle = 1.6;

  static final double _halfBase = 2 * math.pi / spines * 0.2;

  /// The angle of spine [i], the first at the top.
  static double angle(int i) => 2 * math.pi * i / spines - math.pi / 2;

  static Offset _at(double a, double r) =>
      Offset(50 + r * math.cos(a), 50 + r * math.sin(a));

  /// The outline of the body with its spines, as one path. [amp] scales the spines, and [wobble] ripples their lengths along a wave at [phase].
  static Path body({double amp = 1, double wobble = 0, double phase = 0}) {
    final points = <Offset>[];
    for (var i = 0; i < spines; i++) {
      final a = angle(i);
      final length =
          pattern[i % 4] * amp * (1 + wobble * math.sin(phase + i * 0.9)) +
          0.001;
      points
        ..add(_at(a - _halfBase, radius))
        ..add(_at(a, radius + length))
        ..add(_at(a + _halfBase, radius));
    }
    final path = Path()..moveTo(points[0].dx, points[0].dy);
    for (var k = 1; k < points.length; k++) {
      if (k % 3 == 0) {
        path.arcToPoint(points[k], radius: const Radius.circular(radius));
      } else {
        path.lineTo(points[k].dx, points[k].dy);
      }
    }
    return path
      ..arcToPoint(points[0], radius: const Radius.circular(radius))
      ..close();
  }

  /// The grooves of the record: two broken rings and a shorter arc inside them.
  static Path grooves() {
    Path arc(double r, double from, double to) {
      final sweep = ((to - from) % 360 + 360) % 360;
      return Path()..addArc(
        Rect.fromCircle(center: centre, radius: r),
        from * math.pi / 180,
        sweep * math.pi / 180,
      );
    }

    return Path()
      ..addPath(arc(19, -150, 40), Offset.zero)
      ..addPath(arc(19, 70, 150), Offset.zero)
      ..addPath(arc(13, 20, 200), Offset.zero);
  }

  /// The label ring around the spindle.
  static Path label() =>
      Path()..addOval(Rect.fromCircle(center: centre, radius: 6));
}
