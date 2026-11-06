import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/experience.dart';
import '../../app/playback_providers.dart';
import '../../app/providers.dart';

/// Whether the seek bar shows waveforms: the person has not turned them off, the server reports the `songWaveform` extension and the app is online. The player sets its layout from this rather than from each waveform, so the layout stays the same while a waveform loads.
final waveformSupportedProvider = FutureProvider.autoDispose<bool>((ref) async {
  final client = ref.watch(clientProvider);
  if (client == null || ref.watch(isOfflineProvider)) return false;
  if (ref.watch(waveformStyleProvider) == WaveformStyle.off) return false;
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

/// Loads the waveform of a track as soon as it plays, on this device or on a Music Assistant player, so the player shows it when it opens, and the waveforms of the songs fetched ahead, so the seek bar has them when their turn comes. The app watches this for the whole session.
final playingWaveformProvider = Provider<void>((ref) {
  final id = ref.watch(nowPlayingProvider.select((s) => s.value?.track?.id));
  if (id != null) ref.watch(waveformProvider(id));
  for (final next in ref.watch(prefetchedTrackIdsProvider)) {
    ref.watch(waveformProvider(next));
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

/// Smooths [bars] with a small Gaussian kernel, so neighbouring bars rise and fall together and the outline reads as a curve. Each bar averages itself and the two bars on either side, the nearest weighing most; at the ends, the weights of the missing neighbours are left out.
List<double> smoothBars(List<double> bars) {
  const weights = [1.0, 4.0, 6.0, 4.0, 1.0];
  return List.generate(bars.length, (i) {
    var sum = 0.0, total = 0.0;
    for (var k = -2; k <= 2; k++) {
      final j = i + k;
      if (j < 0 || j >= bars.length) continue;
      sum += bars[j] * weights[k + 2];
      total += weights[k + 2];
    }
    return sum / total;
  });
}

/// Draws [peaks] as vertically centred bars, smoothed by [smoothBars],, in [played] up to [progress] (0 to 1) and in [unplayed] after it.
class WaveformPainter extends CustomPainter {
  const WaveformPainter({
    required this.peaks,
    required this.progress,
    required this.played,
    required this.unplayed,
    this.smooth = true,
  });

  static const barWidth = 2.0;
  static const barGap = 1.5;

  final List<int> peaks;
  final double progress;
  final Color played;
  final Color unplayed;

  /// Smooths the bars with [smoothBars]; otherwise each bar shows its own loudness.
  final bool smooth;

  @override
  void paint(Canvas canvas, Size size) {
    const step = barWidth + barGap;
    final count = ((size.width + barGap) / step).floor();
    final raw = waveformBars(peaks, count);
    final bars = smooth ? smoothBars(raw) : raw;
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
      unplayed != oldDelegate.unplayed ||
      smooth != oldDelegate.smooth;
}
