import 'dart:convert';
import 'dart:io';

import '../data/subsonic/models.dart';

/// A queue this device played before another replaced it, with the song and position it had reached.
class PastQueue {
  const PastQueue(this.tracks, this.index, this.position, this.replacedAt);

  final List<Track> tracks;
  final int index;
  final Duration position;
  final DateTime replacedAt;

  /// What the queue was: the album when every song comes from one, the artist when one artist sings them all, otherwise its first song and how many follow.
  String get label {
    final first = tracks.first;
    final albumId = first.albumId;
    if (albumId != null &&
        first.album != null &&
        tracks.every((t) => t.albumId == albumId)) {
      return first.album!;
    }
    final artist = first.artist;
    if (tracks.length > 1 &&
        artist != null &&
        tracks.every((t) => t.artist == artist)) {
      return artist;
    }
    return tracks.length == 1
        ? first.title
        : '${first.title} and ${tracks.length - 1} more';
  }

  Map<String, dynamic> toJson() => {
    'index': index,
    'position': position.inMilliseconds,
    'replacedAt': replacedAt.millisecondsSinceEpoch,
    'tracks': [for (final t in tracks) t.json],
  };

  static PastQueue? fromJson(Map<String, dynamic> json) {
    final tracks = jsonList(json['tracks']).map(Track.new).toList();
    if (tracks.isEmpty) return null;
    return PastQueue(
      tracks,
      (json['index'] as int? ?? 0).clamp(0, tracks.length - 1),
      Duration(milliseconds: json['position'] as int? ?? 0),
      DateTime.fromMillisecondsSinceEpoch(json['replacedAt'] as int? ?? 0),
    );
  }
}

/// The last [limit] queues this device replaced, most recent first, kept in a file so they survive a restart.
class PastQueueStore {
  PastQueueStore(this.file);

  static const limit = 5;

  final File file;

  Future<List<PastQueue>> load() async {
    try {
      if (!await file.exists()) return const [];
      return [
        for (final entry in jsonDecode(await file.readAsString()) as List)
          ?PastQueue.fromJson(entry as Map<String, dynamic>),
      ];
    } on Exception {
      return const [];
    }
  }

  /// Puts [queue] first. An earlier entry with the same songs in the same order gives way to it.
  Future<List<PastQueue>> push(PastQueue queue) async {
    final ids = _ids(queue.tracks);
    final queues = [
      queue,
      ...(await load()).where((q) => _ids(q.tracks) != ids),
    ].take(limit).toList();
    await _save(queues);
    return queues;
  }

  /// Removes the entry at [index], as when it plays again.
  Future<List<PastQueue>> removeAt(int index) async {
    final queues = [...await load()];
    if (index < queues.length) queues.removeAt(index);
    await _save(queues);
    return queues;
  }

  Future<void> clear() async {
    if (await file.exists()) await file.delete();
  }

  Future<void> _save(List<PastQueue> queues) async {
    final temp = File('${file.path}.part');
    await temp.writeAsString(jsonEncode([for (final q in queues) q.toJson()]));
    await temp.rename(file.path);
  }

  static String _ids(List<Track> tracks) => tracks.map((t) => t.id).join(',');
}
