import 'dart:convert';
import 'dart:io';

import '../data/subsonic/models.dart';

class SavedQueue {
  const SavedQueue(this.tracks, this.index, this.position);

  final List<Track> tracks;
  final int index;
  final Duration position;
}

/// The queue of this device, kept in a file so it survives a restart.
class QueueStore {
  QueueStore(this.file);

  final File file;

  Future<void> save(List<Track> tracks, int index, Duration position) async {
    if (tracks.isEmpty) return clear();
    final temp = File('${file.path}.part');
    await temp.writeAsString(
      jsonEncode({
        'index': index,
        'position': position.inMilliseconds,
        'tracks': [for (final t in tracks) t.json],
      }),
    );
    await temp.rename(file.path);
  }

  Future<SavedQueue?> load() async {
    try {
      if (!await file.exists()) return null;
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final tracks = jsonList(json['tracks']).map(Track.new).toList();
      if (tracks.isEmpty) return null;
      final index = (json['index'] as int? ?? 0).clamp(0, tracks.length - 1);
      return SavedQueue(
        tracks,
        index,
        Duration(milliseconds: json['position'] as int? ?? 0),
      );
    } on Exception {
      return null;
    }
  }

  Future<void> clear() async {
    if (await file.exists()) await file.delete();
  }
}
