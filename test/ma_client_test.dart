import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:puffer/data/music_assistant/ma_client.dart';
import 'package:puffer/data/music_assistant/ma_models.dart';
import 'package:puffer/data/subsonic/models.dart';
import 'package:puffer/playback/ma_playback_controller.dart';

/// A Music Assistant server that answers the commands the client sends and records them.
class FakeServer {
  late HttpServer _server;
  WebSocket? socket;
  final commands = <Map<String, dynamic>>[];
  String validToken = 'secret';

  /// The answer to `player_queues/items`, when a test sets one.
  List<Map<String, Object?>>? queueItems;

  Uri get base => Uri.parse('http://127.0.0.1:${_server.port}');

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen((request) async {
      final ws = await WebSocketTransformer.upgrade(request);
      socket = ws;
      ws.add(
        jsonEncode({
          'server_id': 'x',
          'server_version': '2.9.0',
          'schema_version': 30,
          'min_supported_schema_version': 28,
        }),
      );
      ws.listen((raw) {
        final msg = jsonDecode(raw as String) as Map<String, dynamic>;
        commands.add(msg);
        if (msg['command'] == 'player_queues/items' && queueItems != null) {
          ws.add(
            jsonEncode({'message_id': msg['message_id'], 'result': queueItems}),
          );
          return;
        }
        if (msg['command'] == 'player_queues/items') {
          // Long lists arrive in parts.
          ws.add(
            jsonEncode({
              'message_id': msg['message_id'],
              'result': [
                {'queue_item_id': 'a'},
              ],
              'partial': true,
            }),
          );
          ws.add(
            jsonEncode({
              'message_id': msg['message_id'],
              'result': [
                {'queue_item_id': 'b'},
              ],
            }),
          );
          return;
        }
        ws.add(jsonEncode(_answer(msg)));
      });
    });
  }

  Map<String, dynamic> _answer(Map<String, dynamic> msg) {
    final id = msg['message_id'];
    final args = msg['args'] as Map<String, dynamic>? ?? const {};
    switch (msg['command']) {
      case 'auth':
        return args['token'] == validToken
            ? {
                'message_id': id,
                'result': {'authenticated': true},
              }
            : {
                'message_id': id,
                'error_code': 23,
                'details': 'Invalid or expired token',
              };
      case 'auth/login':
        return {
          'message_id': id,
          'result': {
            'success': args['password'] == 'pw',
            'access_token': 'secret',
          },
        };
      case 'players/all':
        return {
          'message_id': id,
          'result': [
            {
              'player_id': 'kitchen',
              'name': 'Kitchen',
              'available': true,
              'playback_state': 'idle',
              'volume_level': 30,
            },
          ],
        };
      case 'player_queues/all':
        return {
          'message_id': id,
          'result': [
            {
              'queue_id': 'kitchen',
              'active': false,
              'state': 'idle',
              'items': 0,
            },
          ],
        };
      default:
        return {'message_id': id, 'result': null};
    }
  }

  void send(Map<String, dynamic> message) => socket!.add(jsonEncode(message));

  Future<void> stop() => _server.close(force: true);
}

