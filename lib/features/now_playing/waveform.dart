import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';

/// Whether the seek bar shows waveforms: the server reports the `songWaveform` extension and the app is online. The player sets its layout from this rather than from each waveform, so the layout stays the same while a waveform loads.
final waveformSupportedProvider = FutureProvider.autoDispose<bool>((ref) async {
  final client = ref.watch(clientProvider);
  if (client == null || ref.watch(isOfflineProvider)) return false;
  return client.supports('songWaveform');
});

/// Loudness of the track [id] for the seek bar, or null when waveforms are not supported or the request fails.
final waveformProvider = FutureProvider.autoDispose.family<List<int>?, String>((
  ref,
  id,
) async {
  if (!await ref.watch(waveformSupportedProvider.future)) return null;
  final client = ref.read(clientProvider)!;
  try {
    final peaks = await client.getWaveform(id);
    if (peaks.isEmpty) return null;
    ref.keepAlive();
    return peaks;
  } on Exception {
    return null;
  }
});

/// Heights from 0 to 1 of [count] bars. Each bar is the quadratic mean of the peaks it covers, because the server sends RMS values, and its height is that value squared relative to the loudest peak, which spreads out the loud range most mastered music sits in.
List<double> waveformBars(List<int> peaks, int count) {
  if (peaks.isEmpty || count <= 0) return const [];
  final loudest = math.max(1, peaks.reduce(math.max));
  return List.generate(count, (i) {
    final from = i * peaks.length ~/ count;
    final to = math.max(from + 1, (i + 1) * peaks.length ~/ count);
    var sum = 0.0;
    for (var j = from; j < to; j++) {
      sum += peaks[j] * peaks[j];
    }
    final rms = math.sqrt(sum / (to - from)) / loudest;
    return rms * rms;
  });
}

/// Draws [peaks] as vertically centred bars, in [played] up to [progress] (0 to 1) and in [unplayed] after it.
class WaveformPainter extends CustomPainter {
  const WaveformPainter({
    required this.peaks,
    required this.progress,
    required this.played,
    required this.unplayed,
  });

  static const barWidth = 2.0;
  static const barGap = 1.5;

  final List<int> peaks;
  final double progress;
  final Color played;
  final Color unplayed;

  @override
  void paint(Canvas canvas, Size size) {
    const step = barWidth + barGap;
    final count = ((size.width + barGap) / step).floor();
    final bars = waveformBars(peaks, count);
    final playedX = progress * size.width;
    final playedPaint = Paint()..color = played;
    final unplayedPaint = Paint()..color = unplayed;
    final mid = size.height / 2;
    for (var i = 0; i < bars.length; i++) {
      final x = i * step;
      final height = math.max(1.0, bars[i] * size.height);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, mid - height / 2, barWidth, height),
          const Radius.circular(1),
        ),
        x + barWidth / 2 <= playedX ? playedPaint : unplayedPaint,
      );
    }
  }

  @override
  bool shouldRepaint(WaveformPainter oldDelegate) =>
      !identical(peaks, oldDelegate.peaks) ||
      progress != oldDelegate.progress ||
      played != oldDelegate.played ||
      unplayed != oldDelegate.unplayed;
}
