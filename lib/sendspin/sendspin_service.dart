import 'dart:async';
import 'dart:convert';

import 'package:bonsoir/bonsoir.dart';
import 'package:pcm_player/pcm_player.dart';

import 'listener.dart';
import 'noise.dart';
import 'pcm_output.dart';
import 'session.dart';

/// [PcmDevice] on the native output of the pcm_player plugin.
class NativePcmDevice implements PcmDevice {
  final _player = PcmPlayer.instance;

  @override
  bool open({
    required int sampleRate,
    required int channels,
    required int capacityFrames,
  }) => _player.open(
    sampleRate: sampleRate,
    channels: channels,
    capacityFrames: capacityFrames,
  );
  @override
  void close() => _player.close();
  @override
  int write(samples) => _player.write(samples);
  @override
  int get writePosition => _player.writePosition;
  @override
  int get readPosition => _player.readPosition;
  @override
  int get latencyFrames => _player.latencyFrames;
  @override
  int get nowNs => _player.nowNs;
  @override
  void clear() => _player.clear();
  @override
  set volume(double amplitude) => _player.volume = amplitude;
  @override
  (int, int)? lastCallback() => _player.lastCallback();
}

/// The phone as a Sendspin speaker: the WebSocket endpoint servers connect to, announced on the local network as `_sendspin._tcp` (spec: "Server Initiated Connections").
class SendspinService {
  SendspinService({
    required this.name,
    required this.identity,
    this.onPlaybackStarted,
  });

  static const port = 8928;
  static const path = '/sendspin';

  final String name;
  final StaticKey identity;
  final void Function()? onPlaybackStarted;

  final _status = StreamController<SendspinStatus>.broadcast();
  SendspinStatus status = const SendspinStatus();
  SendspinListener? _listener;
  BonsoirBroadcast? _broadcast;

  Stream<SendspinStatus> get statusStream => _status.stream;

  Future<void> start() async {
    final output = ScheduledPcmOutput(
      NativePcmDevice(),
      onPlaybackStarted: onPlaybackStarted,
    );
    _listener = SendspinListener(
      config: SendspinConfig(identity: identity, name: name),
      output: output,
      port: port,
      path: path,
      onStatus: (s) {
        status = s;
        _status.add(s);
      },
    );
    await _listener!.start();
    _broadcast = BonsoirBroadcast(
      service: BonsoirService(
        name: name,
        type: '_sendspin._tcp',
        port: port,
        attributes: {'path': path, 'name': name},
      ),
    );
    await _broadcast!.initialize();
    await _broadcast!.start();
  }

  Future<void> stop() async {
    await _broadcast?.stop();
    _broadcast = null;
    await _listener?.stop();
    _listener = null;
    await _status.close();
  }

  /// The identity is the device's long-lived key pair, stored as base64.
  static Future<StaticKey> identityFrom(String? stored) async => stored == null
      ? await StaticKey.generate()
      : await StaticKey.fromPrivate(base64Decode(stored));

  static String encodeIdentity(StaticKey key) => base64Encode(key.privateKey);
}
