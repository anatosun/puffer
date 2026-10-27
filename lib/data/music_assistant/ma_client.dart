import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'ma_models.dart';

class MaException implements Exception {
  const MaException(this.code, this.message);

  final int code;
  final String message;

  @override
  String toString() => message;
}

class MaEvent {
  const MaEvent(this.event, this.objectId, this.data);

  final String event;
  final String? objectId;
  final Object? data;
}

enum MaConnectionStatus { connecting, connected, disconnected, unauthorized }

typedef ChannelFactory = WebSocketChannel Function(Uri uri);

/// Base address of a Music Assistant server, with the scheme and port the person most likely means.
Uri normaliseMaUrl(String input) {
  var text = input.trim();
  if (!text.contains('://')) text = 'http://$text';
  var uri = Uri.parse(text);
  if (!uri.hasPort && uri.scheme == 'http') uri = uri.replace(port: 8095);
  final path = uri.path.endsWith('/')
      ? uri.path.substring(0, uri.path.length - 1)
      : uri.path;
  return uri.replace(path: path, query: null, fragment: null);
}

Uri _wsUri(Uri base) => base.replace(
  scheme: base.scheme == 'https' ? 'wss' : 'ws',
  path: '${base.path}/ws',
);

/// One WebSocket session per call, used before a token exists.
Future<String> maLogin(
  Uri base, {
  required String username,
  required String password,
  String deviceName = 'Puffer',
  ChannelFactory? connect,
}) async {
  final channel = (connect ?? WebSocketChannel.connect)(_wsUri(base));
  try {
    await channel.ready;
    final messages = channel.stream.map(
      (m) => jsonDecode(m as String) as MaJson,
    );
    final iterator = StreamIterator(messages);
    if (!await iterator.moveNext()) {
      throw const MaException(0, 'The server closed the connection');
    }
    channel.sink.add(
      jsonEncode({
        'message_id': 'login',
        'command': 'auth/login',
        'args': {
          'username': username,
          'password': password,
          'device_name': deviceName,
        },
      }),
    );
    while (await iterator.moveNext()) {
      final message = iterator.current;
      if (message['message_id'] != 'login') continue;
      if (message.containsKey('error_code')) {
        throw MaException(
          message['error_code'] as int,
          message['details'] as String? ?? 'Login failed',
        );
      }
      final result = message['result'] as MaJson? ?? const {};
      final token = result['access_token'] as String?;
      if (result['success'] != true || token == null) {
        throw MaException(
          401,
          result['error'] as String? ?? 'Wrong username or password',
        );
      }
      return token;
    }
    throw const MaException(0, 'The server closed the connection');
  } finally {
    await channel.sink.close();
  }
}

/// A connection to Music Assistant that authenticates with a token, reconnects after drops, and keeps the state of players and queues current from events.
class MusicAssistantClient {
  MusicAssistantClient(this.baseUrl, this.token, {ChannelFactory? connect})
    : _connect = connect ?? WebSocketChannel.connect;

  final Uri baseUrl;
  final String token;
  final ChannelFactory _connect;

  WebSocketChannel? _channel;
  int _nextId = 0;
  final _pending = <String, Completer<Object?>>{};
  final _partial = <String, List<Object?>>{};
  bool _closed = false;
  int _attempt = 0;
  Timer? _retry;

  final _events = StreamController<MaEvent>.broadcast();
  final _statusController = StreamController<MaConnectionStatus>.broadcast();
  final _playersController =
      StreamController<Map<String, MaPlayer>>.broadcast();
  final _queuesController = StreamController<Map<String, MaQueue>>.broadcast();

  MaConnectionStatus status = MaConnectionStatus.disconnected;
  MaJson? serverInfo;
  Map<String, MaPlayer> players = const {};
  Map<String, MaQueue> queues = const {};

  Stream<MaEvent> get events => _events.stream;
  Stream<MaConnectionStatus> get statusStream => _statusController.stream;
  Stream<Map<String, MaPlayer>> get playersStream => _playersController.stream;
  Stream<Map<String, MaQueue>> get queuesStream => _queuesController.stream;

  void _setStatus(MaConnectionStatus value) {
    status = value;
    _statusController.add(value);
  }

  Future<void> connect() async {
    if (_closed) return;
    _setStatus(MaConnectionStatus.connecting);
    final channel = _connect(_wsUri(baseUrl));
    _channel = channel;
    final serverInfoReceived = Completer<void>();
    try {
      await channel.ready;
      channel.stream.listen(
        (raw) {
          final message = jsonDecode(raw as String) as MaJson;
          if (!serverInfoReceived.isCompleted &&
              message.containsKey('server_id')) {
            serverInfo = message;
            serverInfoReceived.complete();
            return;
          }
          _onMessage(message);
        },
        onDone: () => _onClosed(channel),
        onError: (Object _) => _onClosed(channel),
      );
      await serverInfoReceived.future.timeout(const Duration(seconds: 10));
      await command('auth', {'token': token, 'device_name': 'Puffer'});
      _attempt = 0;
      _setStatus(MaConnectionStatus.connected);
      await refresh();
    } on MaException catch (e) {
      if (e.code == 20 || e.code == 21 || e.code == 23) {
        _closed = true;
        _setStatus(MaConnectionStatus.unauthorized);
        await channel.sink.close();
        return;
      }
      _onClosed(channel);
    } on Object {
      _onClosed(channel);
    }
  }

