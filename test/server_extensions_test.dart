import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:puffer/app/providers.dart';
import 'package:puffer/data/subsonic/models.dart';
import 'package:puffer/downloads/download_settings.dart';
import 'package:puffer/features/now_playing/song_info.dart';
import 'package:puffer/playback/audio_format.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> container(Set<String> extensions) async {
  SharedPreferences.setMockInitialValues({
    'playback.qualityWifi': DownloadQuality.opus128.name,
  });
  final prefs = await SharedPreferences.getInstance();
  final c = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      connectivityProvider.overrideWithValue(const AsyncData([])),
      extensionsProvider.overrideWithValue(AsyncData(extensions)),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

const flac = Track({
  'id': '1',
  'suffix': 'flac',
  'contentType': 'audio/flac',
  'bitRate': 1411,
  'samplingRate': 44100,
  'bitDepth': 16,
  'channelCount': 2,
  'size': 31457280,
  'duration': 240,
});

void main() {
  test('features follow the extensions the server reports', () async {
    final none = await container({});
    expect(none.read(canMixProvider), isFalse);
    expect(none.read(hasTopSongsProvider), isFalse);

    final all = await container({'sonicSimilarity', 'topSongsByArtistId'});
    expect(all.read(canMixProvider), isTrue);
    expect(all.read(hasTopSongsProvider), isTrue);
  });

  test('streams follow the quality setting without the transcoding extension, since format and maxBitRate are core Subsonic', () async {
    expect(
      (await container({})).read(streamingQualityProvider),
      DownloadQuality.opus128,
    );
  });

  test('a transcoded download shows its own format, bit rate and size, with the original after', () {
    final rows = songInfo(
      flac,
      delivery: (
        source: PlayingSource.download,
        format: 'opus',
        maxBitRate: null,
        size: 3840000,
      ),
    );
    expect(rows.take(6), [
      ('Source', 'Downloaded file'),
      ('Format', 'OPUS'),
      ('Bit rate', '128 kbps'),
      ('Channels', 'Stereo'),
      ('Size', '3.7 MB'),
      ('Original', 'FLAC · 16/44.1 · 30.0 MB'),
    ]);
  });

  test(
    'a transcoded stream shows the format and bit rate asked of the server',
    () {
      final rows = songInfo(
        flac,
        delivery: (
          source: PlayingSource.stream,
          format: 'mp3',
          maxBitRate: 320,
          size: null,
        ),
      );
      expect(rows.take(5), [
        ('Source', 'Stream, transcoded by the server'),
        ('Format', 'MP3'),
        ('Bit rate', '320 kbps'),
        ('Channels', 'Stereo'),
        ('Original', 'FLAC · 16/44.1 · 30.0 MB'),
      ]);
    },
  );

  test('the original file shows what the server reports', () {
    final rows = songInfo(
      flac,
      delivery: (
        source: PlayingSource.download,
        format: 'flac',
        maxBitRate: null,
        size: 31457280,
      ),
    );
    expect(rows.map((r) => r.$1), isNot(contains('Original')));
    expect(rows[1], ('Format', 'FLAC'));
    expect(rows, contains(('Bit depth', '16-bit')));
  });
}
