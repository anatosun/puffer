import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'models.dart';

const _apiVersion = '1.16.1';
const clientName = 'Puffer';

class SubsonicException implements Exception {
  const SubsonicException(this.code, this.message);

  final int code;
  final String message;

  @override
  String toString() => 'SubsonicException($code): $message';
}

/// Connection details for one server. The password is never stored: either an OpenSubsonic API key or a salted token is kept.
class ServerCredentials {
  const ServerCredentials({
    required this.baseUrl,
    required this.username,
    this.token,
    this.salt,
    this.apiKey,
  });

  /// Builds credentials from a password, with a fresh random salt.
  factory ServerCredentials.fromPassword({
    required String baseUrl,
    required String username,
    required String password,
  }) {
    final random = Random.secure();
    final salt = List.generate(
      12,
      (_) => random.nextInt(36).toRadixString(36),
    ).join();
    final token = md5.convert(utf8.encode(password + salt)).toString();
    return ServerCredentials(
      baseUrl: normaliseBaseUrl(baseUrl),
      username: username,
      token: token,
      salt: salt,
    );
  }

  final String baseUrl;
  final String username;
  final String? token;
  final String? salt;
  final String? apiKey;

  Map<String, String> get authParams => apiKey != null
      ? {'apiKey': apiKey!}
      : {'u': username, 't': token!, 's': salt!};

  Map<String, String> toJson() => {
    'baseUrl': baseUrl,
    'username': username,
    'token': ?token,
    'salt': ?salt,
    'apiKey': ?apiKey,
  };

  factory ServerCredentials.fromJson(Map<String, dynamic> json) =>
      ServerCredentials(
        baseUrl: json['baseUrl'] as String,
        username: json['username'] as String,
        token: json['token'] as String?,
        salt: json['salt'] as String?,
        apiKey: json['apiKey'] as String?,
      );
}

String normaliseBaseUrl(String url) {
  var result = url.trim();
  if (!result.startsWith(RegExp('https?://'))) result = 'https://$result';
  while (result.endsWith('/')) {
    result = result.substring(0, result.length - 1);
  }
  return result;
}

class SubsonicClient {
  SubsonicClient(this.credentials, {http.Client? httpClient})
    : _http = httpClient ?? http.Client();

  final ServerCredentials credentials;
  final http.Client _http;

  /// OpenSubsonic extension names reported by the server, filled by [loadExtensions].
  Set<String> extensions = const {};

  Uri _uri(String endpoint, [Map<String, Object?> params = const {}]) {
    final query = <String, dynamic>{
      ...credentials.authParams,
      'v': _apiVersion,
      'c': clientName,
      'f': 'json',
    };
    params.forEach((key, value) {
      if (value == null) return;
      query[key] = value is Iterable
          ? value.map((e) => '$e').toList()
          : '$value';
    });
    return Uri.parse('${credentials.baseUrl}/rest/$endpoint')
        .replace(queryParameters: query);
  }

