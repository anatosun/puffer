import 'dart:async';

import 'package:audio_service/audio_service.dart';

import '../data/subsonic/models.dart';
import 'player_handler.dart';

enum Repeat { off, one, all }

class QueueEntry {
  const QueueEntry({required this.id, required this.title, this.artist});

  final String id;
  final String title;
  final String? artist;
}

/// What is playing, on the phone or on a Music Assistant player. The now-playing screen reads only this.
class NowPlaying {
  const NowPlaying({
    this.track,
    required this.title,
    this.artist,
    this.album,
    this.coverArt,
    this.imageUrl,
    this.duration = Duration.zero,
    this.position = Duration.zero,
    required this.positionAt,
    this.playing = false,
    this.buffering = false,
    this.shuffle = false,
    this.repeat = Repeat.off,
    this.queue = const [],
    this.index,
    this.outputName,
    this.volume,
  });

  /// The Subsonic track, when known.
  final Track? track;
  final String title;
  final String? artist;
  final String? album;
  final String? coverArt;

  /// Artwork from Music Assistant, used when [coverArt] is unknown.
  final Uri? imageUrl;
  final Duration duration;
  final Duration position;
  final DateTime positionAt;
  final bool playing;
  final bool buffering;
  final bool shuffle;
  final Repeat repeat;
  final List<QueueEntry> queue;
  final int? index;

  /// The Music Assistant player, or null for this device.
  final String? outputName;

  /// Volume from 0 to 100 of the Music Assistant player.
  final int? volume;

  Duration positionNow([DateTime? now]) {
    if (!playing) return position;
    final value = position + (now ?? DateTime.now()).difference(positionAt);
    return duration > Duration.zero && value > duration ? duration : value;
  }
}

class QueueSnapshot {
  const QueueSnapshot(
    this.tracks,
    this.index,
    this.position, {
    required this.playing,
  });

  final List<Track> tracks;
  final int index;
  final Duration position;
  final bool playing;
}

abstract class PlaybackController {
  Stream<NowPlaying?> get state;
  NowPlaying? get current;

  Future<void> playTracks(
    List<Track> tracks, {
    int index = 0,
    bool shuffle = false,
  });
  Future<void> playNext(List<Track> tracks);
  Future<void> addTracks(List<Track> tracks);
  Future<void> play();
  Future<void> pause();
  Future<void> next();
  Future<void> previous();
  Future<void> seek(Duration position);
  Future<void> skipTo(int index);
  Future<void> setShuffle(bool enabled);
  Future<void> setRepeat(Repeat repeat);
  Future<void> removeAt(int index);
  Future<void> move(int from, int to);
  Future<void> setVolume(int volume);

  /// Stops playback and clears what is playing.
  Future<void> stop();

  /// The queue as Subsonic tracks with the current index and position, so it can move to another output. Null when the queue cannot be mapped to tracks.
  Future<QueueSnapshot?> snapshot();
  void dispose();
}

/// Plays on this device through [PlayerHandler].
class LocalPlaybackController implements PlaybackController {
  LocalPlaybackController(this.handler) {
    _subscriptions = [
      handler.mediaItem.listen((_) => _emit()),
      handler.playbackState.listen((_) => _emit()),
      handler.queue.listen((_) => _emit()),
    ];
  }

  final PlayerHandler handler;
  late final List<StreamSubscription<Object?>> _subscriptions;
  final _controller = StreamController<NowPlaying?>.broadcast();
  NowPlaying? _current;

  @override
  NowPlaying? get current => _current ?? _build();

  @override
  Stream<NowPlaying?> get state async* {
    yield current;
    yield* _controller.stream;
  }

  void _emit() {
    _current = _build();
    _controller.add(_current);
  }

  NowPlaying? _build() {
    final item = handler.mediaItem.value;
    if (item == null) return null;
    final s = handler.playbackState.value;
    final track = handler.currentTrack;
    return NowPlaying(
      track: track,
      title: item.title,
      artist: item.artist,
      album: item.album,
      coverArt: track?.coverArt,
      duration: item.duration ?? Duration.zero,
      position: s.updatePosition,
      positionAt: s.updateTime,
      playing: s.playing,
      buffering:
          s.processingState == AudioProcessingState.loading ||
          s.processingState == AudioProcessingState.buffering,
      shuffle: s.shuffleMode != AudioServiceShuffleMode.none,
      repeat: switch (s.repeatMode) {
        AudioServiceRepeatMode.none => Repeat.off,
        AudioServiceRepeatMode.one => Repeat.one,
        _ => Repeat.all,
      },
      queue: [
        for (final m in handler.queue.value)
          QueueEntry(id: m.id, title: m.title, artist: m.artist),
      ],
      index: s.queueIndex,
    );
  }

  @override
  Future<void> playTracks(
    List<Track> tracks, {
    int index = 0,
    bool shuffle = false,
  }) => handler.playTracks(tracks, index: index, shuffle: shuffle);
  @override
  Future<void> playNext(List<Track> tracks) => handler.playNext(tracks);
  @override
  Future<void> addTracks(List<Track> tracks) => handler.addTracks(tracks);
  @override
  Future<void> play() => handler.play();
  @override
  Future<void> pause() => handler.pause();
  @override
  Future<void> next() => handler.skipToNext();
  @override
  Future<void> previous() => handler.skipToPrevious();
  @override
  Future<void> seek(Duration position) => handler.seek(position);
  @override
  Future<void> skipTo(int index) => handler.skipToQueueItem(index);
  @override
  Future<void> setShuffle(bool enabled) => handler.setShuffleMode(
    enabled ? AudioServiceShuffleMode.all : AudioServiceShuffleMode.none,
  );
  @override
  Future<void> setRepeat(Repeat repeat) =>
      handler.setRepeatMode(switch (repeat) {
        Repeat.off => AudioServiceRepeatMode.none,
        Repeat.one => AudioServiceRepeatMode.one,
        Repeat.all => AudioServiceRepeatMode.all,
      });
  @override
  Future<void> removeAt(int index) => handler.removeQueueItemAt(index);
  @override
  Future<void> move(int from, int to) => handler.moveQueueItem(from, to);
  @override
  Future<void> setVolume(int volume) async {}

  @override
  Future<void> stop() => handler.stop();

  @override
  Future<QueueSnapshot?> snapshot() async {
    if (handler.tracks.isEmpty) return null;
    return QueueSnapshot(
      List.of(handler.tracks),
      handler.player.currentIndex ?? 0,
      handler.player.position,
      playing: handler.player.playing,
    );
  }

  @override
  void dispose() {
    for (final s in _subscriptions) {
      s.cancel();
    }
    _controller.close();
  }
}
