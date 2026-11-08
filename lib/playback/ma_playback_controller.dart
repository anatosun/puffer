import 'dart:async';

import '../data/music_assistant/ma_client.dart';
import '../data/music_assistant/ma_models.dart';
import '../data/subsonic/models.dart';
import 'playback_controller.dart';

/// Plays on a Music Assistant player. Music Assistant fetches the audio from the Subsonic server and sends it to the speakers.
///
/// With [providerInstance] (the instance ID of the OpenSubsonic provider of Music Assistant for the same server), tracks are sent as Music Assistant URIs. Otherwise they are sent as Subsonic stream URLs.
class MusicAssistantPlaybackController implements PlaybackController {
  MusicAssistantPlaybackController(
    this.client,
    this.playerId, {
    this.providerInstance,
    required this.streamUri,
    this.onError,
    this.lookupTrack,
    this.thisDevice = false,
    this.startTimeout = const Duration(seconds: 20),
  }) {
    _subscriptions = [
      client.queuesStream.listen((_) => _emit()),
      client.playersStream.listen((_) => _emit()),
      client.events.listen((e) {
        if (e.event == 'queue_items_updated' && e.objectId == playerId) {
          _loadItems();
        }
      }),
    ];
    _loadItems();
  }

  final MusicAssistantClient client;
  final String playerId;
  final String? providerInstance;
  final Uri Function(Track) streamUri;

  /// The player is this phone as a Sendspin speaker, so the player shows as it does for local playback: without a speaker name or a volume slider.
  final bool thisDevice;

  /// Receives failures of transport commands (play, pause, seek, …), which buttons call without awaiting.
  final void Function(Object error)? onError;

  /// Loads a Subsonic track by ID, for queue items added by other Music Assistant clients.
  final Future<Track?> Function(String id)? lookupTrack;

  late final List<StreamSubscription<Object?>> _subscriptions;
  final _controller = StreamController<NowPlaying?>.broadcast();
  final _known = <String, Track>{};

  /// The Subsonic track found for each queue item. Music Assistant sometimes describes the current item without its provider mappings, for example while it restarts the stream after a seek, and the item keeps its track meanwhile.
  final _byQueueItem = <String, Track>{};

  /// IDs looked up through [lookupTrack], each once.
  final _resolving = <String>{};

  /// The lookups run one after the other, the current item first, so a long queue does not send its requests all at once.
  Future<void> _lookups = Future.value();
  List<Track> _sent = const [];
  List<MaQueueItem> _items = const [];
  NowPlaying? _current;

  /// How long a player may take to start before the person is told it did not.
  final Duration startTimeout;

  /// The song asked to play (null under shuffle, where Music Assistant picks it) and its index, shown as loading until the player plays it. A player can take seconds to start, and without this the screen would keep showing the previous song with nothing happening.
  ({Track? track, int index})? _pending;
  Timer? _pendingTimeout;

  @override
  NowPlaying? get current => _current ?? _build();

  @override
  Stream<NowPlaying?> get state async* {
    yield current;
    yield* _controller.stream;
  }

  MaQueue? get _queue => client.queues[playerId];
  MaPlayer? get _player => client.players[playerId];

  Future<void> _loadItems() async {
    try {
      _items = await client.queueItems(playerId);
      _emit();
    } on MaException {
      // Retried on the next queue_items_updated event.
    }
  }

  void _emit() {
    // Queue items can arrive after the controller is replaced, as when the output changes.
    if (_controller.isClosed) return;
    _current = _build();
    _controller.add(_current);
  }

  /// The Subsonic ID of [item], from the provider mapping or from the stream URL it was sent as.
  String? _subsonicId(MaQueueItem item) =>
      (providerInstance == null ? null : item.itemIdAt(providerInstance!)) ??
      item.streamId;

  /// The Subsonic track of [item]. With [resolve], an unknown track is looked up and the state rebuilt once it arrives.
  Track? _trackFor(MaQueueItem item, int? index, {bool resolve = false}) {
    final track = _findTrack(item, index, resolve: resolve);
    if (track != null) return _byQueueItem[item.id] = track;
    return _byQueueItem[item.id];
  }