  Future<Json> _get(
    String endpoint, [
    Map<String, Object?> params = const {},
  ]) async {
    final response = await _http
        .get(_uri(endpoint, params))
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw SubsonicException(
        response.statusCode,
        'HTTP ${response.statusCode} from $endpoint',
      );
    }
    final body =
        (jsonDecode(utf8.decode(response.bodyBytes))
                as Json)['subsonic-response']
            as Json?;
    if (body == null) throw const SubsonicException(0, 'Not a Subsonic server');
    if (body['status'] != 'ok') {
      final error = body['error'] as Json? ?? const {};
      throw SubsonicException(
        error['code'] as int? ?? 0,
        error['message'] as String? ?? 'Unknown error',
      );
    }
    return body;
  }

  Future<void> ping() => _get('ping');

  Future<Set<String>> loadExtensions() async {
    try {
      final body = await _get('getOpenSubsonicExtensions');
      extensions = jsonList(body['openSubsonicExtensions'])
          .map((e) => e['name'] as String)
          .toSet();
    } on SubsonicException {
      extensions = const {};
    }
    return extensions;
  }

  Future<List<Artist>> getArtists() async {
    final body = await _get('getArtists');
    final indexes = jsonList((body['artists'] as Json?)?['index']);
    return [
      for (final index in indexes) ...jsonList(index['artist']).map(Artist.new),
    ];
  }

  Future<Artist> getArtist(String id) async =>
      Artist((await _get('getArtist', {'id': id}))['artist'] as Json);

  Future<Album> getAlbum(String id) async =>
      Album((await _get('getAlbum', {'id': id}))['album'] as Json);

  Future<Track> getSong(String id) async =>
      Track((await _get('getSong', {'id': id}))['song'] as Json);

  /// [type] is one of `newest`, `recent`, `frequent`, `random`, `alphabeticalByName`, `alphabeticalByArtist`, `starred`.
  Future<List<Album>> getAlbumList(
    String type, {
    int size = 50,
    int offset = 0,
  }) async {
    final body = await _get('getAlbumList2', {
      'type': type,
      'size': size,
      'offset': offset,
    });
    return jsonList((body['albumList2'] as Json?)?['album'])
        .map(Album.new)
        .toList();
  }

  Future<List<Playlist>> getPlaylists() async {
    final body = await _get('getPlaylists');
    return jsonList((body['playlists'] as Json?)?['playlist'])
        .map(Playlist.new)
        .toList();
  }

  Future<Playlist> getPlaylist(String id) async =>
      Playlist((await _get('getPlaylist', {'id': id}))['playlist'] as Json);

  Future<SearchResult> search(String query, {int count = 20}) async {
    final body = await _get('search3', {
      'query': query,
      'artistCount': count,
      'albumCount': count,
      'songCount': count,
    });
    final result = body['searchResult3'] as Json? ?? const {};
    return SearchResult(
      artists: jsonList(result['artist']).map(Artist.new).toList(),
      albums: jsonList(result['album']).map(Album.new).toList(),
      tracks: jsonList(result['song']).map(Track.new).toList(),
    );
  }

  Future<Starred> getStarred() async {
    final body = await _get('getStarred2');
    final result = body['starred2'] as Json? ?? const {};
    return Starred(
      artists: jsonList(result['artist']).map(Artist.new).toList(),
      albums: jsonList(result['album']).map(Album.new).toList(),
      tracks: jsonList(result['song']).map(Track.new).toList(),
    );
  }

  /// Songs similar to the song, album or artist [id]. Navidrome fills it from its agents, such as the AudioMuse-AI plugin.
  Future<List<Track>> getSimilarSongs(String id, {int count = 50}) async {
    final body = await _get('getSimilarSongs', {'id': id, 'count': count});
    return jsonList((body['similarSongs'] as Json?)?['song'])
        .map(Track.new)
        .toList();
  }

  /// Songs similar to an artist (ID3), used for artist radio.
  Future<List<Track>> getSimilarSongs2(
    String artistId, {
    int count = 50,
  }) async {
    final body = await _get('getSimilarSongs2', {
      'id': artistId,
      'count': count,
    });
    return jsonList((body['similarSongs2'] as Json?)?['song'])
        .map(Track.new)
        .toList();
  }

  /// Songs that sound like [id], most similar first. Requires the OpenSubsonic `sonicSimilarity` extension.
  Future<List<Track>> getSonicSimilarTracks(String id, {int count = 50}) async {
    final body = await _get('getSonicSimilarTracks', {
      'id': id,
      'count': count,
    });
    return [
      for (final match in jsonList(body['sonicMatch']))
        Track(match['entry'] as Json),
    ];
  }

  bool get hasSonicSimilarity => extensions.contains('sonicSimilarity');

  Future<void> star({String? trackId, String? albumId, String? artistId}) =>
      _get('star', {'id': trackId, 'albumId': albumId, 'artistId': artistId});

  Future<void> unstar({String? trackId, String? albumId, String? artistId}) =>
      _get('unstar', {'id': trackId, 'albumId': albumId, 'artistId': artistId});

  Future<void> scrobble(String id, {required bool submission}) =>
      _get('scrobble', {
        'id': id,
        'submission': submission,
        'time': DateTime.now().millisecondsSinceEpoch,
      });

  /// Streaming URL. [format] and [maxBitRate] request server-side transcoding.
  Uri streamUri(String id, {String? format, int? maxBitRate}) =>
      _uri('stream', {'id': id, 'format': format, 'maxBitRate': maxBitRate});

  /// Original file when no transcoding is requested, otherwise the transcoded stream.
  Uri downloadUri(String id, {String? format, int? maxBitRate}) =>
      format == null && maxBitRate == null
      ? _uri('download', {'id': id})
      : streamUri(id, format: format, maxBitRate: maxBitRate);

  Uri coverArtUri(String id, {int? size}) =>
      _uri('getCoverArt', {'id': id, 'size': size});

  void close() => _http.close();
}
