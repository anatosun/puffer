// Domain models built from Subsonic JSON. Each model keeps the JSON it was built from, so the cache stores and restores it unchanged.

typedef Json = Map<String, dynamic>;

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

  /// Present only in `getAlbum` responses.
  List<Track> get songs => _list(json['song']).map(Track.new).toList();
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
