import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

/// Artwork of downloaded items, kept on disk so downloaded items show in full offline.
class ArtworkStore {
  ArtworkStore(this.directory, this.uriFor);

  final Directory directory;
  final Uri Function(String coverArt) uriFor;
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

  Future<void> ensure(String coverArt) =>
      _inFlight[coverArt] ??= _download(coverArt)
          .whenComplete(() => _inFlight.remove(coverArt));

  Future<void> _download(String coverArt) async {
    final target = file(coverArt);
    if (await target.exists()) return;
    final response = await http
        .get(uriFor(coverArt))
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) return;
    await directory.create(recursive: true);
    final temp = File('${target.path}.part');
    await temp.writeAsBytes(response.bodyBytes);
    await temp.rename(target.path);
  }

  Future<void> clear() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}
