import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:path/path.dart' as p;

/// A silent WAV file of [seconds] at 8 kHz, mono, 16 bits.
File _silence(Directory dir, String name, int seconds) {
  const rate = 8000;
  final data = rate * 2 * seconds;
  final bytes = ByteData(44 + data);
  void ascii(int at, String s) {
    for (var i = 0; i < s.length; i++) {
      bytes.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  bytes.setUint32(4, 36 + data, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 1, Endian.little);
  bytes.setUint16(22, 1, Endian.little);
  bytes.setUint32(24, rate, Endian.little);
  bytes.setUint32(28, rate * 2, Endian.little);
  bytes.setUint16(32, 2, Endian.little);
  bytes.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  bytes.setUint32(40, data, Endian.little);
  return File(p.join(dir.path, name))
    ..writeAsBytesSync(bytes.buffer.asUint8List());
}

/// Runs against libmpv, muted, on Linux when MEDIA_KIT_NATIVE=1:
///   MEDIA_KIT_NATIVE=1 flutter test test/media_kit_queue_test.dart
void main() {
  final enabled =
      Platform.isLinux && Platform.environment['MEDIA_KIT_NATIVE'] == '1';

  test('songs inserted inside the queue play at their place', () async {
    JustAudioMediaKit.ensureInitialized(linux: true);
    final dir = Directory.systemTemp.createTempSync('media_kit_queue');
    addTearDown(() => dir.deleteSync(recursive: true));
    // Each file has its own length, which tells which one the player holds.
    AudioSource song(int seconds) =>
        AudioSource.file(_silence(dir, '$seconds.wav', seconds).path);
    final player = AudioPlayer(
      handleInterruptions: false,
      handleAudioSessionActivation: false,
    );
    addTearDown(player.dispose);
    await player.setVolume(0);
    await player.setAudioSources([song(2), song(3), song(4)]);
    // A song replaced in place, as when its cached file replaces its stream, then two songs at the start.
    await player.removeAudioSourceAt(1);
    await player.insertAudioSource(1, song(5));
    await player.insertAudioSources(0, [song(6), song(7)]);
    final lengths = <int?>[];
    for (var i = 0; i < 5; i++) {
      await player.seek(Duration.zero, index: i);
      await Future<void>.delayed(const Duration(milliseconds: 700));
      lengths.add(player.duration?.inSeconds);
    }
    expect(lengths, [6, 7, 2, 5, 4]);
  }, skip: enabled ? false : 'needs libmpv: MEDIA_KIT_NATIVE=1 on Linux');
}
