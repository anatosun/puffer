import 'package:flutter_test/flutter_test.dart';
import 'package:puffer/data/subsonic/models.dart';
import 'package:puffer/playback/audio_format.dart';

void main() {
  test('lossless files show bit depth and sample rate', () {
    final hiRes = Track(const {
      'id': '1',
      'suffix': 'flac',
      'bitDepth': 24,
      'samplingRate': 96000,
    });
    expect(describeFormat(hiRes), (codec: 'FLAC', quality: '24/96'));
    final cd = Track(const {
      'id': '2',
      'suffix': 'flac',
      'samplingRate': 44100,
    });
    expect(describeFormat(cd), (codec: 'FLAC', quality: '44.1 kHz'));
  });

  test('lossy files show their bit rate', () {
    expect(
      describeFormat(Track(const {'id': '1', 'suffix': 'mp3', 'bitRate': 320})),
      (codec: 'MP3', quality: '320 kbps'),
    );
    expect(describeFormat(Track(const {'id': '1', 'suffix': 'ogg'})), (
      codec: 'OGG',
      quality: null,
    ));
  });

  test('a transcoded stream shows its own format', () {
    final track = Track(const {
      'id': '1',
      'suffix': 'flac',
      'samplingRate': 44100,
    });
    expect(describeFormat(track, format: 'opus', maxBitRate: 128), (
      codec: 'OPUS',
      quality: '128 kbps',
    ));
    // A downloaded file in the original format, as its extension tells.
    expect(describeFormat(track, format: 'flac'), (
      codec: 'FLAC',
      quality: '44.1 kHz',
    ));
  });
}
