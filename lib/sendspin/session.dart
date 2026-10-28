import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'noise.dart';
import 'time_filter.dart';

/// Microseconds of a monotonic clock, the local time of every Sendspin timestamp.
final _clock = Stopwatch()..start();
int monotonicMicros() => _clock.elapsedMicroseconds;

class AudioFormat {
  const AudioFormat({
    required this.codec,
    required this.sampleRate,
    required this.channels,
    required this.bitDepth,
  });

  factory AudioFormat.fromJson(Map<String, dynamic> json) => AudioFormat(
    codec: json['codec'] as String,
    sampleRate: json['sample_rate'] as int,
    channels: json['channels'] as int,
    bitDepth: json['bit_depth'] as int? ?? 16,
  );

  final String codec;
  final int sampleRate;
  final int channels;
  final int bitDepth;

  Map<String, dynamic> toJson() => {
    'codec': codec,
    'channels': channels,
    'sample_rate': sampleRate,
    'bit_depth': bitDepth,
  };

  int get bytesPerFrame => channels * bitDepth ~/ 8;
}

/// Where the audio of a Sendspin stream goes. Timestamps are local monotonic microseconds at which the first frame of a chunk must leave the device.
abstract class SendspinAudioOutput {
  void start(AudioFormat format);
  void chunk(int localTimestamp, Uint8List pcm);
  void clear();
  void stop();
  void setVolume(int volume, {required bool muted});

  /// Delay in milliseconds between handing a frame to the output and hearing it, reported as part of the lead time.
  int get latencyMs;
}

/// Group and playback information the server sends, for display.
class SendspinStatus {
  const SendspinStatus({
    this.serverName,
    this.groupName,
    this.playing = false,
    this.title,
    this.artist,
    this.album,
    this.connected = false,
  });

  final bool connected;
  final String? serverName;
  final String? groupName;
  final bool playing;
  final String? title;
  final String? artist;
  final String? album;

  SendspinStatus copyWith({
    bool? connected,
    String? serverName,
    String? groupName,
    bool? playing,
    String? title,
    String? artist,
    String? album,
  }) => SendspinStatus(
    connected: connected ?? this.connected,
    serverName: serverName ?? this.serverName,
    groupName: groupName ?? this.groupName,
    playing: playing ?? this.playing,
    title: title ?? this.title,
    artist: artist ?? this.artist,
    album: album ?? this.album,
  );
}

class SendspinConfig {
  const SendspinConfig({
    required this.identity,
    required this.name,
    this.softwareVersion = '',
    this.unpairedAccess = true,
  });

  final StaticKey identity;
  final String name;
  final String softwareVersion;

  /// Lets a server play without pairing once its operator approves this device.
  final bool unpairedAccess;
}

class SendspinProtocolException implements Exception {
  const SendspinProtocolException(this.message);

  final String message;

  @override
  String toString() => 'SendspinProtocolException: $message';
}

/// One connection from a Sendspin server to this player: the cleartext init exchange, the Noise handshake, then encrypted messages (spec: connection.md and messaging.md).
class SendspinSession {
  SendspinSession(
    this._socket,
    this.config,
    this.output, {
    this.onStatus,
    this.onActivated,
  });

  final WebSocket _socket;
  final SendspinConfig config;
  final SendspinAudioOutput output;
  final void Function(SendspinStatus status)? onStatus;

  /// Called with the activities of each `server/activate`, so the listener can admit one connection at a time.
  final void Function(SendspinSession session, List<String> activities)?
  onActivated;

  static const supportedFormats = [
    AudioFormat(codec: 'pcm', sampleRate: 48000, channels: 2, bitDepth: 16),
    AudioFormat(codec: 'pcm', sampleRate: 44100, channels: 2, bitDepth: 16),
  ];

  /// Two seconds of 48 kHz stereo PCM, with headroom for the chunk headers.
  static const bufferCapacity = 48000 * 4 * 2 + 64 * 1024;

  final filter = TimeFilter();
  SendspinStatus status = const SendspinStatus();
  String? serverId;
  List<String> activities = const [];
  List<String> activeRoles = const [];

  NoiseTransport? _transport;
  final _pending = <Object>[];
  Completer<void>? _wake;
  Completer<(int, int, int, int)>? _timeReply;
  int volume = 100;
  bool muted = false;
  bool _available = false;
  bool _closed = false;
  AudioFormat? _format;
  Timer? _syncTimer;

