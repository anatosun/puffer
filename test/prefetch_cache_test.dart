import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:puffer/playback/prefetch_cache.dart';
import 'package:puffer/playback/stable_shuffle_order.dart';

void main() {
  late Directory dir;
  late List<Uri> requests;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('prefetch');
    requests = [];
  });
  tearDown(() => dir.delete(recursive: true));

  PrefetchCache cache({
    int maxBytes = 1000,
    http.Response Function(Uri)? respond,
  }) => PrefetchCache(
    Directory(p.join(dir.path, 'prefetch')),
    maxBytes: maxBytes,
    httpClient: MockClient((r) async {
      requests.add(r.url);
      return respond?.call(r.url) ??
          http.Response.bytes(
            List.filled(100, 1),
            200,
            headers: {'content-type': 'audio/mpeg'},
          );
    }),
  );

  Future<void> age(PrefetchCache c, String name, int minutesAgo) => File(
    p.join(c.dir.path, name),
  ).setLastModified(DateTime.now().subtract(Duration(minutes: minutesAgo)));

  test('file names carry the track, the quality and the format', () {
    expect(
      PrefetchCache.fileName('al/1', 'opus128', 'opus'),
      'al_1_opus128.opus',
    );
  });

  test('a song is fetched once and then read from the cache', () async {
    final c = cache();
    final uri = Uri.parse('https://music.example.com/rest/stream?id=1');
    final file = await c.fetch('1_original.flac', uri);
    expect(await file.length(), 100);
    await c.fetch('1_original.flac', uri);
    expect(requests, hasLength(1));
    expect((await c.existing('1_original.flac'))?.path, file.path);
    expect(await c.existing('2_original.flac'), isNull);
  });

  test(
    'a fetch reports its progress by hundredths up to the whole song',
    () async {
      final c = cache(
        respond: (_) => http.Response.bytes(
          List.filled(1000, 1),
          200,
          headers: {'content-type': 'audio/flac'},
        ),
      );
      final reports = <double>[];
      await c.fetch(
        '1_original.flac',
        Uri.parse('https://x/1'),
        progress: reports.add,
      );
      expect(reports.last, 1);
      expect(reports, orderedEquals([...reports]..sort()));
      expect(reports.length, lessThanOrEqualTo(101));
    },
  );

  test('a Subsonic error instead of audio leaves no file', () async {
    final c = cache(
      respond: (_) => http.Response(
        '{"subsonic-response":{"status":"failed"}}',
        200,
        headers: {'content-type': 'application/json'},
      ),
    );
    await expectLater(
      c.fetch('1_original.flac', Uri.parse('https://x/rest/stream')),
      throwsA(isA<HttpException>()),
    );
    expect(await c.size(), 0);
    expect(c.dir.listSync(), isEmpty);
  });

  test(
    'above the limit, the least recently used files go first, except kept ones',
    () async {
      final c = cache(maxBytes: 250);
      for (final name in ['a.mp3', 'b.mp3', 'c.mp3']) {
        await c.fetch(name, Uri.parse('https://x/$name'));
      }
      await age(c, 'a.mp3', 30);
      await age(c, 'b.mp3', 20);
      await age(c, 'c.mp3', 10);
      expect(await c.evict(keep: {'a.mp3'}), ['b.mp3']);
      expect(await c.existing('a.mp3'), isNotNull);
      expect(await c.existing('c.mp3'), isNotNull);
      expect(await c.evict(), isEmpty);
    },
  );

  test('reading a file marks it as used, so it outlives older files', () async {
    final c = cache(maxBytes: 150);
    await c.fetch('a.mp3', Uri.parse('https://x/a'));
    await c.fetch('b.mp3', Uri.parse('https://x/b'));
    await age(c, 'a.mp3', 30);
    await age(c, 'b.mp3', 20);
    await c.existing('a.mp3');
    expect(await c.evict(), ['b.mp3']);
  });

  test('clearing keeps the files the queue plays from', () async {
    final c = cache();
    await c.fetch('a.mp3', Uri.parse('https://x/a'));
    await c.fetch('b.mp3', Uri.parse('https://x/b'));
    await c.clear(keep: {'b.mp3'});
    expect(await c.existing('a.mp3'), isNull);
    expect(await c.existing('b.mp3'), isNotNull);
  });

  group('upcoming songs', () {
    test('follow the play order', () {
      expect(upcomingIndices([0, 1, 2, 3, 4], 1), [2, 3, 4]);
      expect(upcomingIndices([3, 0, 4, 1, 2], 0), [4, 1, 2]);
    });

    test('stop at the end, or wrap around when the queue repeats', () {
      expect(upcomingIndices([0, 1, 2, 3], 2), [3]);
      expect(upcomingIndices([0, 1, 2, 3], 2, loop: true), [3, 0, 1]);
      expect(upcomingIndices([0, 1], 0, loop: true), [1]);
    });
  });

  test('a song replaced in place keeps its place in the shuffle order', () {
    final order = StableShuffleOrder(random: Random(1))
      ..insert(0, 6)
      ..shuffle(initialIndex: 0);
    final before = List.of(order.indices);
    order
      ..replacing(3)
      ..removeRange(3, 4)
      ..insert(3, 1);
    expect(order.indices, before);
  });
}