  Track? _findTrack(MaQueueItem item, int? index, {required bool resolve}) {
    final id = _subsonicId(item);
    if (id != null) {
      final known = _known[id];
      if (known != null) return known;
      if (resolve) _resolve(id);
    }
    // Without an ID, the queue order is the order the tracks were sent in.
    if (index != null &&
        index < _sent.length &&
        _items.length == _sent.length) {
      return _sent[index];
    }
    return null;
  }

  /// Loads a track that another client or an earlier session put in the queue, then rebuilds the state with it.
  void _resolve(String id) {
    final lookup = lookupTrack;
    if (lookup == null || !_resolving.add(id)) return;
    _lookups = _lookups.then((_) async {
      if (_controller.isClosed) return;
      final track = await lookup(id);
      if (track == null) return;
      _known[id] = track;
      _emit();
    });
  }

  NowPlaying? _build() {
    final reported = _buildReported();
    final pending = _pending;
    if (pending == null) return reported;
    final started =
        reported != null &&
        reported.playing &&
        (pending.track == null || reported.track?.id == pending.track!.id);
    if (started) {
      _clearPending();
      return reported;
    }
    return _pendingState(pending);
  }

  /// The song asked to play, as loading, with the queue that was sent.
  NowPlaying _pendingState(({Track? track, int index}) pending) {
    final track = pending.track;
    return NowPlaying(
      track: track,
      title: track?.title ?? 'Starting…',
      artist: track?.artist,
      album: track?.album,
      coverArt: track?.coverArt,
      duration: track?.duration ?? Duration.zero,
      positionAt: DateTime.now(),
      buffering: true,
      queue: [
        for (final (i, t) in _sent.indexed)
          QueueEntry(
            id: 'pending-$i',
            trackId: t.id,
            title: t.title,
            artist: t.artist,
            coverArt: t.coverArt,
          ),
      ],
      index: track == null ? null : pending.index,
      outputName: thisDevice ? null : _player?.name ?? playerId,
      volume: thisDevice ? null : _player?.sliderVolume,
    );
  }

  void _startPending(Track? track, int index) {
    _pendingTimeout?.cancel();
    _pending = (track: track, index: index);
    _pendingTimeout = Timer(startTimeout, () {
      if (_pending == null) return;
      _pending = null;
      onError?.call(MaStartTimeout(_player?.name ?? playerId));
      _emit();
    });
    _emit();
  }

  /// Ends the wait for the start and shows what the player reports.
  void _settlePending() {
    if (_pending == null) return;
    _clearPending();
    _emit();
  }

  void _clearPending() {
    _pendingTimeout?.cancel();
    _pendingTimeout = null;
    _pending = null;
  }

  /// What Music Assistant reports for the queue.
  NowPlaying? _buildReported() {
    final queue = _queue;
    final index = queue?.currentIndex;
    // A paused queue stays on screen. Many players report idle rather than paused, and some events leave out the current item, which the loaded items still have.
    final item =
        queue?.currentItem ??
        (index != null && index < _items.length ? _items[index] : null);
    if (queue == null || item == null) return null;
    final track = _trackFor(item, index, resolve: true);
    final now = DateTime.now();
    return NowPlaying(
      track: track,
      title: track?.title ?? item.title,
      artist: track?.artist ?? item.artist,
      album: track?.album ?? item.album,
      // Images of the OpenSubsonic provider carry the Subsonic cover art id as their path.
      coverArt:
          track?.coverArt ??
          (item.image != null && item.image!.provider == providerInstance
              ? item.image!.path
              : null),
      imageUrl: item.image?.url(client.baseUrl),
      duration: track?.duration ?? item.duration,
      position: queue.position(now),
      positionAt: now,
      playing: queue.state == MaPlaybackState.playing,
      shuffle: queue.shuffle,
      repeat: switch (queue.repeat) {
        MaRepeatMode.off => Repeat.off,
        MaRepeatMode.one => Repeat.one,
        MaRepeatMode.all => Repeat.all,
      },
      queue: [
        for (final (i, it) in _items.indexed)
          _entry(it, _trackFor(it, i, resolve: true)),
      ],
      index: queue.currentIndex,
      outputName: thisDevice ? null : _player?.name ?? playerId,
      volume: thisDevice ? null : _player?.sliderVolume,
      autoplay: queue.autoplay,
    );
  }

