import 'dart:async';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';

import '../data/subsonic/models.dart';
import 'crossfade.dart';
import 'past_queues.dart';
import 'playback_controller.dart';
import 'prefetch_cache.dart';
import 'stream_offset.dart';
import 'stable_shuffle_order.dart';

/// What the handler needs from the session: where each track's audio and artwork are, and where to report plays.
abstract class PlaybackSource {
  Future<String?> localPath(String trackId);
  Uri streamUri(Track track);

  /// The stream of [track] starting at [offset], when the server can start a transcoded stream there. Null for original files and for servers without that ability, which the player then seeks itself.
  Uri? streamUriFrom(Track track, Duration offset);

  /// Asks the server how [tracks] should reach this device, so that [streamUri] gives the stream it chose. Without an answer, [streamUri] keeps to the `stream` endpoint.
  Future<void> decide(List<Track> tracks);

  /// The file of [track] among the songs fetched ahead, when there is one.
  Future<String?> cachedPath(Track track);

  /// Fetches [upcoming], the song that plays and the next songs of the queue, ahead of playback, and calls [ready] with the file of each. [progress] receives the part of each song fetched so far, from 0 to 1, when the server tells its size. Files of the songs in [keep] stay in the cache; [removed] receives the names of the files deleted to make room.
  Future<void> prefetch(
    List<Track> upcoming, {
    required Set<Track> keep,
    required void Function(Track track, String path) ready,
    required void Function(Set<String> fileNames) removed,
    void Function(Track track, double fraction)? progress,
  });

  /// The artwork of [coverArt] as a local file, when it is at hand.
  Uri? artUri(String? coverArt);

  /// Fetches the artwork of [coverArt] to a local file and returns it, or null when it cannot be fetched.
  Future<Uri?> fetchArt(String? coverArt);
  Future<void> nowPlaying(Track track);
  Future<void> played(Track track);

  /// The volume from 0 to 1 at which [track] plays, for loudness normalisation.
  double volumeFor(Track track);

  /// How long one song fades into the next; zero plays them back to back.
  Duration get crossfade;
}

