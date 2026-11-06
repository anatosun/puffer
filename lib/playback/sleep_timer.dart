import '../data/subsonic/models.dart';

/// When the sleep timer pauses playback.
enum SleepMode { after, endOfSong, endOfAlbum }

/// A running sleep timer. [endsAt] is set for [SleepMode.after]; [trackId] and [albumId] name the song or album that plays to its end.
class SleepTimer {
  const SleepTimer.after(DateTime this.endsAt)
    : mode = SleepMode.after,
      trackId = null,
      albumId = null;

  const SleepTimer.endOfSong(String this.trackId)
    : mode = SleepMode.endOfSong,
      endsAt = null,
      albumId = null;

  const SleepTimer.endOfAlbum(this.trackId, String this.albumId)
    : mode = SleepMode.endOfAlbum,
      endsAt = null;

  final SleepMode mode;
  final DateTime? endsAt;
  final String? trackId;
  final String? albumId;

  /// Whether the songs fading into each other would play past the end the timer waits for, so crossfade holds off.
  bool get waitsForSongEnd => mode != SleepMode.after;

  /// Whether playback should pause now that [current] plays: another song after the one of [SleepMode.endOfSong], or a song of another album after the one of [SleepMode.endOfAlbum].
  bool endsWith(Track? current) {
    if (current == null) return false;
    return switch (mode) {
      SleepMode.after => false,
      SleepMode.endOfSong => current.id != trackId,
      SleepMode.endOfAlbum => current.albumId != albumId,
    };
  }

  /// How long is left, for [SleepMode.after].
  Duration? remaining(DateTime now) {
    final end = endsAt;
    if (end == null) return null;
    final left = end.difference(now);
    return left.isNegative ? Duration.zero : left;
  }
}

/// The lengths offered for a sleep timer, in minutes.
const sleepTimerMinutes = [15, 30, 45, 60, 90];

/// How long the volume takes to fade out before the timer pauses playback on this device.
const sleepFade = Duration(seconds: 8);
