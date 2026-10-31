import 'package:flutter_test/flutter_test.dart';
import 'package:puffer/data/music_assistant/ma_models.dart';
import 'package:puffer/data/subsonic/models.dart';
import 'package:puffer/downloads/download_manager.dart';
import 'package:puffer/downloads/download_settings.dart';

Album _album(Map<String, Object?> fields) => Album({'id': 'a', ...fields});

void main() {
  test('albums group by their OpenSubsonic release types', () {
    expect(_album({}).releaseKind, ReleaseKind.album);
    expect(
      _album({
        'releaseTypes': ['Album'],
      }).releaseKind,
      ReleaseKind.album,
    );
    expect(
      _album({
        'releaseTypes': ['EP'],
      }).releaseKind,
      ReleaseKind.ep,
    );
    expect(
      _album({
        'releaseTypes': ['single'],
      }).releaseKind,
      ReleaseKind.single,
    );
    expect(
      _album({
        'releaseTypes': ['Album', 'Live'],
      }).releaseKind,
      ReleaseKind.live,
    );
    expect(
      _album({
        'releaseTypes': ['Album', 'Compilation'],
      }).releaseKind,
      ReleaseKind.compilation,
    );
    expect(
      _album({'isCompilation': true}).releaseKind,
      ReleaseKind.compilation,
    );
  });

  test('a queue item sent as a stream URL carries its Subsonic ID', () {
    MaQueueItem item(Map<String, Object?> media) =>
        MaQueueItem({'queue_item_id': 'q', 'media_item': media});
    expect(
      item({'uri': 'http://navidrome/rest/stream?id=t1&u=me'}).streamId,
      't1',
    );
    expect(
      item({
        'provider_mappings': [
          {'item_id': 'https://music.example/rest/stream.view?id=t2'},
        ],
      }).streamId,
      't2',
    );
    expect(item({'uri': 'library://track/12'}).streamId, isNull);
  });

  test('a transcoded download expects the bit rate times the duration', () {
    final track = Track({'id': 't', 'duration': 200, 'size': 9000000});
    expect(expectedBytes(track, DownloadQuality.original), 9000000);
    expect(expectedBytes(track, DownloadQuality.opus128), 128000 ~/ 8 * 200);
    expect(expectedBytes(Track({'id': 't'}), DownloadQuality.opus128), isNull);
  });
}
