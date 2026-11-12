import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:path/path.dart' as p;
import 'package:puffer/data/subsonic/models.dart';
import 'package:puffer/playback/past_queues.dart';
import 'package:puffer/playback/player_handler.dart';

/// Songs whose audio is a file named by their ID.
class _Files implements PlaybackSource {
  _Files(this.dir);

  final Directory dir;

  @override
  Future<String?> localPath(String trackId) async =>
      p.join(dir.path, '$trackId.wav');
  @override
  Uri streamUri(Track track) => Uri.file(p.join(dir.path, '${track.id}.wav'));
  @override
  Uri? streamUriFrom(Track track, Duration offset) => null;
  @override
  Future<void> decide(List<Track> tracks) async {}
  @override
  Future<String?> cachedPath(Track track) async => null;
  @override
  Future<void> prefetch(
    List<Track> upcoming, {
    required Set<Track> keep,
    required void Function(Track track, String path) ready,
    required void Function(Set<String> fileNames) removed,
    void Function(Track track, double fraction)? progress,
  }) async {}
  @override
  Uri? artUri(String? coverArt) => null;
  @override
  Future<Uri?> fetchArt(String? coverArt) async => null;
  @override
  Future<void> nowPlaying(Track track) async {}
  @override
  Future<void> played(Track track) async {}
  @override
  double volumeFor(Track track) => 0;
  @override
  Duration get crossfade => Duration.zero;
}

/// Songs streamed from [base], whose fetching to the cache the test drives.
class _Streamed extends _Files {
  _Streamed(super.dir, this.base);

  final Uri base;
  List<String> fetched = const [];

  /// The files of the songs fetched ahead, by track ID. Each is there from the second time the handler asks, as for a song whose fetch ends after its stream started.
  Map<String, String> cached = const {};
  final _asked = <String>{};
  void Function(Track track, String path)? onReady;
  void Function(Track track, double fraction)? onProgress;

