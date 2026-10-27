import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';

import '../data/subsonic/models.dart';

/// What the handler needs from the session: where each track's audio and artwork are, and where to report plays.
abstract class PlaybackSource {
  Future<String?> localPath(String trackId);
  Uri streamUri(Track track);
  Uri? artUri(String? coverArt);
  Future<void> nowPlaying(Track track);
  Future<void> played(Track track);

  /// The volume from 0 to 1 at which [track] plays, for loudness normalisation.
  double volumeFor(Track track);
}

/// Plays on the phone through just_audio and reports to the system media controls through audio_service.
class PlayerHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  PlayerHandler() {
    _init();
  }

  final player = AudioPlayer();
  PlaybackSource? source;

  List<Track> _tracks = const [];
  String? _scrobbled;

  /// The tracks of the queue, in queue order.
  List<Track> get tracks => _tracks;

  Track? get currentTrack {
    final index = player.currentIndex;
    return index == null || index >= _tracks.length ? null : _tracks[index];
  }

  Future<void> _init() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());

    player.playbackEventStream.listen(
      _broadcastState,
      onError: (Object _, StackTrace _) {},
    );
    player.playingStream.listen((_) => _broadcastState(player.playbackEvent));
    player.currentIndexStream.listen((index) {
      if (index == null || index >= _tracks.length) return;
      mediaItem.add(queue.value[index]);
      final track = _tracks[index];
      player.setVolume(source?.volumeFor(track) ?? 1);
      source?.nowPlaying(track);
      _scrobbled = null;
    });
    // A play counts once half of the track, or four minutes, has played.
    player.positionStream.listen((position) {
      final track = currentTrack;
      if (track == null || _scrobbled == track.id) return;
      final duration = player.duration ?? track.duration;
      if (duration == Duration.zero) return;
      if (position >= duration * 0.5 ||
          position >= const Duration(minutes: 4)) {
        _scrobbled = track.id;
        source?.played(track);
      }
    });
  }

  Future<AudioSource> _audioSource(Track track) async {
    final path = await source?.localPath(track.id);
    if (path != null) return AudioSource.file(path, tag: track.id);
    return AudioSource.uri(source!.streamUri(track), tag: track.id);
  }

  MediaItem _mediaItem(Track track) => MediaItem(
    id: track.id,
    title: track.title,
    album: track.album,
    artist: track.artist,
    duration: track.duration,
    artUri: source?.artUri(track.coverArt),
  );

  Future<void> playTracks(
    List<Track> tracks, {
    int index = 0,
    bool shuffle = false,
  }) async {
    if (tracks.isEmpty || source == null) return;
    _tracks = List.of(tracks);
    queue.add([for (final t in _tracks) _mediaItem(t)]);
    final sources = await Future.wait(_tracks.map(_audioSource));
    await player.setShuffleModeEnabled(shuffle);
    await player.setAudioSources(
      sources,
      initialIndex: shuffle ? null : index,
      initialPosition: Duration.zero,
    );
    if (shuffle) await player.shuffle();
    await player.play();
  }

  /// Loads a saved queue paused at [position] of track [index].
  Future<void> restore(List<Track> tracks, int index, Duration position) async {
    if (tracks.isEmpty || source == null) return;
    _tracks = List.of(tracks);
    queue.add([for (final t in _tracks) _mediaItem(t)]);
    final sources = await Future.wait(_tracks.map(_audioSource));
    await player.setAudioSources(
      sources,
      initialIndex: index,
      initialPosition: position,
    );
  }

  Future<void> playNext(List<Track> tracks) async {
    if (_tracks.isEmpty) return playTracks(tracks);
    var insertAt = (player.currentIndex ?? -1) + 1;
    for (final t in tracks) {
      await player.insertAudioSource(insertAt, await _audioSource(t));
      _tracks.insert(insertAt, t);
      insertAt++;
    }
    queue.add([for (final t in _tracks) _mediaItem(t)]);
  }

  Future<void> addTracks(List<Track> tracks) async {
    if (_tracks.isEmpty) return playTracks(tracks);
    for (final t in tracks) {
      await player.addAudioSource(await _audioSource(t));
      _tracks.add(t);
    }
    queue.add([for (final t in _tracks) _mediaItem(t)]);
  }

  @override
  Future<void> removeQueueItemAt(int index) async {
    await player.removeAudioSourceAt(index);
    _tracks.removeAt(index);
    queue.add([for (final t in _tracks) _mediaItem(t)]);
  }

  Future<void> moveQueueItem(int from, int to) async {
    await player.moveAudioSource(from, to);
    _tracks.insert(to, _tracks.removeAt(from));
    queue.add([for (final t in _tracks) _mediaItem(t)]);
  }

  @override
  Future<void> play() => player.play();

  @override
  Future<void> pause() => player.pause();

  @override
  Future<void> seek(Duration position) => player.seek(position);

  @override
  Future<void> skipToNext() => player.seekToNext();

  @override
  Future<void> skipToPrevious() async {
    if (player.position > const Duration(seconds: 3)) {
      return player.seek(Duration.zero);
    }
    return player.seekToPrevious();
  }

  @override
  Future<void> skipToQueueItem(int index) =>
      player.seek(Duration.zero, index: index);

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    final enabled = shuffleMode != AudioServiceShuffleMode.none;
    if (enabled) await player.shuffle();
    await player.setShuffleModeEnabled(enabled);
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) =>
      player.setLoopMode(switch (repeatMode) {
        AudioServiceRepeatMode.none => LoopMode.off,
        AudioServiceRepeatMode.one => LoopMode.one,
        AudioServiceRepeatMode.all ||
        AudioServiceRepeatMode.group => LoopMode.all,
      });

  @override
  Future<void> stop() async {
    await player.stop();
    await player.clearAudioSources();
    _tracks = const [];
    queue.add(const []);
    mediaItem.add(null);
    await super.stop();
  }

  void _broadcastState(PlaybackEvent event) {
    final playing = player.playing;
    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: const {
          ProcessingState.idle: AudioProcessingState.idle,
          ProcessingState.loading: AudioProcessingState.loading,
          ProcessingState.buffering: AudioProcessingState.buffering,
          ProcessingState.ready: AudioProcessingState.ready,
          ProcessingState.completed: AudioProcessingState.completed,
        }[player.processingState]!,
        playing: playing,
        updatePosition: player.position,
        bufferedPosition: player.bufferedPosition,
        speed: player.speed,
        queueIndex: event.currentIndex,
        shuffleMode: player.shuffleModeEnabled
            ? AudioServiceShuffleMode.all
            : AudioServiceShuffleMode.none,
        repeatMode: switch (player.loopMode) {
          LoopMode.off => AudioServiceRepeatMode.none,
          LoopMode.one => AudioServiceRepeatMode.one,
          LoopMode.all => AudioServiceRepeatMode.all,
        },
      ),
    );
  }
}
