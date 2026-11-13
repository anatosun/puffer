import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/experience.dart';
import '../../app/playback_providers.dart';
import '../../app/providers.dart';

/// Whether the seek bar shows waveforms: the person has not turned them off, and the server reports the `songWaveform` extension or, offline, the downloads keep waveforms. The player sets its layout from this rather than from each waveform, so the layout stays the same while a waveform loads.
final waveformSupportedProvider = FutureProvider.autoDispose<bool>((ref) async {
  final client = ref.watch(clientProvider);
  if (client == null) return false;
  if (ref.watch(waveformStyleProvider) == WaveformStyle.off) return false;
  if (ref.watch(isOfflineProvider)) {
    return await ref.watch(repositoryProvider)?.hasStoredWaveforms() ?? false;
  }
  return client.supports('songWaveform');
});

/// Loudness of the track [id] for the seek bar, or null when waveforms are not supported or the request fails. The waveform kept with a download comes first; a downloaded song whose waveform comes from the server keeps it.
final waveformProvider = FutureProvider.autoDispose.family<List<int>?, String>((
  ref,
  id,
) async {
  if (!await ref.watch(waveformSupportedProvider.future)) return null;
  final repository = ref.read(repositoryProvider);
  final kept = await repository?.storedWaveform(id);
  if (kept != null) {
    ref.keepAlive();
    return kept;
  }
  if (ref.read(isOfflineProvider)) return null;
  final client = ref.read(clientProvider)!;
  try {
    final peaks = await client.getWaveform(id);
    if (peaks.isEmpty) return null;
    if (ref.read(downloadedTrackIdSetProvider).contains(id)) {
      await repository?.storeWaveform(id, peaks);
    }
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

/// The parts of the line of the seek bar, as fractions of its length from 0 to 1: played up to [progress], loaded up to [loaded] after that, and not loaded after. A [loaded] behind [progress] leaves no loaded part.
({double played, double loaded}) timelineParts(double progress, double loaded) {
  final played = progress.clamp(0.0, 1.0);
  return (played: played, loaded: math.max(played, loaded.clamp(0.0, 1.0)));
}

/// The seek bar: [peaks] as vertically centred bars, smoothed by [smoothBars], when there is a waveform, and a thin line across the middle. Bars and line are in [played] up to [progress] (0 to 1) and in [unplayed] after it; the line is in [loadedColour] where the player has loaded the song, up to [loaded].
class TimelinePainter extends CustomPainter {
  const TimelinePainter({
    this.peaks,
    required this.progress,
    required this.loaded,
    required this.played,
    required this.loadedColour,
    required this.unplayed,
    this.smooth = true,
  });

  static const barWidth = 2.0;
  static const barGap = 1.5;
  static const lineWidth = 2.0;

  final List<int>? peaks;
  final double progress;
  final double loaded;
  final Color played;
  final Color loadedColour;
  final Color unplayed;

  /// Smooths the bars with [smoothBars]; otherwise each bar shows its own loudness.
  final bool smooth;

  @override
  void paint(Canvas canvas, Size size) {
    final mid = size.height / 2;
    final playedX = progress.clamp(0.0, 1.0) * size.width;
    if (peaks case final peaks?) {
      const step = barWidth + barGap;
      final count = ((size.width + barGap) / step).floor();
      final raw = waveformBars(peaks, count);
      final bars = smooth ? smoothBars(raw) : raw;
      final playedPaint = Paint()..color = played;
      final unplayedPaint = Paint()..color = unplayed;
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
    final parts = timelineParts(progress, loaded);
    final top = mid - lineWidth / 2;
    // The line has round ends; the parts meet edge to edge inside it.
    canvas.save();
    canvas.clipRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, top, size.width, lineWidth),
        const Radius.circular(lineWidth / 2),
      ),
    );
    void part(double from, double to, Color colour) {
      if (to <= from) return;
      canvas.drawRect(
        Rect.fromLTRB(from * size.width, top, to * size.width, top + lineWidth),
        Paint()..color = colour,
      );
    }

    part(0, parts.played, played);
    part(parts.played, parts.loaded, loadedColour);
    part(parts.loaded, 1, unplayed);
    canvas.restore();
  }

  @override
  bool shouldRepaint(TimelinePainter oldDelegate) =>
      !identical(peaks, oldDelegate.peaks) ||
      progress != oldDelegate.progress ||
      loaded != oldDelegate.loaded ||
      played != oldDelegate.played ||
      loadedColour != oldDelegate.loadedColour ||
      unplayed != oldDelegate.unplayed ||
      smooth != oldDelegate.smooth;
}
