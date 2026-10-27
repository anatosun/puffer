import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:puffer/data/subsonic/models.dart';
import 'package:puffer/playback/queue_store.dart';

void main() {
  late Directory dir;
  late QueueStore store;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('queue_test');
    store = QueueStore(File('${dir.path}/queue.json'));
  });

  tearDown(() => dir.delete(recursive: true));

  test('a saved queue loads with its index and position', () async {
    await store.save(
      const [
        Track({'id': 'a'}),
        Track({'id': 'b'}),
      ],
      1,
      const Duration(seconds: 42),
    );
    final saved = (await store.load())!;
    expect(saved.tracks.map((t) => t.id), ['a', 'b']);
    expect(saved.index, 1);
    expect(saved.position, const Duration(seconds: 42));
  });

  test('saving an empty queue clears it', () async {
    await store.save(
      const [
        Track({'id': 'a'}),
      ],
      0,
      Duration.zero,
    );
    await store.save(const [], 0, Duration.zero);
    expect(await store.load(), isNull);
  });

  test('a damaged file loads as no queue', () async {
    await File('${dir.path}/queue.json').writeAsString('{not json');
    expect(await store.load(), isNull);
  });
}
