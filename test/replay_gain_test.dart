import 'package:flutter_test/flutter_test.dart';
import 'package:puffer/data/subsonic/models.dart';
import 'package:puffer/playback/replay_gain.dart';

Track track(Map<String, dynamic>? rg) => Track({'id': 't', 'replayGain': ?rg});

void main() {
  test('off, or no ReplayGain data, plays at full volume', () {
    expect(replayGainVolume(track({'trackGain': -6.0}), ReplayGainMode.off), 1);
    expect(replayGainVolume(track(null), ReplayGainMode.track), 1);
  });

  test('a negative gain attenuates', () {
    expect(
      replayGainVolume(track({'trackGain': -6.0206}), ReplayGainMode.track),
      closeTo(0.5, 0.001),
    );
  });

  test(
    'album mode prefers the album gain and falls back to the track gain',
    () {
      expect(
        replayGainVolume(
          track({'trackGain': -6.0206, 'albumGain': 0.0}),
          ReplayGainMode.album,
        ),
        1,
      );
      expect(
        replayGainVolume(track({'trackGain': -6.0206}), ReplayGainMode.album),
        closeTo(0.5, 0.001),
      );
    },
  );

  test('the peak limits the volume and positive gains stay at full volume', () {
    expect(
      replayGainVolume(
        track({'trackGain': -1.0, 'trackPeak': 1.25}),
        ReplayGainMode.track,
      ),
      closeTo(0.8, 0.001),
    );
    expect(
      replayGainVolume(track({'trackGain': 4.0}), ReplayGainMode.track),
      1,
    );
  });
}
