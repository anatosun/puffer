import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:puffer/data/subsonic/subsonic_client.dart';
import 'package:puffer/playback/scrobble_queue.dart';

void main() {
  late Directory dir;
  late File file;
  late List<List<String>> sent;
  late Object? failure;
  late Set<String> refused;

  ScrobbleQueue queue({int limit = 5000}) => ScrobbleQueue(
    file,
    limit: limit,
    send: (plays) async {
      if (failure case final f?) throw f;
      if (plays.any((p) => refused.contains(p.trackId))) {
        throw const SubsonicException(70, 'not found');
      }
      sent.add([for (final p in plays) p.trackId]);
    },
  );

  Play play(String id) => Play(id, DateTime.utc(2026, 11, 20, 12));

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('scrobble_test');
    file = File('${dir.path}/scrobbles.json');
    sent = [];
    failure = null;
    refused = {};
  });

  tearDown(() => dir.delete(recursive: true));

  test('plays kept offline survive a restart and keep their time', () async {
    await queue().add(Play('a', DateTime.utc(2026, 11, 20, 9, 30)));
    final pending = await queue().pending();
    expect(pending.single.trackId, 'a');
    expect(
      pending.single.at.isAtSameMomentAs(DateTime.utc(2026, 11, 20, 9, 30)),
      isTrue,
    );
  });

  test(
    'flushing sends the plays kept, oldest first, and forgets them',
    () async {
      final q = queue();
      await q.add(play('a'));
      await q.add(play('b'));
      await q.flush();
      expect(sent, [
        ['a', 'b'],
      ]);
      expect(await q.pending(), isEmpty);
      expect(file.existsSync(), isFalse);
    },
  );

  test('flushing sends many plays in batches', () async {
    final q = queue();
    for (var i = 0; i < ScrobbleQueue.batch + 3; i++) {
      await q.add(play('$i'));
    }
    await q.flush();
    expect(sent.map((b) => b.length), [ScrobbleQueue.batch, 3]);
  });

  test('a play the server cannot be reached for waits', () async {
    final q = queue();
    failure = const SocketException('unreachable');
    await q.report(play('a'));
    expect((await q.pending()).single.trackId, 'a');

    failure = null;
    await q.report(play('b'));
    expect(sent, [
      ['b'],
      ['a'],
    ]);
    expect(await q.pending(), isEmpty);
  });

  test('a flush that cannot reach the server keeps every play', () async {
    final q = queue();
    await q.add(play('a'));
    failure = const SocketException('unreachable');
    await q.flush();
    expect((await q.pending()).map((p) => p.trackId), ['a']);
  });

  test('a play the server refuses is dropped, the others are sent', () async {
    final q = queue();
    await q.add(play('a'));
    await q.add(play('gone'));
    await q.add(play('c'));
    refused = {'gone'};
    await q.flush();
    expect(sent, [
      ['a'],
      ['c'],
    ]);
    expect(await q.pending(), isEmpty);
  });

  test('a refused play reported live is not kept', () async {
    final q = queue();
    refused = {'gone'};
    await q.report(play('gone'));
    expect(await q.pending(), isEmpty);
  });

  test('the oldest plays go beyond the limit', () async {
    final q = queue(limit: 3);
    for (var i = 0; i < 5; i++) {
      await q.add(play('$i'));
    }
    final pending = await q.pending();
    expect(pending.length, 3);
    expect(pending.first.trackId, '2');
  });

  test(
    'the client sends several plays in one request with their times',
    () async {
      late Uri request;
      final client = SubsonicClient(
        const ServerCredentials(
          baseUrl: 'http://navidrome',
          username: 'u',
          token: 't',
          salt: 's',
        ),
        httpClient: MockClient((r) async {
          request = r.url;
          return http.Response(
            '{"subsonic-response":{"status":"ok","version":"1.16.1"}}',
            200,
          );
        }),
      );
      await client.scrobblePlays([
        ('a', DateTime.fromMillisecondsSinceEpoch(1000)),
        ('b', DateTime.fromMillisecondsSinceEpoch(2000)),
      ]);
      expect(request.pathSegments.last, 'scrobble');
      expect(request.queryParametersAll['id'], ['a', 'b']);
      expect(request.queryParametersAll['time'], ['1000', '2000']);
      expect(request.queryParameters['submission'], 'true');
    },
  );
}
