import 'dart:math' as math;

import '../data/subsonic/models.dart';

/// Whether the song [from] fades into [to]. Songs of the same album never fade, since many albums run from one song into the next.
bool crossfades(Track from, Track to) =>
    from.albumId == null || to.albumId == null || from.albumId != to.albumId;

/// The volumes of the outgoing and the incoming song at [progress] from 0 to 1 of a fade. Equal-power curves keep the loudness even through the middle of the fade.
(double, double) crossfadeVolumes(double progress) {
  final t = progress.clamp(0.0, 1.0);
  return (math.cos(t * math.pi / 2), math.sin(t * math.pi / 2));
}
