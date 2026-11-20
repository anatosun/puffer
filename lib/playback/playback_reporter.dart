/// The states of the OpenSubsonic `reportPlayback` endpoint.
enum PlaybackReportState { starting, playing, paused, stopped }

/// What to tell the server about a song: its state and the position in it.
class PlaybackReport {
  const PlaybackReport(this.trackId, this.state, this.position);

  final String trackId;
  final PlaybackReportState state;
  final Duration position;

  @override
  bool operator ==(Object other) =>
      other is PlaybackReport &&
      other.trackId == trackId &&
      other.state == state &&
      other.position == position;

  @override
  int get hashCode => Object.hash(trackId, state, position);

  @override
  String toString() => 'PlaybackReport($trackId, ${state.name}, $position)';
}

/// Turns what plays into the reports the server needs, one per change: a song starts (`starting`, then `playing`), pauses, plays on, moves to another place, starts over, or ends (`stopped`). It reports nothing while nothing changes, so it needs no timer: the server moves the position on by itself between reports.
class PlaybackReporter {
  /// A position this far from where the song should be is a seek.
  static const seek = Duration(seconds: 5);

  String? _track;
  bool _started = false;
  bool _playing = false;
  Duration _position = Duration.zero;
  DateTime? _at;

  /// The reports for the song [trackId] (null when nothing plays or nothing is reported), [playing] or not, at [position] at the time [now].
  List<PlaybackReport> update({
    required String? trackId,
    required bool playing,
    required Duration position,
    required DateTime now,
  }) {
    final reports = <PlaybackReport>[];
    final expected = _expected(now);
    if (trackId != _track) {
      if (_track case final previous? when _started) {
        reports.add(
          PlaybackReport(previous, PlaybackReportState.stopped, expected),
        );
      }
      _track = trackId;
      _started = false;
    } else if (trackId != null && _started) {
      final jumped = (position - expected).abs() > seek;
      if (jumped && position < seek && expected > seek * 2) {
        // Back to the start, as when one song repeats: the play ends and another begins.
        reports.add(
          PlaybackReport(trackId, PlaybackReportState.stopped, expected),
        );
        _started = false;
      } else if (jumped && playing == _playing) {
        reports.add(PlaybackReport(trackId, _state(playing), position));
      }
    }
    if (trackId != null) {
      if (playing && !_started) {
        _started = true;
        reports
          ..add(PlaybackReport(trackId, PlaybackReportState.starting, position))
          ..add(PlaybackReport(trackId, PlaybackReportState.playing, position));
      } else if (_started && playing != _playing) {
        reports.add(PlaybackReport(trackId, _state(playing), position));
      }
    }
    _playing = playing;
    _position = position;
    _at = now;
    return reports;
  }

  static PlaybackReportState _state(bool playing) =>
      playing ? PlaybackReportState.playing : PlaybackReportState.paused;

  Duration _expected(DateTime now) {
    final at = _at;
    if (at == null || !_playing) return _position;
    return _position + now.difference(at);
  }
}