  /// The row of [item] in the queue, from its Subsonic [track] when there is one.
  QueueEntry _entry(MaQueueItem item, Track? track) => QueueEntry(
    id: item.id,
    trackId: track?.id,
    title: track?.title ?? item.title,
    artist: track?.artist ?? item.artist,
    coverArt:
        track?.coverArt ??
        (item.image != null && item.image!.provider == providerInstance
            ? item.image!.path
            : null),
    imageUrl: item.image?.url(client.baseUrl, size: 160),
  );

  String _media(Track t) => providerInstance != null
      ? '$providerInstance://track/${t.id}'
      : streamUri(t).toString();

  void _remember(List<Track> tracks) {
    for (final t in tracks) {
      _known[t.id] = t;
    }
  }

  Future<void> _queueCommand(String command, [MaJson args = const {}]) =>
      client.command('player_queues/$command', {'queue_id': playerId, ...args});

  Future<void> _control(Future<void> command) async {
    try {
      await command;
    } on MaException catch (e) {
      onError?.call(e);
    }
  }

  @override
  Future<void> playTracks(
    List<Track> tracks, {
    int index = 0,
    bool shuffle = false,
  }) async {
    if (tracks.isEmpty) return;
    _remember(tracks);
    _sent = List.of(tracks);
    final media = tracks.map(_media).toList();
    final start = index.clamp(0, tracks.length - 1);
    _startPending(shuffle ? null : tracks[start], start);
    try {
      await _sendPlay(media, start, shuffle);
    } catch (_) {
      _clearPending();
      _emit();
      rethrow;
    }
  }

  Future<void> _sendPlay(List<String> media, int index, bool shuffle) async {
    if (index == 0 || shuffle) {
      await _queueCommand('play_media', {
        'media': media,
        'option': 'replace',
        'shuffle': shuffle,
      });
      return;
    }
    // Music Assistant applies `start_item` only to an album, playlist or genre it expands itself; with a list of tracks it ignores it, and `replace` always starts at the first item. So the queue is emptied, filled with `add`, which never starts playback, and started at the chosen song. The songs before it stay in the queue, as on the phone.
    await _queueCommand('clear');
    await _queueCommand('play_media', {
      'media': media,
      'option': 'add',
      'shuffle': false,
    });
    await _queueCommand('play_index', {'index': index});
  }

  /// Music Assistant cannot change the queue up to the song playing, which the player has buffered, without restarting it; so only what follows the song is replaced, in one step, and the songs played before it stay.
  @override
  Future<void> continueWith(List<Track> tracks, int index) async {
    _remember(tracks);
    final after = tracks.sublist(index + 1);
    final current = _queue?.currentIndex;
    if (after.isEmpty) {
      // Nothing follows the song: the songs queued after it go.
      final upcoming = current == null
          ? const <MaQueueItem>[]
          : _items.skip(current + 1).toList();
      for (final item in upcoming) {
        await _queueCommand('delete_item', {'item_id_or_index': item.id});
      }
    } else {
      await _queueCommand('play_media', {
        'media': after.map(_media).toList(),
        'option': 'replace_next',
        // The album plays in its order.
        'shuffle': false,
      });
    }
    // The order sent stays known when it matched the queue up to the song.
    final kept = current != null && _sent.length == _items.length
        ? _sent.take(current + 1)
        : null;
    _sent = kept == null ? const [] : [...kept, ...after];
  }

  @override
  Future<void> playNext(List<Track> tracks) async {
    _remember(tracks);
    _sent = const [];
    await _queueCommand('play_media', {
      'media': tracks.map(_media).toList(),
      'option': 'next',
    });
  }

  @override
  Future<void> addTracks(List<Track> tracks) async {
    _remember(tracks);
    _sent = [..._sent, ...tracks];
    await _queueCommand('play_media', {
      'media': tracks.map(_media).toList(),
      'option': 'add',
    });
  }