void main() {
  late FakeServer server;

  setUp(() async {
    server = FakeServer();
    await server.start();
  });

  tearDown(() => server.stop());

  Future<MusicAssistantClient> connected() async {
    final client = MusicAssistantClient(server.base, 'secret');
    await client.connect();
    return client;
  }

  test('normalises addresses to http with port 8095', () {
    expect(normaliseMaUrl('ma.local').toString(), 'http://ma.local:8095');
    expect(
      normaliseMaUrl('https://ma.example.com/').toString(),
      'https://ma.example.com',
    );
  });

  test('logs in and returns the access token', () async {
    expect(
      await maLogin(server.base, username: 'me', password: 'pw'),
      'secret',
    );
    await expectLater(
      maLogin(server.base, username: 'me', password: 'wrong'),
      throwsA(isA<MaException>()),
    );
  });

  test('authenticates and loads players and queues', () async {
    final client = await connected();
    expect(client.status, MaConnectionStatus.connected);
    expect(client.players['kitchen']!.name, 'Kitchen');
    expect(client.queues['kitchen']!.state, MaPlaybackState.idle);
    await client.close();
  });

  test('an invalid token stops reconnecting', () async {
    server.validToken = 'other';
    final client = await connected();
    expect(client.status, MaConnectionStatus.unauthorized);
    await client.close();
  });

  test('events update players and queues', () async {
    final client = await connected();
    final update = client.playersStream.first;
    server.send({
      'event': 'player_updated',
      'object_id': 'kitchen',
      'data': {
        'player_id': 'kitchen',
        'name': 'Kitchen',
        'available': true,
        'playback_state': 'playing',
        'volume_level': 50,
      },
    });
    expect((await update)['kitchen']!.volume, 50);
    await client.close();
  });

  test('joins partial results', () async {
    final client = await connected();
    final items = await client.queueItems('kitchen');
    expect(items.map((i) => i.id), ['a', 'b']);
    await client.close();
  });

  test('the controller sends tracks as provider URIs or stream URLs', () async {
    final client = await connected();
    final tracks = [
      Track({'id': 't1', 'title': 'One'}),
      Track({'id': 't2', 'title': 'Two'}),
    ];

    final withProvider = MusicAssistantPlaybackController(
      client,
      'kitchen',
      providerInstance: 'opensubsonic--abc',
      streamUri: (t) => Uri.parse('http://subsonic/rest/stream?id=${t.id}'),
    );
    await withProvider.playTracks(tracks, index: 1);
    final play = server.commands.lastWhere(
      (c) => c['command'] == 'player_queues/play_media',
    );
    expect(play['args'], {
      'queue_id': 'kitchen',
      'media': ['opensubsonic--abc://track/t1', 'opensubsonic--abc://track/t2'],
      'option': 'replace',
      'start_item': 'opensubsonic--abc://track/t2',
      'shuffle': false,
    });

    final withUrls = MusicAssistantPlaybackController(
      client,
      'kitchen',
      streamUri: (t) => Uri.parse('http://subsonic/rest/stream?id=${t.id}'),
    );
    await withUrls.addTracks(tracks.take(1).toList());
    final add = server.commands.lastWhere(
      (c) => c['command'] == 'player_queues/play_media',
    );
    expect((add['args'] as Map)['media'], [
      'http://subsonic/rest/stream?id=t1',
    ]);
    expect((add['args'] as Map)['option'], 'add');

    withProvider.dispose();
    withUrls.dispose();
    await client.close();
  });

  test('a queue item keeps its track when an update leaves out its provider mappings', () async {
    final client = await connected();
    final controller = MusicAssistantPlaybackController(
      client,
      'kitchen',
      providerInstance: 'opensubsonic--abc',
      streamUri: (t) => Uri.parse('http://subsonic/${t.id}'),
    );
    // Three tracks sent against the two items the fake server lists, so the queue order cannot stand in for the mappings.
    await controller.playTracks([
      Track({'id': 't1', 'title': 'One'}),
      Track({'id': 't2', 'title': 'Two'}),
      Track({'id': 't3', 'title': 'Three'}),
    ]);
    Map<String, dynamic> update(Map<String, dynamic> media) => {
      'event': 'queue_updated',
      'object_id': 'kitchen',
      'data': {
        'queue_id': 'kitchen',
        'state': 'playing',
        'items': 2,
        'current_index': 0,
        'current_item': {
          'queue_item_id': 'q1',
          'name': 'One',
          'media_item': media,
        },
      },
    };
    final mapped = controller.state.firstWhere((np) => np?.track != null);
    server.send(
      update({
        'name': 'One',
        'provider_mappings': [
          {'item_id': 't1', 'provider_instance': 'opensubsonic--abc'},
        ],
      }),
    );
    expect((await mapped)!.track?.id, 't1');

    // As after a seek: the same item, described without its mappings.
    final after = controller.state.skip(1).first;
    server.send(update({'name': 'One'}));
    expect((await after)!.track?.id, 't1');
    controller.dispose();
    await client.close();
  });

  test('now playing maps the queue item back to the Subsonic track', () async {
    final client = await connected();
    final controller = MusicAssistantPlaybackController(
      client,
      'kitchen',
      providerInstance: 'opensubsonic--abc',
      streamUri: (t) => Uri.parse('http://subsonic/${t.id}'),
    );
    await controller.playTracks([
      Track({'id': 't1', 'title': 'One', 'coverArt': 'al-1'}),
    ]);
    final next = controller.state.firstWhere((np) => np != null);
    server.send({
      'event': 'queue_updated',
      'object_id': 'kitchen',
      'data': {
        'queue_id': 'kitchen',
        'active': true,
        'state': 'playing',
        'items': 1,
        'current_index': 0,
        'elapsed_time': 12,
        'current_item': {
          'queue_id': 'kitchen',
          'queue_item_id': 'q1',
          'name': 'One',
          'duration': 200,
          'media_item': {
            'name': 'One',
            'provider_mappings': [
              {'item_id': 't1', 'provider_instance': 'opensubsonic--abc'},
            ],
          },
        },
      },
    });
    final np = (await next)!;
    expect(np.track?.id, 't1');
    expect(np.coverArt, 'al-1');
    expect(np.playing, isTrue);
    expect(np.outputName, 'Kitchen');
    controller.dispose();
    await client.close();
  });

  test('a paused queue that reports idle still shows', () async {
    final client = await connected();
    final controller = MusicAssistantPlaybackController(
      client,
      'kitchen',
      streamUri: (t) => Uri.parse('http://subsonic/${t.id}'),
    );
    final shown = controller.state.firstWhere((np) => np != null);
    server.send({
      'event': 'queue_updated',
      'object_id': 'kitchen',
      'data': {
        'queue_id': 'kitchen',
        'active': true,
        'state': 'idle',
        'items': 1,
        'current_index': 0,
        'elapsed_time': 42,
        'current_item': {
          'queue_id': 'kitchen',
          'queue_item_id': 'q1',
          'name': 'One',
          'media_item': {'name': 'One'},
        },
      },
    });
    final np = (await shown)!;
    expect(np.title, 'One');
    expect(np.playing, isFalse);
    expect(np.position, const Duration(seconds: 42));
    controller.dispose();
    await client.close();
  });

  test(
    'a controller replaced before its queue items arrive stays quiet',
    () async {
      final client = await connected();
      MusicAssistantPlaybackController(
        client,
        'kitchen',
        streamUri: (t) => Uri.parse('http://subsonic/${t.id}'),
      ).dispose();
      // The items the controller asked for at its start arrive after it closed.
      await pumpEventQueue();
      await client.close();
    },
  );

  test('now playing looks up a track queued by another client', () async {
    final client = await connected();
    final controller = MusicAssistantPlaybackController(
      client,
      'kitchen',
      streamUri: (t) => Uri.parse('http://subsonic/${t.id}'),
      lookupTrack: (id) async => Track({'id': id, 'title': 'Looked up'}),
    );
    final resolved = controller.state.firstWhere((np) => np?.track?.id == 't9');
    server.send({
      'event': 'queue_updated',
      'object_id': 'kitchen',
      'data': {
        'queue_id': 'kitchen',
        'active': true,
        'state': 'playing',
        'items': 1,
        'current_index': 0,
        'current_item': {
          'queue_id': 'kitchen',
          'queue_item_id': 'q1',
          'name': 'Nine',
          'media_item': {
            'name': 'Nine',
            'uri': 'http://navidrome/rest/stream?u=me&id=t9&v=1.16.1',
          },
        },
      },
    });
    expect((await resolved)!.title, 'Looked up');
    controller.dispose();
    await client.close();
  });

  test(
    'the queue shows the Subsonic tracks of items another client queued',
    () async {
      final client = await connected();
      Map<String, Object?> item(String id, String name) => {
        'queue_item_id': 'q-$id',
        'name': name,
        'media_item': {
          'name': name,
          'uri': 'http://navidrome/rest/stream?u=me&id=$id&v=1.16.1',
        },
      };
      server.queueItems = [item('t1', 'One'), item('t2', 'Two')];
      final looked = <String>[];
      final controller = MusicAssistantPlaybackController(
        client,
        'kitchen',
        streamUri: (t) => Uri.parse('http://subsonic/${t.id}'),
        lookupTrack: (id) async {
          looked.add(id);
          return Track({'id': id, 'title': 'Looked up $id'});
        },
      );
      final resolved = controller.state.firstWhere(
        (np) => np?.queue.length == 2 && np!.queue[1].title == 'Looked up t2',
      );
      server.send({
        'event': 'queue_updated',
        'object_id': 'kitchen',
        'data': {
          'queue_id': 'kitchen',
          'active': true,
          'state': 'playing',
          'items': 2,
          'current_index': 0,
          'current_item': item('t1', 'One'),
        },
      });
      final np = (await resolved)!;
      expect(np.title, 'Looked up t1');
      expect(
        [for (final e in np.queue) e.title],
        ['Looked up t1', 'Looked up t2'],
      );
      expect(looked, ['t1', 't2']);
      controller.dispose();
      await client.close();
    },
  );

  test(
    'the controller groups players, transfers the queue and stops',
    () async {
      final client = await connected();
      final controller = MusicAssistantPlaybackController(
        client,
        'kitchen',
        streamUri: (t) => Uri.parse('http://subsonic/${t.id}'),
      );
      await controller.setMembers(add: ['living']);
      await controller.transferTo('living');
      await controller.stop();
      final sent = server.commands
          .skip(3)
          .where((c) => c['command'] != 'player_queues/items')
          .map((c) => [c['command'], c['args']])
          .toList();
      expect(sent, [
        [
          'players/cmd/set_members',
          {
            'target_player': 'kitchen',
            'player_ids_to_add': ['living'],
          },
        ],
        [
          'player_queues/transfer',
          {'source_queue_id': 'kitchen', 'target_queue_id': 'living'},
        ],
        [
          'player_queues/stop',
          {'queue_id': 'kitchen'},
        ],
        [
          'player_queues/clear',
          {'queue_id': 'kitchen'},
        ],
      ]);
      controller.dispose();
      await client.close();
    },
  );

  test('a snapshot maps the queue items to Subsonic tracks', () async {
    final client = await connected();
    final controller = MusicAssistantPlaybackController(
      client,
      'kitchen',
      providerInstance: 'opensubsonic--abc',
      streamUri: (t) => Uri.parse('http://subsonic/${t.id}'),
      lookupTrack: (id) async => Track({'id': id, 'title': 'Looked up $id'}),
    );
    await pumpEventQueue();
    server.send({
      'event': 'queue_updated',
      'object_id': 'kitchen',
      'data': {
        'queue_id': 'kitchen',
        'active': true,
        'state': 'playing',
        'items': 2,
        'current_index': 1,
        'elapsed_time': 30,
      },
    });
    // The fake answers player_queues/items with items a and b, which have no provider mappings.
    await pumpEventQueue();
    expect(await controller.snapshot(), isNull);
    controller.dispose();
    await client.close();
  });

  test('images go through the proxy id, or the path when reachable', () {
    final base = Uri.parse('http://ma:8095');
    expect(
      const MaImage({'path': 'al-1', 'provider': 'x', 'proxy_id': 'abc'})
          .url(base)
          .toString(),
      'http://ma:8095/imageproxy/abc?size=512',
    );
    expect(
      const MaImage({'path': 'https://img/x.jpg', 'remotely_accessible': true})
          .url(base)
          .toString(),
      'https://img/x.jpg',
    );
    expect(const MaImage({'path': 'al-1', 'provider': 'x'}).url(base), isNull);
  });

  test(
    'a queue item from the Subsonic provider shows the Subsonic cover',
    () async {
      final client = await connected();
      final controller = MusicAssistantPlaybackController(
        client,
        'kitchen',
        providerInstance: 'opensubsonic--abc',
        streamUri: (t) => Uri.parse('http://subsonic/${t.id}'),
      );
      final next = controller.state.firstWhere((np) => np != null);
      server.send({
        'event': 'queue_updated',
        'object_id': 'kitchen',
        'data': {
          'queue_id': 'kitchen',
          'active': true,
          'state': 'paused',
          'items': 1,
          'current_index': 0,
          'current_item': {
            'queue_id': 'kitchen',
            'queue_item_id': 'q1',
            'name': 'Song added elsewhere',
            'image': {
              'path': 'al-9',
              'provider': 'opensubsonic--abc',
              'proxy_id': 'p9',
            },
          },
        },
      });
      final np = (await next)!;
      expect(np.coverArt, 'al-9');
      expect(np.title, 'Song added elsewhere');
      controller.dispose();
      await client.close();
    },
  );
}
