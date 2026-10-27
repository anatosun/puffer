import 'dart:math';

import '../data/subsonic/models.dart';

enum ReplayGainMode {
  off('Off'),
  track('Track'),
  album('Album');

  const ReplayGainMode(this.label);

  final String label;
}

/// The player volume, from 0 to 1, that applies the ReplayGain of [track] reported by OpenSubsonic.
///
/// The player can only attenuate, so a positive gain plays at full volume. The peak keeps the result from clipping.
double replayGainVolume(Track track, ReplayGainMode mode) {
  final rg = track.json['replayGain'] as Map<String, dynamic>?;
  if (mode == ReplayGainMode.off || rg == null) return 1;
  double? value(String key) => (rg[key] as num?)?.toDouble();
  final album = mode == ReplayGainMode.album;
  final gain =
      (album
          ? value('albumGain') ?? value('trackGain')
          : value('trackGain') ?? value('albumGain')) ??
      value('fallbackGain');
  if (gain == null) return 1;
  final peak = album
      ? value('albumPeak') ?? value('trackPeak')
      : value('trackPeak') ?? value('albumPeak');
  var volume = pow(10, (gain + (value('baseGain') ?? 0)) / 20).toDouble();
  if (peak != null && peak > 0) volume = min(volume, 1 / peak);
  return volume.clamp(0, 1);
}
