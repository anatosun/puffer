import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:puffer/data/artwork_store.dart';

void main() {
  late Directory dir;
  late List<String> asked;
  var running = 0;
  var most = 0;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('artwork');
    asked = [];
    running = 0;
    most = 0;
  });
  tearDown(() => dir.delete(recursive: true));

  ArtworkStore store({http.Response Function(String id)? respond}) =>
      ArtworkStore(
        Directory(p.join(dir.path, 'artwork')),
        (id) => Uri.parse('https://x/rest/getCoverArt?id=$id'),
        httpClient: MockClient((request) async {
          final id = request.url.queryParameters['id']!;
          asked.add(id);
          running++;
          most = running > most ? running : most;
          await Future<void>.delayed(const Duration(milliseconds: 5));
          running--;
          return respond?.call(id) ??
              http.Response.bytes(
                [1, 2, 3],
                200,
                headers: {'content-type': 'image/jpeg'},
              );
        }),
      );

  test(
    'the covers of a download are fetched once each, one after another',
    () async {
      final s = store();
      await s.ensureAll(['al-1', 'mf-1', null, 'mf-2', 'al-1', 'mf-1']);
      expect(asked, ['al-1', 'mf-1', 'mf-2']);
      expect(most, 1);
      for (final id in ['al-1', 'mf-1', 'mf-2']) {
        expect(s.existing(id), isNotNull);
      }
      await s.ensureAll(['al-1', 'mf-2']);
      expect(asked, hasLength(3));
    },
  );

  test('a Subsonic error instead of an image stores nothing', () async {
    final s = store(
      respond: (_) => http.Response(
        '{"subsonic-response":{"status":"failed"}}',
        200,
        headers: {'content-type': 'application/json'},
      ),
    );
    await s.ensureAll(['al-1']);
    expect(s.existing('al-1'), isNull);
  });

  test('a cover that fails leaves the others to come', () async {
    final s = store(
      respond: (id) => id == 'mf-1'
          ? http.Response('', 404)
          : http.Response.bytes(
              [1],
              200,
              headers: {'content-type': 'image/png'},
            ),
    );
    await s.ensureAll(['mf-1', 'mf-2']);
    expect(s.existing('mf-1'), isNull);
    expect(s.existing('mf-2'), isNotNull);
  });
}