  @override
  Future<void> play() => _control(_queueCommand('play'));
  @override
  Future<void> pause() {
    // A pause ends the wait for the start: the person no longer expects it to play.
    _settlePending();
    return _control(_queueCommand('pause'));
  }

  @override
  Future<void> next() => _control(_queueCommand('next'));
  @override
  Future<void> previous() => _control(_queueCommand('previous'));
  @override
  Future<void> seek(Duration position) =>
      _control(_queueCommand('seek', {'position': position.inSeconds}));
  @override
  Future<void> skipTo(int index) =>
      _control(_queueCommand('play_index', {'index': index}));
  @override
  Future<void> setShuffle(bool enabled) =>
      _control(_queueCommand('shuffle', {'shuffle_enabled': enabled}));
  @override
  Future<void> setRepeat(Repeat repeat) =>
      _control(_queueCommand('repeat', {'repeat_mode': repeat.name}));

  /// Turns the Autoplay of the queue on or off: Music Assistant then adds similar songs itself when the queue runs out. It refuses Autoplay while repeat is on, and the player offers none then. Servers before the rename only know `dont_stop_the_music`.
  Future<void> setAutoplay(bool enabled) => _control(() async {
    try {
      await _queueCommand('autoplay', {'autoplay_enabled': enabled});
    } on MaException {
      await _queueCommand('dont_stop_the_music', {
        'dont_stop_the_music_enabled': enabled,
      });
    }
  }());

  @override
  Future<void> removeAt(int index) async {
    _sent = const [];
    await _control(_queueCommand('delete_item', {'item_id_or_index': index}));
  }

  @override
  Future<void> move(int from, int to) async {
    if (from >= _items.length) return;
    _sent = const [];
    await _control(
      _queueCommand('move_item', {
        'queue_item_id': _items[from].id,
        'pos_shift': to - from,
      }),
    );
  }

  @override
  Future<void> setVolume(int volume) async {
    final player = _player;
    if (player != null) await _control(client.setVolume(player, volume));
  }

  /// Stops the player and clears its queue, since a queue that is not playing stays on screen.
  @override
  Future<void> stop() async {
    _settlePending();
    await _control(_queueCommand('stop'));
    await _control(_queueCommand('clear'));
  }

  @override
  Future<QueueSnapshot?> snapshot() async {
    final queue = _queue;
    if (queue == null || _items.isEmpty) return null;
    final current = queue.currentIndex ?? 0;
    // Items without a Subsonic track, such as radio streams, are left out, so the rest of the queue still moves.
    final tracks = <Track>[];
    var index = 0;
    var currentMapped = false;
    for (final (i, item) in _items.indexed) {
      var track = _trackFor(item, i);
      final id = _subsonicId(item);
      if (track == null && id != null) track = await lookupTrack?.call(id);
      if (i == current) {
        index = tracks.length;
        currentMapped = track != null;
      }
      if (track != null) tracks.add(track);
    }
    if (tracks.isEmpty) return null;
    return QueueSnapshot(
      tracks,
      index.clamp(0, tracks.length - 1),
      currentMapped ? queue.position(DateTime.now()) : Duration.zero,
      playing: queue.state == MaPlaybackState.playing,
    );
  }

  /// Adds players to the group led by this player, or removes them.
  Future<void> setMembers({
    List<String> add = const [],
    List<String> remove = const [],
  }) => _control(
    client.command('players/cmd/set_members', {
      'target_player': playerId,
      if (add.isNotEmpty) 'player_ids_to_add': add,
      if (remove.isNotEmpty) 'player_ids_to_remove': remove,
    }),
  );

  /// Moves the queue of this player to another Music Assistant player.
  Future<void> transferTo(String targetId) => client.command(
    'player_queues/transfer',
    {'source_queue_id': playerId, 'target_queue_id': targetId},
  );

  @override
  void dispose() {
    _pendingTimeout?.cancel();
    for (final s in _subscriptions) {
      s.cancel();
    }
    _controller.close();
  }
}

/// A Music Assistant player that did not start playing within [MusicAssistantPlaybackController.startTimeout].
class MaStartTimeout implements Exception {
  const MaStartTimeout(this.player);

  final String player;

  @override
  String toString() => '$player has not started playing';
}
