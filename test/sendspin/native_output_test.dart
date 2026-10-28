import 'dart:typed_data';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:puffer/sendspin/listener.dart';
import 'package:puffer/sendspin/noise.dart';
import 'package:puffer/sendspin/pcm_output.dart';
import 'package:puffer/sendspin/sendspin_service.dart';
import 'package:puffer/sendspin/session.dart';

/// Runs on the real audio device, muted, when LD_LIBRARY_PATH contains a built libpcm_player.so and PCM_PLAYER_NATIVE=1:
///   LD_LIBRARY_PATH=build/linux/x64/debug/plugins/pcm_player/shared PCM_PLAYER_NATIVE=1 flutter test test/sendspin/native_output_test.dart
void main() {
  final enabled = Platform.environment['PCM_PLAYER_NATIVE'] == '1';
  final python = Platform.environment['SENDSPIN_PYTHON'];

  test(
    'the device reads frames at its sample rate and reports its position',
    () async {
      final device = NativePcmDevice();
      expect(
        device.open(sampleRate: 48000, channels: 2, capacityFrames: 48000),
        isTrue,
      );
      device.volume = 0;
      final start = DateTime.now();
      final written = device.write(Int16List(48000 * 2));
      expect(written, 48000);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final elapsed = DateTime.now().difference(start).inMicroseconds / 1e6;
      final read = device.readPosition;
      expect(read / 48000, closeTo(elapsed, 0.15));
      final callback = device.lastCallback();
      expect(callback, isNotNull);
      expect(device.nowNs - callback!.$2, lessThan(100000000));
      expect(device.latencyFrames, greaterThan(0));
      device.close();
    },
    skip: enabled
        ? false
        : 'set PCM_PLAYER_NATIVE=1 with the built library on LD_LIBRARY_PATH',
  );

  test(
    'aiosendspin plays through the scheduler to the device',
    () async {
      final device = NativePcmDevice();
      var started = false;
      final output = ScheduledPcmOutput(
        device,
        onPlaybackStarted: () => started = true,
      );
      output.setVolume(0, muted: true);
      final identity = await StaticKey.generate();
      final listener = SendspinListener(
        config: SendspinConfig(identity: identity, name: 'Puffer native test'),
        output: output,
        port: 0,
      );
      await listener.start();
      final process = await Process.start(python!, [
        'test/sendspin/interop_server.py',
        'ws://127.0.0.1:${listener.boundPort}/sendspin',
        identity.id,
      ]);
      final done = Completer<void>();
      int? readWhenStreaming;
      process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            if (line == 'READY') readWhenStreaming = 0;
            if (line == 'DONE') done.complete();
          });
      await done.future.timeout(const Duration(seconds: 60));
      // The device consumed the three seconds of audio, plus the silence before it.
      final read = device.readPosition;
      await listener.stop();
      process.kill();
      expect(readWhenStreaming, isNotNull);
      expect(started, isTrue);
      expect(read / 48000, greaterThan(2.5));
    },
    skip: enabled && python != null
        ? false
        : 'set PCM_PLAYER_NATIVE=1 and SENDSPIN_PYTHON',
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
