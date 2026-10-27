// Music Assistant objects, wrapping the server JSON with typed getters. Field names follow music_assistant_models.

typedef MaJson = Map<String, dynamic>;

enum MaPlaybackState { idle, paused, playing, unknown }

enum MaRepeatMode { off, one, all }

MaPlaybackState _state(Object? value) =>
    MaPlaybackState.values.asNameMap()[value] ?? MaPlaybackState.unknown;

class MaPlayer {
  const MaPlayer(this.json);

  final MaJson json;

  String get id => json['player_id'] as String;
  String get name => json['name'] as String? ?? id;
  bool get available => json['available'] as bool? ?? false;
  bool get enabled => json['enabled'] as bool? ?? true;
  bool get hidden => json['hide_in_ui'] as bool? ?? false;
  String? get type => json['type'] as String?;
  MaPlaybackState get state => _state(json['playback_state']);
  int? get volume => json['volume_level'] as int?;
  bool get muted => json['volume_muted'] as bool? ?? false;
  String? get syncedTo => json['synced_to'] as String?;
  String? get activeGroup => json['active_group'] as String?;
  List<String> get groupMembers => [
    ...?(json['group_members'] as List?)?.cast<String>(),
  ];
  bool get isGroup => type == 'group' || groupMembers.length > 1;

  /// Players a person can pick as output: available, enabled, shown, and not a member following another player.
  bool get selectable => available && enabled && !hidden && syncedTo == null;
}

class MaImage {
  const MaImage(this.json);

  final MaJson json;

  String get path => json['path'] as String;
  String get provider => json['provider'] as String? ?? 'builtin';
  bool get remotelyAccessible => json['remotely_accessible'] as bool? ?? false;

  /// A URL for the image: the path itself when the server says it is reachable, otherwise through the image proxy of Music Assistant.
  Uri url(Uri serverBase, {int size = 512}) => remotelyAccessible
      ? Uri.parse(path)
      : serverBase.replace(
          path: '${serverBase.path}/imageproxy',
          queryParameters: {
            'path': path,
            'provider': provider,
            'size': '$size',
          },
        );
}

class MaQueueItem {
  const MaQueueItem(this.json);

  final MaJson json;

  String get id => json['queue_item_id'] as String;
  String get name => json['name'] as String? ?? '';
  Duration get duration =>
      Duration(seconds: (json['duration'] as num?)?.round() ?? 0);
  MaJson? get mediaItem => json['media_item'] as MaJson?;
  MaImage? get image =>
      json['image'] == null ? null : MaImage(json['image'] as MaJson);

  String get title => mediaItem?['name'] as String? ?? name;
  String? get artist {
    final artists = mediaItem?['artists'] as List?;
    if (artists == null || artists.isEmpty) return null;
    return artists
        .map((a) => (a as MaJson)['name'])
        .whereType<String>()
        .join(', ');
  }

  String? get album => (mediaItem?['album'] as MaJson?)?['name'] as String?;

  /// The ID of the track at the given provider instance, from the provider mappings of the media item.
  String? itemIdAt(String providerInstance) {
    for (final m in (mediaItem?['provider_mappings'] as List?) ?? const []) {
      final mapping = m as MaJson;
      if (mapping['provider_instance'] == providerInstance) {
        return mapping['item_id'] as String?;
      }
    }
    return null;
  }
}

class MaQueue {
  const MaQueue(this.json);

  final MaJson json;

  String get id => json['queue_id'] as String;
  bool get active => json['active'] as bool? ?? false;
  MaPlaybackState get state => _state(json['state']);
  int? get currentIndex => json['current_index'] as int?;
  int get itemCount => json['items'] as int? ?? 0;
  bool get shuffle => json['shuffle_enabled'] as bool? ?? false;
  MaRepeatMode get repeat =>
      MaRepeatMode.values.asNameMap()[json['repeat_mode']] ?? MaRepeatMode.off;
  MaQueueItem? get currentItem => json['current_item'] == null
      ? null
      : MaQueueItem(json['current_item'] as MaJson);
  double get elapsed => (json['elapsed_time'] as num?)?.toDouble() ?? 0;

  /// UTC timestamp in seconds of [elapsed].
  double get elapsedUpdatedAt =>
      (json['elapsed_time_last_updated'] as num?)?.toDouble() ?? 0;

  /// The position now, advanced from [elapsed] while playing.
  Duration position(DateTime now) {
    var seconds = elapsed;
    if (state == MaPlaybackState.playing && elapsedUpdatedAt > 0) {
      seconds += now.millisecondsSinceEpoch / 1000 - elapsedUpdatedAt;
    }
    return Duration(milliseconds: (seconds * 1000).round().clamp(0, 1 << 40));
  }
}

class MaProvider {
  const MaProvider(this.json);

  final MaJson json;

  String get instanceId => json['instance_id'] as String;
  String get domain => json['domain'] as String;
  String get name => json['name'] as String? ?? instanceId;
  bool get available => json['available'] as bool? ?? false;
}
