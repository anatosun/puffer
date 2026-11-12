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

  test('the songs are written again only when they change', () async {
    const tracks = [
      Track({'id': 'a'}),
      Track({'id': 'b'}),
    ];
    final file = File('${dir.path}/queue.json');
    await store.save(tracks, 0, const Duration(seconds: 5));
    final written = await file.readAsString();
    await store.save(tracks, 1, const Duration(seconds: 9));
    expect(await file.readAsString(), written);

    // As after a restart.
    final saved = (await QueueStore(file).load())!;
    expect(saved.index, 1);
    expect(saved.position, const Duration(seconds: 9));

    await store.save(
      [
        ...tracks,
        const Track({'id': 'c'}),
      ],
      2,
      Duration.zero,
    );
    expect(await file.readAsString(), isNot(written));
    expect((await QueueStore(file).load())!.tracks, hasLength(3));
  });

  test('a place saved for another queue is left out', () async {
    final file = File('${dir.path}/queue.json');
    await store.save(
      const [
        Track({'id': 'a'}),
        Track({'id': 'b'}),
      ],
      1,
      const Duration(seconds: 7),
    );
    await File('${file.path}.place')
        .writeAsString('{"stamp": 1, "index": 0, "position": 3000}');
    final saved = (await QueueStore(file).load())!;
    expect(saved.index, 1);
    expect(saved.position, const Duration(seconds: 7));
  });

  test('a queue saved before the place had its own file loads', () async {
    await File('${dir.path}/queue.json').writeAsString(
      '{"index": 1, "position": 2000, "tracks": [{"id": "a"}, {"id": "b"}]}',
    );
    final saved = (await store.load())!;
    expect(saved.index, 1);
    expect(saved.position, const Duration(seconds: 2));
  });

  test('a damaged file loads as no queue', () async {
    await File('${dir.path}/queue.json').writeAsString('{not json');
    expect(await store.load(), isNull);
  });
}
