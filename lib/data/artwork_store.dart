import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

/// Artwork of downloaded items, kept on disk so downloaded items show in full offline.
class ArtworkStore {
  ArtworkStore(this.directory, this.uriFor, {http.Client? httpClient})
    : _http = httpClient;

  final Directory directory;
  final Uri Function(String coverArt) uriFor;
  final http.Client? _http;
  final _inFlight = <String, Future<void>>{};

  File file(String coverArt) => File(
    p.join(
      directory.path,
      '${coverArt.replaceAll(RegExp(r'[^\w\-]'), '_')}.img',
    ),
  );

  File? existing(String? coverArt) {
    if (coverArt == null) return null;
    final f = file(coverArt);
    return f.existsSync() ? f : null;
  }

  /// Stores [coverArt] unless it is stored or on its way.
  Future<void> ensure(String coverArt) =>
      // The callback returns nothing: given back, the future it removes would be waited for by itself, and the fetch would never complete.
      _inFlight[coverArt] ??= _download(coverArt).whenComplete(() {
        _inFlight.remove(coverArt);
      });

  /// Stores each of [coverArts] once, one after another, so the covers of a large download do not all ask the server at the same time. A cover that fails is skipped.
  Future<void> ensureAll(Iterable<String?> coverArts) async {
    for (final coverArt in {...coverArts.nonNulls}) {
      try {
        await ensure(coverArt);
      } on Exception {
        // The item shows without its cover offline.
      }
    }
  }

  Future<void> _download(String coverArt) async {
    final target = file(coverArt);
    if (await target.exists()) return;
    final uri = uriFor(coverArt);
    final response = await (_http?.get(uri) ?? http.get(uri)).timeout(
      const Duration(seconds: 30),
    );
    // A Subsonic error comes with status 200; stored, it would show as a broken image for good.
    final type = response.headers['content-type'] ?? '';
    if (response.statusCode != 200 ||
        type.contains('json') ||
        type.contains('xml') ||
        type.startsWith('text/')) {
      return;
    }
    await directory.create(recursive: true);
    final temp = File('${target.path}.part');
    await temp.writeAsBytes(response.bodyBytes);
    await temp.rename(target.path);
  }

  Future<void> clear() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}
