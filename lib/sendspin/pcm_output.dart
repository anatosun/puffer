import 'dart:async';
import 'dart:collection';
import 'dart:math';
import 'dart:typed_data';

import 'session.dart';

/// The operations the scheduler needs from an audio device, so tests can simulate one.
abstract class PcmDevice {
  bool open({
    required int sampleRate,
    required int channels,
    required int capacityFrames,
  });
  void close();
  int write(Int16List samples);
  int get writePosition;
  int get readPosition;
  int get latencyFrames;
  int get nowNs;
  void clear();
  set volume(double amplitude);
  (int, int)? lastCallback();
}

class _Chunk {
  _Chunk(this.startNs, this.samples);

  /// When the first frame must leave the speaker, on the device clock.
  int startNs;
  Int16List samples;
}

/// Plays Sendspin audio on a [PcmDevice] at the times the server asks for (spec: player v1, "Playback Synchronization").
///
/// The ring position the device last read, and when, give the time at which the next written frame will play. Each chunk is written so its first frame lands at its timestamp: small errors are corrected by dropping or repeating one frame, larger ones (after a start, a seek or an underrun) by one jump of silence or skipped frames.
class ScheduledPcmOutput implements SendspinAudioOutput {
  ScheduledPcmOutput(
    this.device, {
    this.onPlaybackStarted,
    this.onPlaybackStopped,
  });

  final PcmDevice device;
  final void Function()? onPlaybackStarted;
  final void Function()? onPlaybackStopped;

  /// How far ahead of the speaker audio is written.
  static const _aheadNs = 400 * 1000000;

  /// Errors below this are left alone; between this and [_snapNs] one frame is dropped or repeated per chunk.
  static const _deadBandNs = 100 * 1000;
  static const _snapNs = 1000 * 1000;

  AudioFormat? _format;
  final _queue = ListQueue<_Chunk>();
  Timer? _pump;
  bool _resync = true;
  int _calibrationNs = 0;
  double _volume = 1;
  bool _muted = false;

  @override
  int get latencyMs =>
      _format == null ? 50 : device.latencyFrames * 1000 ~/ _format!.sampleRate;

  @override
  void start(AudioFormat format) {
    if (format.codec != 'pcm' || format.bitDepth != 16) return;
    final current = _format;
    if (current == null ||
        current.sampleRate != format.sampleRate ||
        current.channels != format.channels) {
      device.close();
      if (!device.open(
        sampleRate: format.sampleRate,
        channels: format.channels,
        capacityFrames: format.sampleRate,
      )) {
        return;
      }
      _applyVolume();
      onPlaybackStarted?.call();
    }
    _format = format;
    // The device clock and the monotonic clock of the session differ by a constant.
    _calibrationNs = device.nowNs - monotonicMicros() * 1000;
    _resync = true;
    _pump ??= Timer.periodic(const Duration(milliseconds: 10), (_) => fill());
  }

  @override
  void chunk(int localTimestamp, Uint8List pcm) {
    if (_format == null) return;
    final samples = Int16List(pcm.length ~/ 2);
    samples.buffer.asUint8List().setAll(0, pcm.sublist(0, samples.length * 2));
    _queue.add(_Chunk(localTimestamp * 1000 + _calibrationNs, samples));
  }

  @override
  void clear() {
    _queue.clear();
    device.clear();
    _resync = true;
  }

  @override
  void stop() {
    if (_format == null) return;
    _pump?.cancel();
    _pump = null;
    _queue.clear();
    device.close();
    _format = null;
    onPlaybackStopped?.call();
  }

  @override
  void setVolume(int volume, {required bool muted}) {
    // Perceived loudness to amplitude, as the specification recommends.
    _volume = pow(volume.clamp(0, 100) / 100, 1.5).toDouble();
    _muted = muted;
    _applyVolume();
  }

  void _applyVolume() => device.volume = _muted ? 0 : _volume;

  /// When the frame at ring position [position] will leave the speaker, on the device clock.
  int _playTimeNs(int position, int rate) {
    final latencyNs = device.latencyFrames * 1000000000 ~/ rate;
    final callback = device.lastCallback();
    if (callback == null) {
      return device.nowNs +
          (position - device.readPosition) * 1000000000 ~/ rate +
          latencyNs;
    }
    final (readAt, at) = callback;
    return at + (position - readAt) * 1000000000 ~/ rate + latencyNs;
  }

  /// Writes queued audio until the device holds [_aheadNs] of it.
  void fill() {
    final format = _format;
    if (format == null) return;
    final rate = format.sampleRate, channels = format.channels;
    // An empty ring means an underrun: the next chunk jumps into place.
    if (device.writePosition - device.readPosition <= 0) _resync = true;
    while (_queue.isNotEmpty) {
      final buffered = device.writePosition - device.readPosition;
      if (buffered * 1000000000 ~/ rate >= _aheadNs) return;
      final chunk = _queue.first;
      final errorNs = chunk.startNs - _playTimeNs(device.writePosition, rate);
      final errorFrames = errorNs * rate ~/ 1000000000;
      if (_resync || errorNs.abs() > _snapNs) {
        _resync = false;
        if (errorFrames > 0) {
          // Early: wait with silence.
          device.write(Int16List(min(errorFrames, rate) * channels));
          continue;
        }
        // Late: skip the frames whose time has passed.
        final skip = -errorFrames;
        if (skip * channels >= chunk.samples.length) {
          _queue.removeFirst();
          continue;
        }
        chunk.samples = Int16List.sublistView(chunk.samples, skip * channels);
        chunk.startNs += skip * 1000000000 ~/ rate;
      } else if (errorNs.abs() > _deadBandNs &&
          chunk.samples.length > channels * 2) {
        if (errorNs < 0) {
          // Slightly late: drop one frame.
          chunk.samples = Int16List.sublistView(chunk.samples, channels);
        } else {
          // Slightly early: repeat the first frame.
          device.write(Int16List.sublistView(chunk.samples, 0, channels));
        }
      }
      final written = device.write(chunk.samples);
      if (written * channels < chunk.samples.length) {
        chunk.samples = Int16List.sublistView(
          chunk.samples,
          written * channels,
        );
        chunk.startNs += written * 1000000000 ~/ rate;
        return;
      }
      _queue.removeFirst();
    }
  }
}