/// Plays on the phone through just_audio and reports to the system media controls through audio_service.
class PlayerHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  PlayerHandler() {
    _init();
  }

  final player = _newPlayer();
  PlaybackSource? source;

  /// Receives the queue that [playTracks] replaces, so it can be played again later.
  void Function(PastQueue queue)? onReplaced;

  List<Track> _tracks = const [];
  String? _scrobbled;

  /// The player of the incoming song during a crossfade, made on the first fade.
  AudioPlayer? _incoming;
  Timer? _fadeTimer;
  Timer? _fadeStart;

  /// Completes when the volumes have crossed, or when the fade is cancelled.
  Completer<void>? _faded;

  /// A crossfade runs, from the start of the incoming song until the main player has taken it over.
  bool _fading = false;

  /// The main player is taking over the incoming song, so its volume stays down until then.
  bool _handingOver = false;

  /// The shuffle order of the queue, which keeps a song in place when its cached file replaces its stream.
  StableShuffleOrder _order = StableShuffleOrder();

  /// Counts the queues loaded, so a prefetch for an earlier queue changes nothing.
  int _generation = 0;

  /// Changes of the queue run one after the other, so replacing a stream by its cached file never interleaves with an edit.
  Future<void> _edits = Future.value();

  /// The queue [_lastIndex] belongs to.
  int _indexGeneration = -1;

  /// A stream is being replaced by its file, or back: the player reports index changes that are not song changes.
  bool _swapping = false;

  /// The last index the player reported. While it seeks, some backends report no index for a moment, which must not make the current track unknown.
  int? _lastIndex;

  /// Where the stream of the current song starts within the song. Zero unless a seek restarted a transcoded stream on the server.
  Duration _offset = Duration.zero;

  /// How much of the current song is on this device, by [loadedPart]. It changes twice a second while the song loads, so it stays out of [playbackState], each change of which goes to the system media controls.
  Duration get buffered => _buffered;
  Duration _buffered = Duration.zero;
  Stream<Duration> get bufferedChanges => _bufferedChanges.stream;
  final _bufferedChanges = StreamController<Duration>.broadcast();

  /// The part of each song fetched to the cache so far, by track ID, for the songs of the last [_prefetch].
  final _fetched = <String, double>{};

  /// Works out [buffered] again and reports a change.
  Duration _updateBuffered() {
    final index = player.currentIndex;
    final duration = player.duration;
    final Duration value;
    if (index == null || index >= _tracks.length || duration == null) {
      value = player.bufferedPosition + _offset;
    } else {
      value = loadedPart(
        duration: duration + _offset,
        buffered: player.bufferedPosition + _offset,
        fromFile: !_streams(index),
        fetched: _fetched[_tracks[index].id] ?? 0,
      );
    }
    if (value != _buffered) {
      _buffered = value;
      _bufferedChanges.add(value);
    }
    return value;
  }

  /// The offset the current song starts with after a queue loads, for the index the player reports first.
  ({int index, Duration offset})? _startOffset;

  /// The position in the current song. The player counts from the start of its stream, which is [_offset] into the song.
  Duration get position => player.position + _offset;

  /// The tracks of the queue, in queue order.
  List<Track> get tracks => _tracks;

  Track? get currentTrack {
    final index = player.currentIndex ?? _lastIndex;
    return index == null || index >= _tracks.length ? null : _tracks[index];
  }

  Future<void> _init() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());

    player.playbackEventStream.listen((event) {
      if (!_swapping) _broadcastState(event);
    }, onError: (Object _, StackTrace _) {});
    player.playingStream.listen((_) => _broadcastState(player.playbackEvent));
    player.currentIndexStream.listen((index) {
      if (_swapping || index == null || index >= _tracks.length) return;
      // A replacement before the current song shifts the index for a moment; only the index the player holds now counts, and only once per queue.
      if (index != player.currentIndex) return;
      if (index == _lastIndex && _generation == _indexGeneration) return;
      _indexGeneration = _generation;
      _lastIndex = index;
      _offset = _startOffset?.index == index
          ? _startOffset!.offset
          : Duration.zero;
      _startOffset = null;
      _restoreStreams();
      _prefetch();
      mediaItem.add(queue.value[index]);
      final track = _tracks[index];
      if (queue.value[index].artUri == null) unawaited(_fetchArt(index));
      if (!_handingOver) player.setVolume(source?.volumeFor(track) ?? 1);
      source?.nowPlaying(track);
      _scrobbled = null;
    });
    // A play counts once half of the track, or four minutes, has played. The position comes once a second, which keeps the phone asleep between ticks while the screen is off.
    player
        .createPositionStream(
          minPeriod: const Duration(seconds: 1),
          maxPeriod: const Duration(seconds: 1),
        )
        .listen((position) {
          _maybeCrossfade(position);
          final track = currentTrack;
          if (track == null || _scrobbled == track.id) return;
          // A stream that restarted part-way is shorter than the song, so it is measured against the song.
          final duration = _offset > Duration.zero
              ? track.duration
              : player.duration ?? track.duration;
          if (countsAsPlayed(position + _offset, duration)) {
            _scrobbled = track.id;
            source?.played(track);
          }
        });
  }

  Future<AudioSource> _audioSource(Track track) async {
    final path =
        await source?.localPath(track.id) ?? await source?.cachedPath(track);
    if (path != null) return AudioSource.file(path, tag: track.id);
    return AudioSource.uri(source!.streamUri(track), tag: track.id);
  }

  /// The source of [track] for starting at [position], with the point of the song its stream starts at. A transcoded stream starts on the server at [position], since the player cannot seek in it; anything else starts at its beginning and the player seeks.
  Future<(AudioSource, Duration)> _sourceFrom(
    Track track,
    Duration position,
  ) async {
    final normal = await _audioSource(track);
    if (position < const Duration(seconds: 2) ||
        normal is! UriAudioSource ||
        normal.uri.scheme == 'file') {
      return (normal, Duration.zero);
    }
    final uri = source?.streamUriFrom(track, position);
    return uri == null
        ? (normal, Duration.zero)
        : (AudioSource.uri(uri, tag: track.id), position);
  }

  /// Puts the ordinary stream back in the entries that restarted part-way, once their song is no longer the current one, so they play from their beginning when their turn comes again.
  void _restoreStreams() {
    final sources = player.audioSources;
    for (var i = 0; i < sources.length && i < _tracks.length; i++) {
      final s = sources[i];
      if (s is! UriAudioSource ||
          !startsPartWay(s.uri) ||
          i == player.currentIndex) {
        continue;
      }
      final id = _tracks[i].id;
      final generation = _generation;
      unawaited(
        _serial(() async {
          if (generation != _generation) return;
          for (var j = 0; j < _tracks.length; j++) {
            final entry = player.audioSources[j];
            if (_tracks[j].id != id ||
                j == player.currentIndex ||
                entry is! UriAudioSource ||
                !startsPartWay(entry.uri)) {
              continue;
            }
            final plain = await _audioSource(_tracks[j]);
            _swapping = true;
            try {
              _order.replacing(j);
              await player.removeAudioSourceAt(j);
              await player.insertAudioSource(j, plain);
            } on Exception {
              // The entry keeps its stream.
            } finally {
              _swapping = false;
            }
          }
        }),
      );
    }
  }

  /// Starts the stream of the current song again at [position] on the server, since the player cannot seek there in a transcoded stream.
  Future<void> _restartAt(int index, Track track, Duration position) =>
      _serial(() async {
        final uri = source?.streamUriFrom(track, position);
        if (uri == null || player.currentIndex != index) return;
        final wasPlaying = player.playing;
        _swapping = true;
        try {
          // Paused meanwhile, so the song after it never sounds while the entry is replaced.
          await player.pause();
          _order.replacing(index);
          await player.removeAudioSourceAt(index);
          await player.insertAudioSource(
            index,
            AudioSource.uri(uri, tag: track.id),
          );
          await player.seek(Duration.zero, index: index);
          _offset = position;
        } on Exception {
          // The song carries on from where the player is.
        } finally {
          _swapping = false;
        }
        _broadcastState(player.playbackEvent);
        // The future of play() ends with the playback, so it is not awaited.
        if (wasPlaying) unawaited(player.play());
      });

  Future<T> _serial<T>(Future<T> Function() edit) {
    final result = _edits.then((_) => edit());
    _edits = result.then((_) {}, onError: (Object _) {});
    return result;
  }

  /// Loads [sources] as a new queue with a fresh shuffle order.
  Future<void> _load(
    List<AudioSource> sources, {
    int? initialIndex,
    Duration? initialPosition,
  }) async {
    _generation++;
    _order = StableShuffleOrder();
    await player.setAudioSources(
      sources,
      initialIndex: initialIndex,
      initialPosition: initialPosition,
      shuffleOrder: _order,
    );
  }

  bool _streams(int index) {
    final sources = player.audioSources;
    if (index >= sources.length) return false;
    final s = sources[index];
    return s is UriAudioSource && s.uri.scheme != 'file';
  }

  /// Fetches the song that plays and the next songs to the cache, and plays each of the next songs from its file once it is there. The song that plays keeps its stream, which a switch would interrupt; its file serves when it plays again, and shows how much of it is on this device.
  void _prefetch() {
    final src = source;
    final current = player.currentIndex;
    if (src == null || current == null || current >= _tracks.length) return;
    final order = player.effectiveIndices;
    final next = upcomingIndices(
      order,
      current,
      loop: player.loopMode == LoopMode.all,
    ).where((i) => i < _tracks.length).toList();
    final at = order.indexOf(current);
    final recent = order
        .sublist(
          (at - recentlyPlayedKept).clamp(0, order.length),
          at.clamp(0, order.length),
        )
        .where((i) => i < _tracks.length);
    final generation = _generation;
    unawaited(() async {
      // The server decides how the current song and those ahead reach this device before they are fetched.
      await _decide([_tracks[current], for (final i in next) _tracks[i]]);
      if (generation != _generation) return;
      _upgradeStreams(generation, next);
      final fetched = [
        for (final i in [current, ...next])
          if (_streams(i)) _tracks[i],
      ];
      final ids = {for (final t in fetched) t.id};
      _fetched.removeWhere((id, _) => !ids.contains(id));
      await src
          .prefetch(
            fetched,
            keep: {
              _tracks[current],
              for (final i in next) _tracks[i],
              for (final i in recent) _tracks[i],
            },
            ready: (track, path) {
              _fetched[track.id] = 1;
              _updateBuffered();
              unawaited(
                _replace(
                  generation,
                  track.id,
                  toFile: true,
                  source: AudioSource.file(path, tag: track.id),
                ),
              );
            },
            removed: cachedFilesRemoved,
            progress: (track, fraction) {
              _fetched[track.id] = fraction;
              if (track.id == currentTrack?.id) _updateBuffered();
            },
          )
          .catchError((Object _) {});
    }());
  }

  /// Asks the server how [tracks] reach this device, waiting no more than a few seconds before the songs stream from the `stream` endpoint.
  Future<void> _decide(List<Track> tracks) async {
    try {
      await source?.decide(tracks).timeout(const Duration(seconds: 5));
    } on Exception {
      // The songs stream as they would without the answer.
    }
  }

  /// Gives the queue entries at [indices] the stream the server chose, where it differs from the one they have.
  void _upgradeStreams(int generation, Iterable<int> indices) {
    final src = source;
    if (src == null) return;
    for (final i in indices) {
      if (!_streams(i)) continue;
      final entry = player.audioSources[i] as UriAudioSource;
      final track = _tracks[i];
      final uri = src.streamUri(track);
      if (uri == entry.uri) continue;
      unawaited(
        _replace(
          generation,
          track.id,
          toFile: false,
          source: AudioSource.uri(uri, tag: track.id),
        ),
      );
    }
  }

  /// Songs of the queue whose cached files were deleted stream again.
  void cachedFilesRemoved(Set<String> fileNames) {
    final src = source;
    if (src == null) return;
    final sources = player.audioSources;
    for (var i = 0; i < sources.length && i < _tracks.length; i++) {
      final s = sources[i];
      if (s is! UriAudioSource || s.uri.scheme != 'file') continue;
      if (!fileNames.contains(s.uri.pathSegments.last)) continue;
      final track = _tracks[i];
      unawaited(
        _replace(
          _generation,
          track.id,
          toFile: false,
          source: AudioSource.uri(src.streamUri(track), tag: track.id),
        ),
      );
    }
  }

  /// Replaces the queue entries of [trackId] other than the current song: its stream by its cached file when [toFile], its cached file by its stream otherwise.
  Future<void> _replace(
    int generation,
    String trackId, {
    required bool toFile,
    required AudioSource source,
  }) => _serial(() async {
    if (generation != _generation || _fading) return;
    for (var i = 0; i < _tracks.length; i++) {
      if (_tracks[i].id != trackId || i == player.currentIndex) continue;
      if (_streams(i) != toFile) continue;
      _swapping = true;
      try {
        _order.replacing(i);
        await player.removeAudioSourceAt(i);
        await player.insertAudioSource(i, source);
      } on Exception {
        // The entry keeps its previous source.
      } finally {
        _swapping = false;
      }
    }
  });

  /// Fetches the artwork of the song at [index] for the system media controls, and shows it if the song still plays and its queue is the same.
  Future<void> _fetchArt(int index) async {
    final generation = _generation;
    final uri = await source?.fetchArt(_tracks[index].coverArt);
    if (uri == null || generation != _generation) return;
    if (player.currentIndex != index || index >= queue.value.length) return;
    final item = queue.value[index].copyWith(artUri: uri);
    queue.add([...queue.value]..[index] = item);
    mediaItem.add(item);
  }

  MediaItem _mediaItem(Track track) => MediaItem(
    id: track.id,
    title: track.title,
    album: track.album,
    artist: track.artist,
    duration: track.duration,
    artUri: source?.artUri(track.coverArt),
  );

  /// Starts a crossfade once the current song is within the crossfade of its end, when the next song may fade in: not the same album, not repeating one song.
  void _maybeCrossfade(Duration position) {
    final fade = source?.crossfade ?? Duration.zero;
    if (fade == Duration.zero || _fading || !player.playing) return;
    if (player.loopMode == LoopMode.one) return;
    final index = player.currentIndex, next = player.nextIndex;
    final duration = player.duration;
    if (index == null || next == null || duration == null) return;
    if (index >= _tracks.length || next >= _tracks.length) return;
    final remaining = duration - position;
    // Too close to the end, a fade could not finish before the song does.
    if (remaining < const Duration(seconds: 1)) return;
    if (!crossfades(_tracks[index], _tracks[next])) return;
    if (remaining > fade) {
      // The fade is due before the next position arrives, so a timer starts it on time. Each call checks again, so a pause or a seek in between leaves the fade out.
      final wait = remaining - fade;
      if (wait < const Duration(milliseconds: 1500)) {
        _fadeStart?.cancel();
        _fadeStart = Timer(wait, () => _maybeCrossfade(player.position));
      }
      return;
    }
    unawaited(_crossfade(index, next, remaining));
  }

  Future<void> _crossfade(int index, int next, Duration remaining) async {
    _fading = true;
    final from = _tracks[index], to = _tracks[next];
    final fromVolume = source?.volumeFor(from) ?? 1;
    final toVolume = source?.volumeFor(to) ?? 1;
    final incoming = _incoming ??= _newPlayer();
    try {
      await incoming.setVolume(0);
      await incoming.setAudioSource(await _audioSource(to));
      if (!_fading) return;
      unawaited(incoming.play());
      // The fade ends a little before the outgoing song does, so the main player never runs into the next song by itself.
      final span = remaining - const Duration(milliseconds: 400);
      final start = DateTime.now();
      final faded = _faded = Completer<void>();
      _fadeTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
        final t =
            DateTime.now().difference(start).inMilliseconds /
            span.inMilliseconds;
        final (out, into) = crossfadeVolumes(t);
        player.setVolume(fromVolume * out);
        incoming.setVolume(toVolume * into);
        if (t >= 1) {
          timer.cancel();
          if (!faded.isCompleted) faded.complete();
        }
      });
      await faded.future;
      if (!_fading) return;
      // The main player takes over the incoming song where it is, silently, then the two swap.
      _handingOver = true;
      await player.setVolume(0);
      await player.seek(incoming.position, index: next);
      await _ready();
      await player.seek(incoming.position);
      await _ready();
      if (!_fading) return;
      await player.setVolume(toVolume);
      await incoming.stop();
    } on Exception {
      // A failed fade leaves the songs to follow each other without one.
    } finally {
      _endCrossfade();
    }
  }

  Future<void> _ready() async {
    try {
      await player.processingStateStream
          .firstWhere((s) => s == ProcessingState.ready)
          .timeout(const Duration(seconds: 5));
    } on TimeoutException {
      // The player stays where it is.
    }
  }

  void _endCrossfade() {
    _fading = false;
    _handingOver = false;
    _fadeTimer?.cancel();
    _fadeTimer = null;
    if (_faded case final faded? when !faded.isCompleted) faded.complete();
    _faded = null;
  }

  /// Stops a running crossfade, for a pause, a seek or a skip: the incoming song stops and the current one plays at its own volume.
  void _cancelCrossfade() {
    _fadeStart?.cancel();
    if (!_fading) return;
    _endCrossfade();
    unawaited(_incoming?.stop());
    final track = currentTrack;
    unawaited(
      player.setVolume(track == null ? 1 : source?.volumeFor(track) ?? 1),
    );
  }

  Future<void> playTracks(
    List<Track> tracks, {
    int index = 0,
    bool shuffle = false,
  }) async {
    if (tracks.isEmpty || source == null) return;
    _cancelCrossfade();
    if (_tracks.isNotEmpty && !_sameSongs(_tracks, tracks)) {
      onReplaced?.call(
        PastQueue(
          List.of(_tracks),
          player.currentIndex ?? 0,
          position,
          DateTime.now(),
        ),
      );
    }
    _tracks = List.of(tracks);
    queue.add([for (final t in _tracks) _mediaItem(t)]);
    // The shuffle order of just_audio starts with the initial index, so a shuffled queue starts at a random song.
    final start = shuffle ? Random().nextInt(_tracks.length) : index;
    if (start < _tracks.length) await _decide([_tracks[start]]);
    final sources = await Future.wait(_tracks.map(_audioSource));
    await player.setShuffleModeEnabled(shuffle);
    await _serial(
      () => _load(sources, initialIndex: start, initialPosition: Duration.zero),
    );
    _prefetch();
    await player.play();
  }

  /// Loads a saved queue paused at [position] of track [index].
  Future<void> restore(List<Track> tracks, int index, Duration position) async {
    if (tracks.isEmpty || source == null) return;
    _cancelCrossfade();
    _tracks = List.of(tracks);
    queue.add([for (final t in _tracks) _mediaItem(t)]);
    if (index < _tracks.length) await _decide([_tracks[index]]);
    final sources = await Future.wait(_tracks.map(_audioSource));
    final start = await _startingAt(sources, index, position);
    await _serial(
      () => _load(sources, initialIndex: index, initialPosition: start),
    );
    _prefetch();
  }

  /// Swaps the source at [index] for one that starts at [position] when the player cannot seek there, and returns where the player itself starts.
  Future<Duration> _startingAt(
    List<AudioSource> sources,
    int index,
    Duration position,
  ) async {
    if (index >= sources.length || index >= _tracks.length) return position;
    final (from, offset) = await _sourceFrom(_tracks[index], position);
    if (offset == Duration.zero) return position;
    sources[index] = from;
    _startOffset = (index: index, offset: offset);
    return Duration.zero;
  }

  /// Builds the audio sources of the queue again, for example after the streaming quality changed, and carries on from the same song and position. A song that was playing keeps playing.
  Future<void> reloadSources() async {
    final index = player.currentIndex;
    if (_tracks.isEmpty || source == null || index == null) return;
    _cancelCrossfade();
    final position = this.position;
    final playing = player.playing;
    if (index < _tracks.length) await _decide([_tracks[index]]);
    final sources = await Future.wait(_tracks.map(_audioSource));
    final start = await _startingAt(sources, index, position);
    await _serial(
      () => _load(sources, initialIndex: index, initialPosition: start),
    );
    _prefetch();
    if (playing) await player.play();
  }

  /// Replaces the songs after the current one with [tracks]. The current entry stays, so its song plays on, and the songs before it stay. The queue it replaces goes to the past queues when songs followed the current one.
  Future<void> replaceUpcoming(List<Track> tracks) async {
    if (_tracks.isEmpty || player.currentIndex == null) {
      return playTracks(tracks);
    }
    _cancelCrossfade();
    final sources = await Future.wait(tracks.map(_audioSource));
    final kept = await _serial(() async {
      final at = player.currentIndex;
      if (at == null || at >= _tracks.length) return false;
      if (at + 1 < _tracks.length) {
        onReplaced?.call(
          PastQueue(List.of(_tracks), at, position, DateTime.now()),
        );
      }
      _swapping = true;
      try {
        final count = player.audioSources.length;
        if (at + 1 < count) await player.removeAudioSourceRange(at + 1, count);
        if (sources.isNotEmpty) await player.addAudioSources(sources);
      } finally {
        _swapping = false;
      }
      _tracks = [..._tracks.take(at + 1), ...tracks];
      // The entries up to the current one keep the artwork fetched for them.
      queue.add([
        ...queue.value.take(at + 1),
        for (final t in tracks) _mediaItem(t),
      ]);
      return true;
    });
    if (!kept) return playTracks(tracks);
    _broadcastState(player.playbackEvent);
    _prefetch();
  }

  Future<void> playNext(List<Track> tracks) async {
    if (_tracks.isEmpty) return playTracks(tracks);
    final sources = [for (final t in tracks) await _audioSource(t)];
    await _serial(() async {
      var insertAt = (player.currentIndex ?? -1) + 1;
      for (final (i, t) in tracks.indexed) {
        await player.insertAudioSource(insertAt, sources[i]);
        _tracks.insert(insertAt, t);
        insertAt++;
      }
      queue.add([for (final t in _tracks) _mediaItem(t)]);
    });
    _prefetch();
  }

  Future<void> addTracks(List<Track> tracks) async {
    if (_tracks.isEmpty) return playTracks(tracks);
    final sources = [for (final t in tracks) await _audioSource(t)];
    await _serial(() async {
      for (final (i, t) in tracks.indexed) {
        await player.addAudioSource(sources[i]);
        _tracks.add(t);
      }
      queue.add([for (final t in _tracks) _mediaItem(t)]);
    });
    _prefetch();
  }

  @override
  Future<void> removeQueueItemAt(int index) async {
    await _serial(() async {
      await player.removeAudioSourceAt(index);
      _tracks.removeAt(index);
      queue.add([for (final t in _tracks) _mediaItem(t)]);
    });
    _prefetch();
  }

  Future<void> moveQueueItem(int from, int to) async {
    await _serial(() async {
      await player.moveAudioSource(from, to);
      _tracks.insert(to, _tracks.removeAt(from));
      queue.add([for (final t in _tracks) _mediaItem(t)]);
    });
    _prefetch();
  }

  @override
  Future<void> play() => player.play();

  @override
  Future<void> pause() {
    _cancelCrossfade();
    return player.pause();
  }

  @override
  Future<void> seek(Duration position) {
    _cancelCrossfade();
    final index = player.currentIndex;
    final track = currentTrack;
    if (index != null &&
        track != null &&
        _streams(index) &&
        restartsStream(
          target: position,
          offset: _offset,
          buffered: player.bufferedPosition,
          restartable: source?.streamUriFrom(track, position) != null,
        )) {
      return _restartAt(index, track, position);
    }
    final inStream = position - _offset;
    return player.seek(inStream.isNegative ? Duration.zero : inStream);
  }

  @override
  Future<void> skipToNext() {
    _cancelCrossfade();
    return player.seekToNext();
  }

  @override
  Future<void> skipToPrevious() async {
    _cancelCrossfade();
    if (position > const Duration(seconds: 3)) return seek(Duration.zero);
    return player.seekToPrevious();
  }

  @override
  Future<void> skipToQueueItem(int index) {
    _cancelCrossfade();
    return player.seek(Duration.zero, index: index);
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    final enabled = shuffleMode != AudioServiceShuffleMode.none;
    if (enabled) await player.shuffle();
    await player.setShuffleModeEnabled(enabled);
    _prefetch();
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
    _cancelCrossfade();
    await player.stop();
    await _serial(() async {
      _generation++;
      await player.clearAudioSources();
    });
    _tracks = const [];
    queue.add(const []);
    mediaItem.add(null);
    await super.stop();
  }

  void _broadcastState(PlaybackEvent event) {
    final buffered = _updateBuffered();
    final playing = player.playing;
    final previous = playbackState.value;
    final next = previous.copyWith(
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
      updatePosition: position,
      bufferedPosition: buffered,
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
    );
    if (!sameState(previous, next)) playbackState.add(next);
  }
}

