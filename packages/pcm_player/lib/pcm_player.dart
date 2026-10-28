import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// PCM output through miniaudio: a ring buffer of interleaved 16-bit frames, with the ring position and time of the device's last read, so callers can schedule playback against [nowNs].
class PcmPlayer {
  PcmPlayer._(DynamicLibrary lib)
    : _open = lib
          .lookupFunction<
            Int32 Function(Int32, Int32, Int32),
            int Function(int, int, int)
          >('pcm_open'),
      _close = lib.lookupFunction<Void Function(), void Function()>(
        'pcm_close',
      ),
      _write = lib
          .lookupFunction<
            Int32 Function(Pointer<Int16>, Int32),
            int Function(Pointer<Int16>, int)
          >('pcm_write'),
      _writePosition = lib.lookupFunction<Int64 Function(), int Function()>(
        'pcm_write_position',
      ),
      _readPosition = lib.lookupFunction<Int64 Function(), int Function()>(
        'pcm_read_position',
      ),
      _clear = lib.lookupFunction<Void Function(), void Function()>(
        'pcm_clear',
      ),
      _lastCallback = lib
          .lookupFunction<
            Int32 Function(Pointer<Int64>, Pointer<Int64>),
            int Function(Pointer<Int64>, Pointer<Int64>)
          >('pcm_last_callback'),
      _latencyFrames = lib.lookupFunction<Int32 Function(), int Function()>(
        'pcm_latency_frames',
      ),
      _setVolume = lib
          .lookupFunction<Void Function(Float), void Function(double)>(
            'pcm_set_volume',
          ),
      _nowNs = lib.lookupFunction<Int64 Function(), int Function()>(
        'pcm_now_ns',
      );

  static final PcmPlayer instance = PcmPlayer._(_load());

  static DynamicLibrary _load() {
    if (Platform.isIOS || Platform.isMacOS) return DynamicLibrary.process();
    if (Platform.isWindows) return DynamicLibrary.open('pcm_player.dll');
    return DynamicLibrary.open('libpcm_player.so');
  }

  final int Function(int, int, int) _open;
  final void Function() _close;
  final int Function(Pointer<Int16>, int) _write;
  final int Function() _writePosition;
  final int Function() _readPosition;
  final void Function() _clear;
  final int Function(Pointer<Int64>, Pointer<Int64>) _lastCallback;
  final int Function() _latencyFrames;
  final void Function(double) _setVolume;
  final int Function() _nowNs;

  Pointer<Int16> _buffer = nullptr;
  int _bufferFrames = 0;
  int _channels = 2;

  /// Opens the default output. Returns false when no device is available.
  bool open({
    required int sampleRate,
    required int channels,
    required int capacityFrames,
  }) {
    _channels = channels;
    return _open(sampleRate, channels, capacityFrames) == 0;
  }

  void close() {
    _close();
    if (_buffer != nullptr) calloc.free(_buffer);
    _buffer = nullptr;
    _bufferFrames = 0;
  }

  /// Appends [frames] interleaved samples (a multiple of the channel count); returns how many frames fit.
  int write(Int16List samples) {
    final frames = samples.length ~/ _channels;
    if (frames == 0) return 0;
    if (frames > _bufferFrames) {
      if (_buffer != nullptr) calloc.free(_buffer);
      _buffer = calloc<Int16>(frames * _channels);
      _bufferFrames = frames;
    }
    _buffer.asTypedList(frames * _channels).setAll(0, samples);
    return _write(_buffer, frames);
  }

  int get writePosition => _writePosition();
  int get readPosition => _readPosition();
  int get bufferedFrames => _writePosition() - _readPosition();
  int get latencyFrames => _latencyFrames();
  int get nowNs => _nowNs();

  void clear() => _clear();

  set volume(double amplitude) => _setVolume(amplitude);

  /// The ring position the device read at its last callback and when, or null before the first callback.
  (int, int)? lastCallback() {
    final position = calloc<Int64>(), at = calloc<Int64>();
    try {
      return _lastCallback(position, at) == 0
          ? null
          : (position.value, at.value);
    } finally {
      calloc.free(position);
      calloc.free(at);
    }
  }
}