  /// Reloads all players and queues.
  Future<void> refresh() async {
    final playerList = await command('players/all') as List? ?? const [];
    players = {
      for (final p in playerList)
        (p as MaJson)['player_id'] as String: MaPlayer(p),
    };
    _playersController.add(players);
    final queueList = await command('player_queues/all') as List? ?? const [];
    queues = {
      for (final q in queueList)
        (q as MaJson)['queue_id'] as String: MaQueue(q),
    };
    _queuesController.add(queues);
  }

  void _onClosed(WebSocketChannel channel) {
    if (_channel != channel) return;
    _channel = null;
    for (final c in _pending.values) {
      if (!c.isCompleted) {
        c.completeError(
          const MaException(0, 'Connection to Music Assistant lost'),
        );
      }
    }
    _pending.clear();
    _partial.clear();
    if (_closed) return;
    _setStatus(MaConnectionStatus.disconnected);
    final delay = Duration(seconds: min(30, 1 << min(_attempt++, 5)));
    _retry?.cancel();
    _retry = Timer(delay, connect);
  }

  void _onMessage(MaJson message) {
    if (message.containsKey('event')) {
      _onEvent(
        MaEvent(
          message['event'] as String,
          message['object_id'] as String?,
          message['data'],
        ),
      );
      return;
    }
    final id = message['message_id'] as String?;
    final completer = _pending[id];
    if (id == null || completer == null) return;
    if (message.containsKey('error_code')) {
      _pending.remove(id);
      _partial.remove(id);
      completer.completeError(
        MaException(
          message['error_code'] as int? ?? 0,
          message['details'] as String? ?? 'Command failed',
        ),
      );
      return;
    }
    // Long lists arrive in several messages marked partial, followed by a final one.
    if (message['partial'] == true) {
      _partial
          .putIfAbsent(id, () => [])
          .addAll((message['result'] as List?) ?? const []);
      return;
    }
    _pending.remove(id);
    final earlier = _partial.remove(id);
    final result = message['result'];
    completer.complete(
      earlier == null ? result : [...earlier, ...?(result as List?)],
    );
  }

  void _onEvent(MaEvent event) {
    final data = event.data;
    switch (event.event) {
      case 'player_added' || 'player_updated' when data is MaJson:
        players = {...players, data['player_id'] as String: MaPlayer(data)};
        _playersController.add(players);
      case 'player_removed':
        players = {...players}..remove(event.objectId);
        _playersController.add(players);
      case 'queue_added' || 'queue_updated' when data is MaJson:
        queues = {...queues, data['queue_id'] as String: MaQueue(data)};
        _queuesController.add(queues);
      case 'queue_time_updated' when event.objectId != null && data is num:
        final queue = queues[event.objectId];
        if (queue != null) {
          queues = {
            ...queues,
            queue.id: MaQueue({
              ...queue.json,
              'elapsed_time': data,
              'elapsed_time_last_updated':
                  DateTime.now().millisecondsSinceEpoch / 1000,
            }),
          };
          _queuesController.add(queues);
        }
    }
    _events.add(event);
  }

  /// Sends a command. Loading media into a queue makes Music Assistant resolve every item first, so it answers late.
  Future<Object?> command(String command, [MaJson args = const {}]) {
    final timeout = command == 'player_queues/play_media'
        ? const Duration(minutes: 2)
        : const Duration(seconds: 30);
    final channel = _channel;
    if (channel == null) {
      return Future.error(
        const MaException(0, 'Not connected to Music Assistant'),
      );
    }
    final id = '${++_nextId}';
    final completer = Completer<Object?>();
    _pending[id] = completer;
    channel.sink.add(
      jsonEncode({'message_id': id, 'command': command, 'args': args}),
    );
    return completer.future.timeout(
      timeout,
      onTimeout: () {
        _pending.remove(id);
        throw MaException(0, '$command timed out');
      },
    );
  }

  Future<List<MaProvider>> musicProviders() async {
    final list =
        await command('providers', {'provider_type': 'music'}) as List? ??
        const [];
    return [for (final p in list) MaProvider(p as MaJson)];
  }

  Future<List<MaQueueItem>> queueItems(
    String queueId, {
    int limit = 500,
    int offset = 0,
  }) async {
    final list =
        await command('player_queues/items', {
          'queue_id': queueId,
          'limit': limit,
          'offset': offset,
        }) as List? ??
        const [];
    return [for (final i in list) MaQueueItem(i as MaJson)];
  }

  Future<void> close() async {
    _closed = true;
    _retry?.cancel();
    await _channel?.sink.close();
    _channel = null;
    await _events.close();
    await _statusController.close();
    await _playersController.close();
    await _queuesController.close();
  }
}