/// ExoPlayer loads 50 seconds ahead, but stops at 13 MB by default: enough for 50 seconds of a CD-quality FLAC, about 20 seconds of a 24-bit one at 192 kHz. The larger cap keeps 50 seconds of either.
AudioPlayer _newPlayer() => AudioPlayer(
  audioLoadConfiguration: const AudioLoadConfiguration(
    androidLoadControl: AndroidLoadControl(targetBufferBytes: 64 << 20),
  ),
);

bool _sameSongs(List<Track> a, List<Track> b) =>
    a.length == b.length &&
    Iterable.generate(a.length).every((i) => a[i].id == b[i].id);

/// How much of a song of [duration] is on this device: all of it when it plays from a file, a download or a song fetched ahead; otherwise the further of what the player has [buffered] and the part of the song [fetched] to the cache, from 0 to 1.
Duration loadedPart({
  required Duration duration,
  required Duration buffered,
  required bool fromFile,
  double fetched = 0,
}) {
  if (fromFile) return duration;
  final cached = duration * fetched.clamp(0.0, 1.0);
  return cached > buffered ? cached : buffered;
}

/// Whether [next] says nothing that [previous] does not: the same state, with a position where [previous] puts it by now. The player reports each change of the loaded part, which the system media controls do not need.
bool sameState(PlaybackState previous, PlaybackState next) =>
    previous.processingState == next.processingState &&
    previous.playing == next.playing &&
    previous.speed == next.speed &&
    previous.queueIndex == next.queueIndex &&
    previous.shuffleMode == next.shuffleMode &&
    previous.repeatMode == next.repeatMode &&
    previous.errorMessage == next.errorMessage &&
    (previous.position - next.updatePosition).abs() <
        const Duration(milliseconds: 200);