  @override
  Future<String?> localPath(String trackId) async => null;
  @override
  Uri streamUri(Track track) => base.replace(path: '/${track.id}.wav');
  @override
  Future<String?> cachedPath(Track track) async =>
      _asked.add(track.id) ? null : cached[track.id];
  @override
  Future<void> prefetch(
    List<Track> upcoming, {
    required Set<Track> keep,
    required void Function(Track track, String path) ready,
    required void Function(Set<String> fileNames) removed,
    void Function(Track track, double fraction)? progress,
  }) async {
    fetched = [for (final t in upcoming) t.id];
    onReady = ready;
    onProgress = progress;
  }
}

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

  test(
    'a radio replaces the songs after the one that plays, which plays on',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('com.ryanheise.audio_session'),
            (_) async => null,
          );
      JustAudioMediaKit.ensureInitialized(linux: true);
      final dir = Directory.systemTemp.createTempSync('media_kit_radio');
      addTearDown(() => dir.deleteSync(recursive: true));
      Track song(String id, int seconds) {
        _silence(dir, '$id.wav', seconds);
        return Track({'id': id, 'title': id, 'duration': seconds});
      }

      final handler = PlayerHandler()..source = _Files(dir);
      addTearDown(handler.player.dispose);
      await handler.playTracks([
        song('a', 9),
        song('b', 8),
        song('c', 4),
      ], index: 1);
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      // A song that plays from its file is on this device in full.
      expect(handler.buffered, const Duration(seconds: 8));
      final before = handler.position;
      await handler.replaceUpcoming([song('r1', 5), song('r2', 6)]);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect([for (final t in handler.tracks) t.id], ['a', 'b', 'r1', 'r2']);
      expect(handler.player.currentIndex, 1);
      // The song did not start again.
      expect(handler.position, greaterThan(before));
      await handler.player.seek(Duration.zero, index: 2);
      await Future<void>.delayed(const Duration(milliseconds: 700));
      expect(handler.player.duration?.inSeconds, 5);
    },
    skip: enabled ? false : 'needs libmpv: MEDIA_KIT_NATIVE=1 on Linux',
  );

  test('a streamed song shows the part of it fetched to the cache', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.ryanheise.audio_session'),
          (_) async => null,
        );
    // A cache of two seconds, so the player loads far less than the song.
    final size = JustAudioMediaKit.bufferSize;
    JustAudioMediaKit.bufferSize = 32 * 1024;
    addTearDown(() => JustAudioMediaKit.bufferSize = size);
    JustAudioMediaKit.ensureInitialized(linux: true);
    final dir = Directory.systemTemp.createTempSync('media_kit_stream');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = _silence(dir, 's.wav', 120);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((request) async {
      request.response.headers
        ..contentType = ContentType('audio', 'wav')
        ..contentLength = file.lengthSync();
      await request.response.addStream(file.openRead());
      await request.response.close();
    });
    final source = _Streamed(dir, Uri.parse('http://127.0.0.1:${server.port}'));
    final handler = PlayerHandler()..source = source;
    addTearDown(handler.player.dispose);
    const song = Track({'id': 's', 'title': 's', 'duration': 120});
    await handler.playTracks([song]);
    await Future<void>.delayed(const Duration(milliseconds: 1500));

    // The song that plays is fetched with the next ones.
    expect(source.fetched, ['s']);
    expect(handler.buffered, lessThan(const Duration(seconds: 30)));
    source.onProgress!(song, 0.75);
    expect(handler.buffered, const Duration(seconds: 90));
    source.onReady!(song, file.path);
    expect(handler.buffered, const Duration(minutes: 2));
  }, skip: enabled ? false : 'needs libmpv: MEDIA_KIT_NATIVE=1 on Linux');

  test(
    'a queue that runs out leaves the player and joins the past queues',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('com.ryanheise.audio_session'),
            (_) async => null,
          );
      JustAudioMediaKit.ensureInitialized(linux: true);
      final dir = Directory.systemTemp.createTempSync('media_kit_end');
      addTearDown(() => dir.deleteSync(recursive: true));
      Track song(String id, int seconds) {
        _silence(dir, '$id.wav', seconds);
        return Track({'id': id, 'title': id, 'duration': seconds});
      }

      final past = <PastQueue>[];
      final handler = PlayerHandler()
        ..source = _Files(dir)
        ..onReplaced = past.add;
      addTearDown(handler.player.dispose);
      await handler.playTracks([song('a', 3), song('b', 2)], index: 1);
      await handler.play();
      await handler.mediaItem
          .firstWhere((item) => item == null)
          .timeout(const Duration(seconds: 10));
      expect(handler.tracks, isEmpty);
      expect(handler.queue.value, isEmpty);
      expect([for (final t in past.single.tracks) t.id], ['a', 'b']);
    },
    skip: enabled ? false : 'needs libmpv: MEDIA_KIT_NATIVE=1 on Linux',
  );

  test(
    'shuffled songs play in the shuffle order, each at its own index',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('com.ryanheise.audio_session'),
            (_) async => null,
          );
      JustAudioMediaKit.ensureInitialized(linux: true);
      final dir = Directory.systemTemp.createTempSync('media_kit_shuffle');
      addTearDown(() => dir.deleteSync(recursive: true));
      // Each file has its own length, which tells which one the player holds.
      final lengths = [1, 2, 3, 4];
      final player = AudioPlayer(
        handleInterruptions: false,
        handleAudioSessionActivation: false,
      );
      addTearDown(player.dispose);
      await player.setVolume(0);
      await player.setAudioSources([
        for (final l in lengths)
          AudioSource.file(_silence(dir, '$l.wav', l).path),
      ], shuffleOrder: DefaultShuffleOrder(random: Random(7)));
      await player.setShuffleModeEnabled(true);
      final order = player.effectiveIndices;
      // A queue order would prove nothing.
      expect(order, isNot([0, 1, 2, 3]));
      await player.seek(Duration.zero, index: order.first);

      final played = <int>[];
      final mismatched = <String>[];
      final sub = player.durationStream.listen((duration) {
        final index = player.currentIndex;
        if (duration == null || index == null) return;
        if (played.lastOrNull != index) played.add(index);
        if (duration.inSeconds != lengths[index]) {
          mismatched.add('index $index holds a ${duration.inSeconds} s song');
        }
      });
      addTearDown(sub.cancel);
      await player.play();
      await player.processingStateStream
          .firstWhere((s) => s == ProcessingState.completed)
          .timeout(const Duration(seconds: 25));
      expect(played, order);
      expect(mismatched, isEmpty);
    },
    skip: enabled ? false : 'needs libmpv: MEDIA_KIT_NATIVE=1 on Linux',
  );

  test('a stream that fails carries on from the file of the song', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.ryanheise.audio_session'),
          (_) async => null,
        );
    JustAudioMediaKit.ensureInitialized(linux: true);
    final dir = Directory.systemTemp.createTempSync('media_kit_recover');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = _silence(dir, 's.wav', 30);
    // A server that has lost the song, as one out of reach would.
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((request) async {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    });
    final source = _Streamed(dir, Uri.parse('http://127.0.0.1:${server.port}'))
      ..cached = {'s': file.path};
    final handler = PlayerHandler()..source = source;
    addTearDown(handler.player.dispose);
    const song = Track({'id': 's', 'title': 's', 'duration': 30});
    try {
      await handler.playTracks([song]);
    } on PlayerException {
      // The stream failed; the handler carries on from the file.
    }
    await handler.player.durationStream
        .firstWhere((d) => d == const Duration(seconds: 30))
        .timeout(const Duration(seconds: 10));
    final entry = handler.player.audioSources.single as UriAudioSource;
    expect(entry.uri.scheme, 'file');
  }, skip: enabled ? false : 'needs libmpv: MEDIA_KIT_NATIVE=1 on Linux');
}
