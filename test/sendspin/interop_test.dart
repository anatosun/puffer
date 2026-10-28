import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:puffer/sendspin/listener.dart';
import 'package:puffer/sendspin/noise.dart';
import 'package:puffer/sendspin/session.dart';

class RecordingOutput implements SendspinAudioOutput {
  AudioFormat? format;
  final chunks = <(int, int)>[];
  int volume = 100;

  @override
  void start(AudioFormat format) => this.format = format;

  @override
  void chunk(int localTimestamp, Uint8List pcm) =>
      chunks.add((localTimestamp, pcm.length));

  @override
  void clear() {}

  @override
  void stop() {}

  @override
  void setVolume(int volume, {required bool muted}) => this.volume = volume;

  @override
  int get latencyMs => 0;
}

/// Runs only with SENDSPIN_PYTHON pointing at a Python interpreter that has aiosendspin installed.
void main() {
  final python = Platform.environment['SENDSPIN_PYTHON'];

  test(
    'aiosendspin connects, synchronises clocks and streams audio to the player',
    () async {
      final output = RecordingOutput();
      final identity = await StaticKey.generate();
      final listener = SendspinListener(
        config: SendspinConfig(identity: identity, name: 'Puffer test'),
        output: output,
        port: 0,
      );
      await listener.start();

      final process = await Process.start(python!, [
        'test/sendspin/interop_server.py',
        'ws://127.0.0.1:${listener.boundPort}/sendspin',
        identity.id,
      ]);
      final lines = <String>[];
      final done = Completer<void>();
      process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            lines.add(line);
            if (line == 'DONE') done.complete();
          });
      process.stderr.transform(utf8.decoder).listen(stderr.write);

      await done.future.timeout(const Duration(seconds: 60));
      await listener.stop();
      process.kill();

      expect(lines, contains('READY'));
      expect(output.format?.codec, 'pcm');
      expect(output.format?.sampleRate, 48000);
      // Three seconds of audio arrive, and each chunk starts where the previous one ends.
      const bytesPerSecond = 48000 * 4;
      final total = output.chunks.fold<int>(0, (sum, c) => sum + c.$2);
      expect(total / bytesPerSecond, closeTo(3, 0.3));
      for (var i = 1; i < output.chunks.length; i++) {
        final previousDuration =
            output.chunks[i - 1].$2 * 1000000 ~/ bytesPerSecond;
        expect(
          output.chunks[i].$1 - output.chunks[i - 1].$1,
          closeTo(previousDuration, 1000),
        );
      }
    },
    skip: python == null
        ? 'set SENDSPIN_PYTHON to run against aiosendspin'
        : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