  // Reassembly of fragmented messages (spec: messaging.md, "Fragmentation").
  BytesBuilder? _fragments;
  int? _fragmentType;

  bool get playerActive => activeRoles.contains('player@v1');

  /// Runs the session until the socket closes.
  Future<void> run() async {
    final incoming = _socket.listen(
      (m) {
        _pending.add(m is String ? m : Uint8List.fromList(m as List<int>));
        final arrival = monotonicMicros();
        _arrivals.add(arrival);
        _wake?.complete();
        _wake = null;
      },
      onDone: () => _wakeClosed(),
      onError: (Object _) => _wakeClosed(),
    );
    try {
      await _handshake();
      await _loop();
    } on Object {
      // Any protocol or decryption failure closes the connection silently (spec: "Failure Handling").
    } finally {
      await incoming.cancel();
      await close();
    }
  }

  final _arrivals = <int>[];

  void _wakeClosed() {
    _closed = true;
    _wake?.complete();
    _wake = null;
  }

  /// The next WebSocket message with its arrival time.
  Future<(Object, int)> _next({
    Duration timeout = const Duration(seconds: 30),
  }) async {
    while (_pending.isEmpty) {
      if (_closed) throw const SendspinProtocolException('connection closed');
      _wake = Completer<void>();
      await _wake!.future.timeout(timeout);
    }
    return (_pending.removeAt(0), _arrivals.removeAt(0));
  }

  Future<void> _handshake() async {
    final init = jsonEncode({
      'type': 'client/init',
      'payload': {
        'client_id': config.identity.id,
        'version': 1,
        'suite': suiteName,
      },
    });
    _socket.add(init);

    final (serverInit, _) = await _next();
    if (serverInit is! String) {
      throw const SendspinProtocolException('server/init must be text');
    }
    final parsedInit = jsonDecode(serverInit) as Map<String, dynamic>;
    if (parsedInit['type'] != 'server/init') {
      throw SendspinProtocolException(
        'expected server/init, got ${parsedInit['type']}',
      );
    }
    final initPayload = parsedInit['payload'] as Map<String, dynamic>;
    if (initPayload['version'] != 1) {
      throw const SendspinProtocolException('unsupported version');
    }
    serverId = initPayload['server_id'] as String;

    final responder = await NoiseResponder.start(
      local: config.identity,
      remoteStatic: base64UrlDecodeNoPad(serverId!),
      // The prologue is the exact bytes of both init messages as sent.
      prologue: [...utf8.encode(init), ...utf8.encode(serverInit)],
    );

    final (handshake1, _) = await _next();
    if (handshake1 is! String) {
      throw const SendspinProtocolException('noise/handshake must be text');
    }
    final message1 = jsonDecode(handshake1) as Map<String, dynamic>;
    if (message1['type'] != 'noise/handshake') {
      throw const SendspinProtocolException('expected noise/handshake');
    }
    final payload1 = jsonDecode(
      utf8.decode(
        await responder.readMessage1(
          base64UrlDecodeNoPad((message1['payload'] as Map)['data'] as String),
        ),
      ),
    );
    final category = (payload1 as Map<String, dynamic>)['psk_category'];
    if (category != 'lt' && category != 'pr' && category != 'sn') {
      throw const SendspinProtocolException('unknown psk category');
    }

    // Without pairing records, every lookup misses and falls back to the Sentinel PSK (spec: "Sentinel Fallback").
    final (message2, transport) = await responder.writeMessage2(
      await sentinelPsk(),
      utf8.encode('{}'),
    );
    _socket.add(
      jsonEncode({
        'type': 'noise/handshake',
        'payload': {'data': base64UrlNoPad(message2)},
      }),
    );
    _transport = transport;
  }

  Future<void> send(String type, Map<String, dynamic> payload) => _sendBinary([
    0,
    ...utf8.encode(jsonEncode({'type': type, 'payload': payload})),
  ]);

  Future<void> _sendBinary(List<int> plaintext) async {
    final transport = _transport;
    if (transport == null || _closed) return;
    _socket.add(await transport.send.encrypt(plaintext));
  }

