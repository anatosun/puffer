// Domain models built from Subsonic JSON. Each model keeps the JSON it was built from, so the cache stores and restores it unchanged.

typedef Json = Map<String, dynamic>;

/// One line of lyrics. [start] is null in lyrics without timing.
class LyricLine {
  const LyricLine(this.text, [this.start]);

  final String text;
  final Duration? start;
}

/// The lyrics of a song, from the OpenSubsonic `getLyricsBySongId` response. [json] is one `structuredLyrics` entry.
class Lyrics {
  const Lyrics(this.json);

  final Json json;

  /// The entry to show out of a `lyricsList`: timed lyrics before plain ones. Null when the song has none.
  static Lyrics? pick(Object? lyricsList) {
    final entries = jsonList((lyricsList as Json?)?['structuredLyrics']);
    final usable = [
      for (final e in entries)
        if (jsonList(e['line'])
            .any((l) => '${l['value'] ?? ''}'.trim().isNotEmpty))
          e,
    ];
    if (usable.isEmpty) return null;
    return Lyrics(
      usable.firstWhere((e) => e['synced'] == true, orElse: () => usable.first),
    );
  }

  bool get synced => json['synced'] == true;
  String? get language => json['lang'] as String?;

  /// The lines in order. Times already include the `offset` of the lyrics, which is in milliseconds and makes the lyrics appear sooner when positive.
  List<LyricLine> get lines {
    final offset = (json['offset'] as num?)?.toInt() ?? 0;
    return [
      for (final l in jsonList(json['line']))
        LyricLine(
          '${l['value'] ?? ''}',
          synced && l['start'] is num
              ? Duration(
                  milliseconds: ((l['start'] as num).toInt() - offset).clamp(
                    0,
                    1 << 40,
                  ),
                )
              : null,
        ),
    ];
  }
}

/// The index of the line sung at [position]: the last one that has started, or null before the first. Lines without timing never match.
int? currentLyricLine(List<LyricLine> lines, Duration position) {
  int? current;
  for (var i = 0; i < lines.length; i++) {
    final start = lines[i].start;
    if (start == null) continue;
    if (start > position) break;
    current = i;
  }
  return current;
}

/// Whether [id] names an item a proxy such as octo-fiesta fetches from an external provider (Deezer, Qobuz, Tidal, …). Such a proxy downloads the song in full from the provider whenever a client requests its audio.
bool isExternalId(String id) => id.startsWith('ext-');

/// [items] without the external ones, unless [includeExternal]: what background work such as artist downloads and fetching ahead may request.
Iterable<T> forBackground<T>(
  Iterable<T> items,
  String Function(T) id, {
  required bool includeExternal,
}) => includeExternal ? items : items.where((i) => !isExternalId(id(i)));

List<Json> _list(Object? value) {
  if (value is List) return value.cast<Json>();
  if (value is Map) return [value.cast<String, dynamic>()];
  return const [];
}

class Track {
  const Track(this.json);
  factory Track.fromJson(Json json) => Track(json);

  final Json json;

  String get id => json['id'] as String;
  String get title => json['title'] as String? ?? 'Unknown title';
  String? get album => json['album'] as String?;
  String? get albumId => json['albumId'] as String?;
  String? get artist => json['artist'] as String?;
  String? get artistId => json['artistId'] as String?;
  int? get trackNumber => json['track'] as int?;
  int get discNumber => json['discNumber'] as int? ?? 1;
  Duration get duration => Duration(seconds: json['duration'] as int? ?? 0);
  String get suffix => json['suffix'] as String? ?? 'mp3';
  int? get size => json['size'] as int?;
  int? get bitRate => json['bitRate'] as int?;
  int? get year => json['year'] as int?;
  String? get coverArt => json['coverArt'] as String?;
  bool get starred => json['starred'] != null;
  int get rating => json['userRating'] as int? ?? 0;
}

class Album {
  const Album(this.json);
  factory Album.fromJson(Json json) => Album(json);

  final Json json;

  String get id => json['id'] as String;
  String get name =>
      json['name'] as String? ?? json['title'] as String? ?? 'Unknown album';
  String? get artist => json['artist'] as String?;
  String? get artistId => json['artistId'] as String?;
  String? get coverArt => json['coverArt'] as String?;
  int get songCount => json['songCount'] as int? ?? 0;
  Duration get duration => Duration(seconds: json['duration'] as int? ?? 0);
  int? get year => json['year'] as int?;
  String? get genre => json['genre'] as String?;
  bool get starred => json['starred'] != null;
  int get rating => json['userRating'] as int? ?? 0;

