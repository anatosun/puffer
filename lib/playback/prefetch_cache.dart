import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

/// When the next songs of the queue are fetched ahead.
enum PrefetchMode {
  off('Off'),
  wifi('On Wi-Fi'),
  always('Always');

  const PrefetchMode(this.label);

  final String label;
}

/// How many songs after the current one are fetched ahead.
const prefetchCount = 3;

/// How many songs played before the current one keep their cached files, so going back a few songs plays from the file.
const recentlyPlayedKept = 10;

/// Cache size limits a person can choose, in bytes.
const prefetchLimits = [
  256 * 1024 * 1024,
  512 * 1024 * 1024,
  1024 * 1024 * 1024,
  2048 * 1024 * 1024,
];

/// A folder of songs fetched ahead of playback, separate from downloads. Files are named by track and quality, so a change of quality fetches the song again. Above [maxBytes], the least recently used files go first.
class PrefetchCache {
  PrefetchCache(this.dir, {required this.maxBytes, http.Client? httpClient})
    : _http = httpClient ?? http.Client();

  final Directory dir;
  int maxBytes;
  final http.Client _http;

  /// The file name of [trackId] at [quality], with the extension the player needs to recognise the format.
  static String fileName(String trackId, String quality, String extension) =>
      '${_safe(trackId)}_${_safe(quality)}.${_safe(extension)}';

  static String _safe(String s) => s.replaceAll(RegExp(r'[^\w.-]'), '_');

  /// The cached file of [name], marked as used now, or null when the cache does not hold it.
  Future<File?> existing(String name) async {
    final file = File(p.join(dir.path, name));
    if (!await file.exists()) return null;
    try {
      await file.setLastModified(DateTime.now());
    } on FileSystemException {
      // The file is still usable; it only ages sooner.
    }
    return file;
  }

  /// Fetches [uri] into the file [name], unless the cache already holds it. A failed fetch leaves no file.
  Future<File> fetch(String name, Uri uri) async {
    final cached = await existing(name);
    if (cached != null) return cached;
    await dir.create(recursive: true);
    final file = File(p.join(dir.path, name));
    final part = File('${file.path}.part');
    final response = await _http
        .send(http.Request('GET', uri))
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200 ||
        (response.headers['content-type'] ?? '').contains('json') ||
        (response.headers['content-type'] ?? '').contains('xml')) {
      await response.stream.drain<void>();
      throw HttpException('HTTP ${response.statusCode}', uri: uri);
    }
    try {
      await response.stream.pipe(part.openWrite());
      return await part.rename(file.path);
    } on Object {
      if (await part.exists()) await part.delete();
      rethrow;
    }
  }

  /// Deletes the least recently used files until the cache fits in [maxBytes], never the files named in [keep]. Returns the names of the deleted files.
  Future<List<String>> evict({Set<String> keep = const {}}) async {
    final files = await _files();
    var total = files.fold<int>(0, (sum, f) => sum + f.$2.size);
    if (total <= maxBytes) return const [];
    files.sort((a, b) => a.$2.modified.compareTo(b.$2.modified));
    final deleted = <String>[];
    for (final (file, stat) in files) {
      if (total <= maxBytes) break;
      final name = p.basename(file.path);
      if (keep.contains(name)) continue;
      await file.delete();
      total -= stat.size;
      deleted.add(name);
    }
    return deleted;
  }

  Future<int> size() async =>
      (await _files()).fold<int>(0, (sum, f) => sum + f.$2.size);

  /// Deletes every file except those named in [keep].
  Future<void> clear({Set<String> keep = const {}}) async {
    for (final (file, _) in await _files()) {
      if (!keep.contains(p.basename(file.path))) await file.delete();
    }
  }

  Future<List<(File, FileStat)>> _files() async {
    if (!await dir.exists()) return [];
    return [
      await for (final entity in dir.list())
        if (entity is File && !entity.path.endsWith('.part'))
          (entity, await entity.stat()),
    ];
  }

  void close() => _http.close();
}

/// The queue positions of the songs that play after [current], in play order: [effectiveIndices] is the play order of the queue (the shuffle order when shuffling). With [loop], the order wraps around to the start.
List<int> upcomingIndices(
  List<int> effectiveIndices,
  int current, {
  int count = prefetchCount,
  bool loop = false,
}) {
  final at = effectiveIndices.indexOf(current);
  if (at < 0) return const [];
  final result = <int>[];
  for (var i = 1; i <= count; i++) {
    final pos = at + i;
    if (pos >= effectiveIndices.length && !loop) break;
    final index = effectiveIndices[pos % effectiveIndices.length];
    if (index == current || result.contains(index)) break;
    result.add(index);
  }
  return result;
}
