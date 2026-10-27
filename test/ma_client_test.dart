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
}
