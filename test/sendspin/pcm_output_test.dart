import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:puffer/sendspin/pcm_output.dart';
import 'package:puffer/sendspin/session.dart';

/// A device whose clock the test advances; it plays [rate] frames per second and reads in callbacks of 10 ms.
class FakeDevice implements PcmDevice {
  FakeDevice(this.rate);

  final int rate;
  int now = 1000000000;
  final written = <int>[];
  int _read = 0;
  (int, int)? _callback;
  double amplitude = 1;
  @override
  int latencyFrames = 480;

  @override
  bool open({
    required int sampleRate,
    required int channels,
    required int capacityFrames,
  }) => true;
  @override
  void close() {}
  @override
  int write(Int16List samples) {
    for (var i = 0; i < samples.length; i += 2) {
      written.add(samples[i]);
    }
    return samples.length ~/ 2;
  }

  @override
  int get writePosition => written.length;
  @override
  int get readPosition => _read;
  @override
  int get nowNs => now;
  @override
  void clear() => written.length = _read;
  @override
  set volume(double value) => amplitude = value;
  @override
  (int, int)? lastCallback() => _callback;

  /// Advances the clock by 10 ms and lets the device read that much.
  void tick() {
    _callback = (_read, now);
    _read = (_read + rate ~/ 100).clamp(0, written.length);
    now += 10000000;
  }
}

/// A stereo chunk whose left samples count up from [first].
Uint8List chunk(int first, int frames) {
  final samples = Int16List(frames * 2);
  for (var i = 0; i < frames; i++) {
    samples[i * 2] = first + i;
  }
  return samples.buffer.asUint8List();
}

void main() {
  const format = AudioFormat(
    codec: 'pcm',
    sampleRate: 48000,
    channels: 2,
    bitDepth: 16,
  );

  test('the first chunk is preceded by silence until its timestamp', () {
    final device = FakeDevice(48000);
    final output = ScheduledPcmOutput(device)..start(format);
    device.tick();
    // Due 200 ms after the device clock's "now"; the session clock maps 1:1 onto the device clock here.
    final dueMicros = monotonicMicros() + 200000;
    output.chunk(dueMicros, chunk(1, 960));
    output.fill();
    final silence = device.written.indexWhere((s) => s == 1);
    // 200 ms minus the 10 ms latency of 480 frames, give or take a little of the time the test itself takes.
    expect(silence, closeTo(48000 * 0.19, 48000 * 0.01));
    output.stop();
  });

  test('a late chunk skips the frames whose time has passed', () {
    final device = FakeDevice(48000);
    final output = ScheduledPcmOutput(device)..start(format);
    device.tick();
    output.chunk(monotonicMicros() - 5000, chunk(1, 960));
    output.fill();
    expect(device.written.first, greaterThan(1));
    output.stop();
  });

  test('consecutive chunks play back to back without silence', () {
    final device = FakeDevice(48000);
    final output = ScheduledPcmOutput(device)..start(format);
    device.tick();
    final start = monotonicMicros() + 100000;
    for (var i = 0; i < 5; i++) {
      output.chunk(start + i * 20000, chunk(1 + i * 960, 960));
    }
    output.fill();
    final first = device.written.indexOf(1);
    final played = device.written.sublist(first, first + 5 * 960);
    // Corrections touch at most a frame per chunk.
    var gaps = 0;
    for (var i = 1; i < played.length; i++) {
      if (played[i] != played[i - 1] + 1) gaps++;
    }
    expect(gaps, lessThanOrEqualTo(5));
    output.stop();
  });

  test('volume follows the perceived loudness curve and mute', () {
    final device = FakeDevice(48000);
    final output = ScheduledPcmOutput(device)..start(format);
    output.setVolume(50, muted: false);
    expect(device.amplitude, closeTo(0.3536, 0.001));
    output.setVolume(50, muted: true);
    expect(device.amplitude, 0);
    output.stop();
  });
}