  /// The kind of release, from the OpenSubsonic `releaseTypes` and `isCompilation` fields. Albums from servers without them count as albums.
  ReleaseKind get releaseKind {
    final types = [
      for (final t in (json['releaseTypes'] as List?) ?? const [])
        '$t'.toLowerCase(),
    ];
    if (json['isCompilation'] == true || types.contains('compilation')) {
      return ReleaseKind.compilation;
    }
    if (types.contains('live')) return ReleaseKind.live;
    if (types.contains('ep')) return ReleaseKind.ep;
    if (types.contains('single')) return ReleaseKind.single;
    return ReleaseKind.album;
  }

  /// Present only in `getAlbum` responses.
  List<Track> get songs => _list(json['song']).map(Track.new).toList();
}

/// Release kinds in the order the artist page lists them.
enum ReleaseKind {
  album('Albums'),
  ep('EPs'),
  single('Singles'),
  live('Live'),
  compilation('Compilations');

  const ReleaseKind(this.label);

  final String label;
}

class Artist {
  const Artist(this.json);
  factory Artist.fromJson(Json json) => Artist(json);

  final Json json;

  String get id => json['id'] as String;
  String get name => json['name'] as String? ?? 'Unknown artist';
  String? get coverArt => json['coverArt'] as String?;
  int get albumCount => json['albumCount'] as int? ?? 0;
  bool get starred => json['starred'] != null;

  /// Present only in `getArtist` responses.
  List<Album> get albums => _list(json['album']).map(Album.new).toList();
}

class Playlist {
  const Playlist(this.json);
  factory Playlist.fromJson(Json json) => Playlist(json);

  final Json json;

  String get id => json['id'] as String;
  String get name => json['name'] as String? ?? 'Untitled playlist';
  String? get owner => json['owner'] as String?;
  String? get coverArt => json['coverArt'] as String?;
  int get songCount => json['songCount'] as int? ?? 0;
  Duration get duration => Duration(seconds: json['duration'] as int? ?? 0);

  /// When the playlist last changed, as an ISO 8601 date.
  String? get changed =>
      json['changed'] as String? ?? json['created'] as String?;

  /// Present only in `getPlaylist` responses.
  List<Track> get entries => _list(json['entry']).map(Track.new).toList();
}

class ArtistInfo {
  const ArtistInfo(this.json);

  final Json json;

  /// The biography as plain text, without the HTML links Last.fm appends.
  String? get biography {
    final raw = json['biography'] as String?;
    if (raw == null) return null;
    final text = raw
        .replaceAll(RegExp(r'<a [^>]*>.*?</a>\.?', dotAll: true), '')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .trim();
    return text.isEmpty ? null : text;
  }

  /// Similar artists that are in the library; the server leaves out those without an id.
  List<Artist> get similarArtists => [
    for (final a in jsonList(json['similarArtist']))
      if (a['id'] != null) Artist(a),
  ];

  /// A photo of the artist. Last.fm's star placeholder counts as none.
  String? get imageUrl {
    for (final key in ['largeImageUrl', 'mediumImageUrl', 'smallImageUrl']) {
      final url = json[key] as String?;
      if (url != null &&
          url.isNotEmpty &&
          !url.contains('2a96cbd8b46e442fc41c2b86b821562f')) {
        return url;
      }
    }
    return null;
  }
}

class Genre {
  const Genre(this.json);

  final Json json;

  String get name => json['value'] as String? ?? '';
  int get albumCount => json['albumCount'] as int? ?? 0;
  int get songCount => json['songCount'] as int? ?? 0;
}

class SearchResult {
  const SearchResult({
    required this.artists,
    required this.albums,
    required this.tracks,
  });

  final List<Artist> artists;
  final List<Album> albums;
  final List<Track> tracks;
}

class Starred {
  const Starred({
    required this.artists,
    required this.albums,
    required this.tracks,
  });

  final List<Artist> artists;
  final List<Album> albums;
  final List<Track> tracks;
}

List<Json> jsonList(Object? value) => _list(value);