  Future<void> _loop() async {
    while (!_closed) {
      final (message, arrival) = await _next(
        timeout: const Duration(days: 365),
      );
      // A cleartext message after the handshake is a silent failure.
      if (message is String) {
        throw const SendspinProtocolException('cleartext after handshake');
      }
      final plain = await _transport!.receive.decrypt(message as Uint8List);
      if (plain.isEmpty) throw const SendspinProtocolException('empty message');
      final type = plain[0];
      if (type == 1) {
        _onFragment(plain, arrival);
        continue;
      }
      if (_fragments != null) {
        throw const SendspinProtocolException(
          'message inside a fragmented message',
        );
      }
      await _dispatch(type, Uint8List.sublistView(plain, 1), arrival);
    }
  }

  void _onFragment(Uint8List plain, int arrival) {
    if (plain.length < 2) {
      throw const SendspinProtocolException('fragment without flags');
    }
    final flags = plain[1];
    if (flags & 0xFC != 0) {
      throw const SendspinProtocolException('reserved fragment flags');
    }
    final first = flags & 0x02 != 0, last = flags & 0x01 != 0;
    if (first) {
      if (_fragments != null || plain.length < 3) {
        throw const SendspinProtocolException('bad first fragment');
      }
      if (plain[2] == 1) {
        throw const SendspinProtocolException('fragment of a fragment');
      }
      _fragmentType = plain[2];
      _fragments = BytesBuilder()..add(Uint8List.sublistView(plain, 3));
    } else {
      if (_fragments == null) {
        throw const SendspinProtocolException('fragment without a first one');
      }
      _fragments!.add(Uint8List.sublistView(plain, 2));
    }
    if (last) {
      final body = _fragments!.takeBytes();
      final type = _fragmentType!;
      _fragments = null;
      _fragmentType = null;
      unawaited(_dispatch(type, body, arrival));
    }
  }

  Future<void> _dispatch(int type, Uint8List body, int arrival) async {
    switch (type) {
      case 0:
        final json = jsonDecode(utf8.decode(body));
        if (json is! Map<String, dynamic> ||
            json['type'] is! String ||
            json['payload'] is! Map) {
          throw const SendspinProtocolException('malformed JSON message');
        }
        await _onJson(
          json['type'] as String,
          (json['payload'] as Map).cast<String, dynamic>(),
          arrival,
        );
      case 4:
        _onAudio(body);
    }
  }

  Future<void> _onJson(
    String type,
    Map<String, dynamic> payload,
    int arrival,
  ) async {
    switch (type) {
      case 'server/hello':
        status = status.copyWith(
          connected: true,
          serverName: payload['name'] as String?,
        );
        onStatus?.call(status);
        await send('client/hello', {
          'name': config.name,
          'device_info': {
            'product_name': 'Puffer',
            'manufacturer': 'Puffer',
            'software_version': config.softwareVersion,
          },
          'supported_roles': ['player@v1', 'metadata@v1'],
          'player@v1_support': {
            'supported_formats': [for (final f in supportedFormats) f.toJson()],
            'buffer_capacity': bufferCapacity,
          },
          'supported_pair_methods': {
            'pairing_psk': {
              'locations': ['operator'],
            },
          },
          'unpaired_access': {'enabled': config.unpairedAccess},
        });
      case 'server/activate':
        await _onActivate(payload);
      case 'server/time':
        _timeReply?.complete((
          payload['client_transmitted'] as int,
          payload['server_received'] as int,
          payload['server_transmitted'] as int,
          arrival,
        ));
        _timeReply = null;
      case 'stream/start':
        final player = payload['player'] as Map<String, dynamic>?;
        if (player != null && playerActive) {
          _format = AudioFormat.fromJson(player);
          output.start(_format!);
        }
      case 'stream/clear':
        final roles = (payload['roles'] as List?)?.cast<String>();
        if (roles == null || roles.contains('player')) output.clear();
      case 'stream/end':
        final roles = (payload['roles'] as List?)?.cast<String>();
        if (roles == null || roles.contains('player')) {
          _format = null;
          output.stop();
        }
      case 'server/command':
        await _onCommand(payload['player'] as Map<String, dynamic>?);
      case 'group/update':
        status = status.copyWith(
          groupName: payload['group_name'] as String?,
          playing: payload['playback_state'] == 'playing',
        );
        onStatus?.call(status);
      case 'server/state':
        final metadata = payload['metadata'] as Map<String, dynamic>?;
        if (metadata != null) {
          status = SendspinStatus(
            connected: true,
            serverName: status.serverName,
            groupName: status.groupName,
            playing: status.playing,
            title: metadata['title'] as String?,
            artist: metadata['artist'] as String?,
            album: metadata['album'] as String?,
          );
          onStatus?.call(status);
        }
      case 'server/unpair':
        // Unpaired sessions ignore it.
        break;
    }
  }

