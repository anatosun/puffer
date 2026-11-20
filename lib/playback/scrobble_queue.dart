import 'dart:convert';
import 'dart:io';

import '../data/subsonic/subsonic_client.dart';

/// A play to report: the song and when it began.
class Play {
  const Play(this.trackId, this.at);

  final String trackId;
  final DateTime at;

  Map<String, Object> toJson() => {
    'id': trackId,
    'at': at.millisecondsSinceEpoch,
  };

  static Play? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final at = json['at'];
    if (id is! String || at is! int) return null;
    return Play(id, DateTime.fromMillisecondsSinceEpoch(at));
  }
}

/// The plays that could not reach the server, kept in a file until they can. A play waits while the app is offline or while the server cannot be reached, and goes to the server with the others once it can. A play the server refuses is dropped, so one bad song never holds the rest.
class ScrobbleQueue {
  ScrobbleQueue(this.file, {required this.send, this.limit = 5000});

  final File file;

  /// Reports plays to the server in one request. A [SubsonicException] means the server refused them; any other error means it could not be reached.
  final Future<void> Function(List<Play> plays) send;

  /// Plays sent in one request. The Subsonic API takes several `id` and `time` pairs per call, and fifty keep the URL short.
  static const batch = 50;

  /// Plays older than the newest this many are dropped, so a long time offline does not grow the file without end.
  final int limit;

  List<Play>? _plays;
  Future<void> _work = Future.value();
  bool _flushing = false;

  /// The plays waiting, oldest first.
  Future<List<Play>> pending() => _run(() async => List.of(await _load()));

  /// Keeps [play] for later.
  Future<void> add(Play play) => _run(() async {
    final plays = await _load();
    plays.add(play);
    if (plays.length > limit) plays.removeRange(0, plays.length - limit);
    await _save(plays);
  });

  /// Sends [play] now and, when that works, the plays waiting. A play the server cannot be reached for waits.
  Future<void> report(Play play) async {
    try {
      await send([play]);
    } on SubsonicException {
      return;
    } on Object {
      await add(play);
      return;
    }
    await flush();
  }

  /// Sends the plays waiting, oldest first, and stops at the first batch the server cannot be reached for.
  Future<void> flush() async {
    if (_flushing) return;
    _flushing = true;
    try {
      while (true) {
        final next = await _run(
          () async => (await _load()).take(batch).toList(),
        );
        if (next.isEmpty) return;
        if (!await _sendBatch(next)) return;
        await _run(() async {
          final sent = next.toSet();
          final plays = await _load()
            ..removeWhere(sent.contains);
          await _save(plays);
        });
      }
    } finally {
      _flushing = false;
    }
  }

  Future<void> clear() => _run(() async => _save(_plays = []));

  /// Whether [plays] are done with: sent, or refused by the server. When the server refuses a batch, each play goes again on its own, so only the plays it refuses are dropped.
  Future<bool> _sendBatch(List<Play> plays) async {
    try {
      await send(plays);
      return true;
    } on SubsonicException {
      if (plays.length == 1) return true;
    } on Object {
      return false;
    }
    for (final play in plays) {
      try {
        await send([play]);
      } on SubsonicException {
        // Refused: dropped.
      } on Object {
        return false;
      }
    }
    return true;
  }

  /// Runs [action] after the ones before it, so the list and the file change one at a time.
  Future<T> _run<T>(Future<T> Function() action) {
    final done = _work.then((_) => action());
    _work = done.then<void>((_) {}, onError: (Object _) {});
    return done;
  }

  Future<List<Play>> _load() async {
    if (_plays case final plays?) return plays;
    try {
      final json = jsonDecode(await file.readAsString());
      return _plays = [
        if (json is List)
          for (final e in json) ?Play.fromJson(e),
      ];
    } on Object {
      return _plays = [];
    }
  }

  Future<void> _save(List<Play> plays) async {
    if (plays.isEmpty) {
      if (await file.exists()) await file.delete();
      return;
    }
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode([for (final p in plays) p.toJson()]));
    await temp.rename(file.path);
  }
}
