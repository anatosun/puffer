import 'package:flutter_test/flutter_test.dart';
import 'package:puffer/data/subsonic/models.dart';
import 'package:puffer/features/now_playing/song_info.dart';
import 'package:puffer/playback/crossfade.dart';

Track track(String id, {String? album}) => Track({'id': id, 'albumId': ?album});

void main() {
  test('songs of the same album never fade into each other', () {
    expect(crossfades(track('1', album: 'a'), track('2', album: 'a')), isFalse);
    expect(crossfades(track('1', album: 'a'), track('2', album: 'b')), isTrue);
    // Without an album, as for some streams, the songs fade.
    expect(crossfades(track('1'), track('2', album: 'a')), isTrue);
  });

  test('a fade keeps the loudness even with equal-power curves', () {
    expect(crossfadeVolumes(0), (1.0, 0.0));
    final (out, into) = crossfadeVolumes(0.5);
    expect(out, closeTo(into, 1e-9));
    expect(out * out + into * into, closeTo(1, 1e-9));
    final (end, full) = crossfadeVolumes(1.5);
    expect(end, closeTo(0, 1e-9));
    expect(full, closeTo(1, 1e-9));
  });

  test('song info lists what the server reports and skips the rest', () {
    final rows = songInfo(
      Track(const {
        'id': '1',
        'suffix': 'flac',
        'bitRate': 1411,
        'samplingRate': 44100,
        'bitDepth': 16,
        'channelCount': 2,
        'size': 31457280,
        'duration': 245,
        'replayGain': {'trackGain': -7.5, 'albumGain': 1.25},
        'genre': 'Jazz',
        'year': 1959,
        'playCount': 12,
        'path': 'Miles Davis/Kind of Blue/01.flac',
      }),
    );
    expect(rows, [
      ('Format', 'FLAC'),
      ('Bit rate', '1411 kbps'),
      ('Sample rate', '44.1 kHz'),
      ('Bit depth', '16-bit'),
      ('Channels', 'Stereo'),
      ('Size', '30.0 MB'),
      ('Length', '4:05'),
      ('Track gain', '-7.50 dB'),
      ('Album gain', '+1.25 dB'),
      ('Genre', 'Jazz'),
      ('Year', '1959'),
      ('Plays', '12'),
      ('File', 'Miles Davis/Kind of Blue/01.flac'),
    ]);
    expect(
      songInfo(Track(const {'id': '2', 'suffix': 'mp3'})).map((r) => r.$1),
      ['Format', 'Length'],
    );
  });
}
