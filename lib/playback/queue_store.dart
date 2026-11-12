import 'dart:convert';
import 'dart:io';

import '../data/subsonic/models.dart';

class SavedQueue {
  const SavedQueue(this.tracks, this.index, this.position);

  final List<Track> tracks;
  final int index;
  final Duration position;
}

/// The queue of this device, kept in a file so it survives a restart. The songs are written when they change; the place in the queue, which changes every few seconds, goes to a small file of its own.
class QueueStore {
  QueueStore(this.file);

  final File file;

  File get _placeFile => File('${file.path}.place');

  /// The songs last written, and the stamp of that write, which the place file names so it never applies to another queue.
  List<String>? _written;
  int _stamp = 0;
  Future<void> _writing = Future.value();

  /// Saves the queue. Saves follow one another, so a slow write never ends after a later one.
  Future<void> save(List<Track> tracks, int index, Duration position) {
    final ids = [for (final t in tracks) t.id];
    final json = tracks.isEmpty ? null : [for (final t in tracks) t.json];
    return _queue(() => _save(ids, json, index, position));
  }

  Future<void> _queue(Future<void> Function() write) {
    final done = _writing.then((_) => write());
    // A failed write leaves the next one to run.
    _writing = done.catchError((Object _) {});
    return done;
  }

  Future<void> _save(
    List<String> ids,
    List<Map<String, dynamic>>? tracks,
    int index,
    Duration position,
  ) async {
    if (tracks == null) return _clear();
    final place = {'index': index, 'position': position.inMilliseconds};
    if (!_same(ids, _written)) {
      _stamp = DateTime.now().microsecondsSinceEpoch;
      await _write(file, {...place, 'stamp': _stamp, 'tracks': tracks});
      _written = ids;
    }
    await _write(_placeFile, {...place, 'stamp': _stamp});
  }

  static bool _same(List<String> a, List<String>? b) {
    if (b == null || a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static Future<void> _write(File target, Object json) async {
    final temp = File('${target.path}.part');
    await temp.writeAsString(jsonEncode(json));
    await temp.rename(target.path);
  }

  Future<SavedQueue?> load() async {
    try {
      if (!await file.exists()) return null;
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final tracks = jsonList(json['tracks']).map(Track.new).toList();
      if (tracks.isEmpty) return null;
      final place = await _place(json['stamp']) ?? json;
      final index = (place['index'] as int? ?? 0).clamp(0, tracks.length - 1);
      _written = [for (final t in tracks) t.id];
      _stamp = json['stamp'] as int? ?? 0;
      return SavedQueue(
        tracks,
        index,
        Duration(milliseconds: place['position'] as int? ?? 0),
      );
    } on Exception {
      return null;
    }
  }

  /// The place saved for the queue written with [stamp]; null when it was saved for another queue or not at all, and the queue file then holds the place.
  Future<Map<String, dynamic>?> _place(Object? stamp) async {
    try {
      if (stamp == null || !await _placeFile.exists()) return null;
      final json =
          jsonDecode(await _placeFile.readAsString()) as Map<String, dynamic>;
      return json['stamp'] == stamp ? json : null;
    } on Exception {
      return null;
    }
  }

  Future<void> clear() => _queue(_clear);

  Future<void> _clear() async {
    _written = null;
    for (final f in [file, _placeFile]) {
      if (await f.exists()) await f.delete();
    }
  }
}