  Future<void> _onActivate(Map<String, dynamic> payload) async {
    final requested =
        (payload['activities'] as List?)?.cast<String>() ?? const [];
    final roles = (payload['active_roles'] as List?)?.cast<String>();
    // A Sentinel-keyed (unpaired) session admits playback only with unpaired access.
    final wantsPlayback =
        requested.contains('playback') || (roles != null && roles.isNotEmpty);
    if (wantsPlayback && !config.unpairedAccess) {
      await goodbye('pairing_required');
      return;
    }
    if (requested.contains('pairing')) {
      // Pairing flows are not implemented yet.
      await send('pair/abort', {'reason': 'method_not_supported'});
    }
    final hadPlayer = playerActive;
    activities = requested;
    if (roles != null) activeRoles = roles;
    onActivated?.call(this, activities);
    if (hadPlayer && !playerActive) output.stop();
    if (activeRoles.isNotEmpty) {
      await _sendState();
      _startClockSync();
    }
  }

  Future<void> _onCommand(Map<String, dynamic>? player) async {
    if (player == null || !playerActive) return;
    switch (player['command']) {
      case 'volume':
        volume = (player['volume'] as int).clamp(0, 100);
      case 'mute':
        muted = player['mute'] as bool;
      default:
        return;
    }
    output.setVolume(volume, muted: muted);
    await _sendState();
  }

  Future<void> _sendState() => send('client/state', {
    'available': _available,
    if (playerActive)
      'player': {
        'volume': volume,
        'muted': muted,
        'output_delay_ms': 0,
        'required_lead_time_ms': 250 + output.latencyMs,
        'min_buffer_ms': 150,
        'supported_commands': ['volume', 'mute'],
      },
  });

  /// Bursts of eight `client/time` exchanges, each sent after the previous reply, feeding the filter the exchange with the smallest error. Bursts start every two seconds until the filter converges, then every eight.
  void _startClockSync() {
    if (_syncTimer != null) return;
    Future<void> burst() async {
      (int, int, int, int)? best;
      for (var i = 0; i < 8 && !_closed; i++) {
        _timeReply = Completer();
        final t1 = monotonicMicros();
        await send('client/time', {'client_transmitted': t1});
        try {
          final reply = await _timeReply!.future.timeout(
            const Duration(seconds: 2),
          );
          if (reply.$1 != t1) continue;
          final error = TimeFilter.maxErrorOf(
            reply.$1,
            reply.$2,
            reply.$3,
            reply.$4,
          );
          if (best == null ||
              error <
                  TimeFilter.maxErrorOf(best.$1, best.$2, best.$3, best.$4)) {
            best = reply;
          }
        } on TimeoutException {
          _timeReply = null;
        }
      }
      if (best != null) filter.addExchange(best.$1, best.$2, best.$3, best.$4);
      if (!_available && filter.converged) {
        _available = true;
        await _sendState();
      }
      if (_closed) return;
      _syncTimer = Timer(
        Duration(seconds: _available ? 8 : 2),
        () => unawaited(burst()),
      );
    }

    _syncTimer = Timer(Duration.zero, () => unawaited(burst()));
  }

  void _onAudio(Uint8List body) {
    // Byte 0 (the type) is already removed: 8 bytes of timestamp, 4 of send-ahead, then audio.
    if (body.length < 12) {
      throw const SendspinProtocolException(
        'audio chunk shorter than its header',
      );
    }
    if (!playerActive || _format == null || !_available) return;
    final view = ByteData.sublistView(body);
    final serverTimestamp = view.getInt64(0, Endian.big);
    output.chunk(
      filter.clientTime(serverTimestamp),
      Uint8List.sublistView(body, 12),
    );
  }

  Future<void> goodbye(String reason) async {
    await send('client/goodbye', {'reason': reason});
    await close();
  }

  Future<void> close() async {
    if (_closed && _transport == null) return;
    _closed = true;
    _syncTimer?.cancel();
    _transport = null;
    if (playerActive) output.stop();
    status = const SendspinStatus();
    onStatus?.call(status);
    await _socket.close();
  }
}
