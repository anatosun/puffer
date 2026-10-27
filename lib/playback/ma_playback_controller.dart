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

  late final List<StreamSubscription<Object?>> _subscriptions;
  final _controller = StreamController<NowPlaying?>.broadcast();
  final _known = <String, Track>{};
  List<Track> _sent = const [];
  List<MaQueueItem> _items = const [];
  NowPlaying? _current;

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
    _current = _build();
    _controller.add(_current);
  }

  Track? _trackFor(MaQueueItem item, int? index) {
    if (providerInstance != null) {
      final id = item.itemIdAt(providerInstance!);
      if (id != null) return _known[id];
    }
    // Stream URLs carry no Subsonic ID back; the queue order is the order the tracks were sent in.
    if (index != null && index < _sent.length && _items.length == _sent.length) {
      return _sent[index];
    }
    return null;
  }

  NowPlaying? _build() {
    final queue = _queue;
    final item = queue?.currentItem;
    if (queue == null || item == null) return null;
    final track = _trackFor(item, queue.currentIndex);
    final now = DateTime.now();
    return NowPlaying(
      track: track,
      title: track?.title ?? item.title,
      artist: track?.artist ?? item.artist,
      album: track?.album ?? item.album,
      coverArt: track?.coverArt,
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
          QueueEntry(
            id: it.id,
            title: _trackFor(it, i)?.title ?? it.title,
            artist: _trackFor(it, i)?.artist ?? it.artist,
          ),
      ],
      index: queue.currentIndex,
      outputName: _player?.name ?? playerId,
      volume: _player?.volume,
    );
  }

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
    await _queueCommand('play_media', {
      'media': media,
      'option': 'replace',
      if (index > 0 && !shuffle) 'start_item': media[index],
      'shuffle': shuffle,
    });
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
  Future<void> play() => _queueCommand('play');
  @override
  Future<void> pause() => _queueCommand('pause');
  @override
  Future<void> next() => _queueCommand('next');
  @override
  Future<void> previous() => _queueCommand('previous');
  @override
  Future<void> seek(Duration position) =>
      _queueCommand('seek', {'position': position.inSeconds});
  @override
  Future<void> skipTo(int index) =>
      _queueCommand('play_index', {'index': index});
  @override
  Future<void> setShuffle(bool enabled) =>
      _queueCommand('shuffle', {'shuffle_enabled': enabled});
  @override
  Future<void> setRepeat(Repeat repeat) =>
      _queueCommand('repeat', {'repeat_mode': repeat.name});

  @override
  Future<void> removeAt(int index) async {
    _sent = const [];
    await _queueCommand('delete_item', {'item_id_or_index': index});
  }

  @override
  Future<void> move(int from, int to) async {
    if (from >= _items.length) return;
    _sent = const [];
    await _queueCommand('move_item', {
      'queue_item_id': _items[from].id,
      'pos_shift': to - from,
    });
  }

  @override
  Future<void> setVolume(int volume) {
    final group = _player?.isGroup ?? false;
    return client.command(
      group ? 'players/cmd/group_volume' : 'players/cmd/volume_set',
      {'player_id': playerId, 'volume_level': volume},
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
