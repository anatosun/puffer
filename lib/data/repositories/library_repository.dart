import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';

import '../db/database.dart';
import '../subsonic/models.dart';
import '../subsonic/subsonic_client.dart';

/// Yields [cached] first when there is one, then [fresh]. A failure of [fresh] after a cached value keeps the cached value.
Stream<T> cachedThenFresh<T>(
  Future<T?> cached,
  Future<T> Function() fresh,
) async* {
  final first = await cached;
  if (first != null) yield first;
  try {
    yield await fresh();
  } on Exception {
    if (first == null) rethrow;
  }
}

/// Whether every word of [query] appears in one of [fields], ignoring case.
bool matchesQuery(String query, Iterable<String?> fields) {
  final haystack = fields.nonNulls.join('\n').toLowerCase();
  return query
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .every(haystack.contains);
}

class OfflineException implements Exception {
  const OfflineException(this.what);

  final String what;

  @override
  String toString() => '$what is not available offline';
}

/// Reads from the server and writes every response to the cache. When the server cannot be reached, or the app is offline, it reads from the cache.
class LibraryRepository {
  LibraryRepository(this.client, this.db, {required this.isOffline});

  final SubsonicClient client;
  final AppDatabase db;
  final bool Function() isOffline;

  /// Stores [json] unless the cache already holds the same text, so repeated fetches of an unchanged item write nothing.
  Future<void> _put(String kind, String id, Object json) async {
    final text = jsonEncode(json);
    final existing = await (db.select(
      db.cachedItems,
    )..where((t) => t.kind.equals(kind) & t.id.equals(id))).getSingleOrNull();
    if (existing?.json == text) return;
    await db
        .into(db.cachedItems)
        .insertOnConflictUpdate(
          CachedItemsCompanion.insert(
            kind: kind,
            id: id,
            json: text,
            updatedAt: DateTime.now(),
          ),
        );
  }

  Future<Object?> _cached(String kind, String id) async {
    final row = await (db.select(
      db.cachedItems,
    )..where((t) => t.kind.equals(kind) & t.id.equals(id))).getSingleOrNull();
    return row == null ? null : jsonDecode(row.json);
  }

  Future<T> _fetch<T>({
    required String kind,
    required String id,
    required Future<T> Function() remote,
    required Object Function(T) encode,
    required T Function(Object) decode,
    Future<void> Function(T)? alsoCache,
  }) async {
    if (!isOffline()) {
      try {
        final value = await remote();
        await _put(kind, id, encode(value));
        if (alsoCache != null) await alsoCache(value);
        return value;
      } on SocketException {
        // Fall through to the cache.
      } on TimeoutException {
        // Fall through to the cache.
      } on SubsonicException catch (e) {
        if (e.code != 0 && e.code < 500) rethrow;
      }
    }
    final cached = await _cached(kind, id);
    if (cached == null) throw OfflineException('$kind $id');
    return decode(cached);
  }

  Future<void> cacheTracks(Iterable<Track> tracks) => db.batch((b) {
    final now = DateTime.now();
    b.insertAllOnConflictUpdate(db.cachedItems, [
      for (final t in tracks)
        CachedItemsCompanion.insert(
          kind: 'track',
          id: t.id,
          json: jsonEncode(t.json),
          updatedAt: now,
        ),
    ]);
  });

  Future<Album> album(String id) => _fetch(
    kind: 'album',
    id: id,
    remote: () => client.getAlbum(id),
    encode: (a) => a.json,
    decode: (j) => Album(j as Json),
    alsoCache: (a) => cacheTracks(a.songs),
  );

  Future<Artist> artist(String id) => _fetch(
    kind: 'artist',
    id: id,
    remote: () => client.getArtist(id),
    encode: (a) => a.json,
    decode: (j) => Artist(j as Json),
  );

  Future<Playlist> playlist(String id) => _fetch(
    kind: 'playlist',
    id: id,
    remote: () => client.getPlaylist(id),
    encode: (p) => p.json,
    decode: (j) => Playlist(j as Json),
    alsoCache: (p) => cacheTracks(p.entries),
  );

  Future<Track> track(String id) => _fetch(
    kind: 'track',
    id: id,
    remote: () => client.getSong(id),
    encode: (t) => t.json,
    decode: (j) => Track(j as Json),
  );

  /// The lyrics of [id], from the cache when the server cannot be reached. Null when the song has none, the server offers none or they were never loaded online.
  Future<Lyrics?> lyrics(String id) async {
    if (!isOffline() && !await client.supports('songLyrics')) return null;
    try {
      return await _fetch<Lyrics?>(
        kind: 'lyrics',
        id: id,
        remote: () => client.getLyricsBySongId(id),
        encode: (l) => l?.json ?? const <String, dynamic>{},
        decode: (j) => (j as Json).isEmpty ? null : Lyrics(j),
      );
    } on OfflineException {
      return null;
    }
  }

  Future<List<Artist>> artists() => _fetch(
    kind: 'list',
    id: 'artists',
    remote: client.getArtists,
    encode: (l) => [for (final a in l) a.json],
    decode: (j) => jsonList(j).map(Artist.new).toList(),
  );

  Future<List<Playlist>> playlists() => _fetch(
    kind: 'list',
    id: 'playlists',
    remote: client.getPlaylists,
    encode: (l) => [for (final p in l) p.json],
    decode: (j) => jsonList(j).map(Playlist.new).toList(),
  );

  Future<List<Album>> albumList(
    String type, {
    int size = 50,
    int offset = 0,
    String? genre,
    int? fromYear,
    int? toYear,
  }) => _fetch(
    kind: 'list',
    id: _albumListKey(type, size, offset, genre, fromYear, toYear),
    remote: () => client.getAlbumList(
      type,
      size: size,
      offset: offset,
      genre: genre,
      fromYear: fromYear,
      toYear: toYear,
    ),
    encode: (l) => [for (final a in l) a.json],
    decode: (j) => jsonList(j).map(Album.new).toList(),
  );

  static String _albumListKey(
    String type,
    int size,
    int offset, [
    String? genre,
    int? fromYear,
    int? toYear,
  ]) =>
      'albums:$type:$size:$offset:${genre ?? ''}:${fromYear ?? ''}:${toYear ?? ''}';

  /// The cached first page of an album list, without asking the server.
  Future<List<Album>?> cachedAlbumList(
    String type, {
    int size = 50,
    String? genre,
    int? fromYear,
    int? toYear,
  }) async {
    final json = await _cached(
      'list',
      _albumListKey(type, size, 0, genre, fromYear, toYear),
    );
    return json == null ? null : jsonList(json).map(Album.new).toList();
  }

  /// The cached artists, without asking the server.
  Future<List<Artist>?> cachedArtists() async {
    final json = await _cached('list', 'artists');
    return json == null ? null : jsonList(json).map(Artist.new).toList();
  }

  /// Albums whose name or artist matches [query]: from the server, or from the cache offline.
  Future<List<Album>> searchAlbums(String query, {int count = 200}) async {
    if (isOffline()) return (await searchOffline(query)).albums;
    final result = await client.search(
      query,
      artistCount: 0,
      albumCount: count,
      songCount: 0,
    );
    return result.albums;
  }

  /// The cached playlists, without asking the server.
  Future<List<Playlist>?> cachedPlaylists() async {
    final json = await _cached('list', 'playlists');
    return json == null ? null : jsonList(json).map(Playlist.new).toList();
  }

  /// The cached playlist [id] with its tracks, without asking the server. A downloaded playlist always has one.
  Future<Playlist?> cachedPlaylist(String id) async {
    final json = await _cached('playlist', id);
    return json == null ? null : Playlist(json as Json);
  }

  Future<ArtistInfo> artistInfo(String id) => _fetch(
    kind: 'artistInfo',
    id: id,
    remote: () => client.getArtistInfo(id),
    encode: (i) => i.json,
    decode: (j) => ArtistInfo(j as Json),
  );

  Future<List<Genre>> genres() => _fetch(
    kind: 'list',
    id: 'genres',
    remote: client.getGenres,
    encode: (l) => [for (final g in l) g.json],
    decode: (j) => jsonList(j).map(Genre.new).toList(),
  );

  Future<SearchResult> search(String query) async {
    if (isOffline()) return searchOffline(query);
    return client.search(query);
  }

  /// Searches the cached tracks, albums and artists by name.
  Future<SearchResult> searchOffline(String query) async {
    final pattern = '%${query.replaceAll('%', '')}%';
    final rows =
        await (db.select(db.cachedItems)
              ..where(
                (t) =>
                    t.kind.isIn(['track', 'album', 'artist']) &
                    t.json.like(pattern),
              )
              ..limit(200))
            .get();
    final lower = query.toLowerCase();
    bool matches(String? s) => s != null && s.toLowerCase().contains(lower);
    final artists = <Artist>[], albums = <Album>[], tracks = <Track>[];
    for (final row in rows) {
      final json = jsonDecode(row.json) as Json;
      switch (row.kind) {
        case 'artist' when matches(Artist(json).name):
          artists.add(Artist(json));
        case 'album' when matches(Album(json).name):
          albums.add(Album(json));
        case 'track' when matches(Track(json).title):
          tracks.add(Track(json));
      }
    }
    return SearchResult(artists: artists, albums: albums, tracks: tracks);
  }

  /// Cached metadata of the given tracks, in the order of [ids]. Unknown IDs are skipped.
  Future<List<Track>> cachedTracks(Iterable<String> ids) async {
    final idList = ids.toList();
    final rows = await (db.select(
      db.cachedItems,
    )..where((t) => t.kind.equals('track') & t.id.isIn(idList))).get();
    final byId = {
      for (final r in rows) r.id: Track(jsonDecode(r.json) as Json),
    };
    return [for (final id in idList) ?byId[id]];
  }

  /// Empties the cache except what downloads need offline, then reloads that part from the server. Kept are the tracks with a file, their albums and artists, and the downloaded playlists and artists. [onProgress] receives the number of reloaded items and their total.
  Future<void> refreshCache({
    void Function(int done, int total)? onProgress,
  }) async {
    final trackIds = (await db.select(db.trackFiles).get())
        .map((f) => f.trackId)
        .toSet();
    final tracks = await cachedTracks(trackIds);
    final pins = await db.select(db.pins).get();
    Set<String> pinned(String kind) => {
      for (final pin in pins)
        if (pin.kind == kind) pin.itemId,
    };
    final albums = {
      ...pinned('album'),
      ...tracks.map((t) => t.albumId).nonNulls,
    };
    final artists = {
      ...pinned('artist'),
      ...tracks.map((t) => t.artistId).nonNulls,
    };
    final playlists = pinned('playlist');

    await (db.delete(db.cachedItems)..where(
          (t) =>
              (t.kind.equals('track') & t.id.isIn(trackIds)).not() &
              (t.kind.equals('album') & t.id.isIn(albums)).not() &
              (t.kind.equals('artist') & t.id.isIn(artists)).not() &
              (t.kind.equals('playlist') & t.id.isIn(playlists)).not(),
        ))
        .go();

    final reloads = <Future<void> Function()>[
      for (final id in albums) () => album(id),
      for (final id in artists) () => artist(id),
      for (final id in playlists) () => playlist(id),
    ];
    var done = 0;
    onProgress?.call(done, reloads.length);
    const parallel = 4;
    for (var i = 0; i < reloads.length; i += parallel) {
      await Future.wait([
        for (final reload in reloads.skip(i).take(parallel))
          reload().then<void>((_) {}, onError: (Object _) {}),
      ]);
      done = (i + parallel).clamp(0, reloads.length);
      onProgress?.call(done, reloads.length);
    }
  }

  Future<Album?> cachedAlbum(String id) async {
    final json = await _cached('album', id);
    return json == null ? null : Album(json as Json);
  }

  /// The cached albums among [ids], by ID, read in one query.
  Future<Map<String, Album>> cachedAlbums(Iterable<String> ids) async {
    final idList = ids.toList();
    final rows = await (db.select(
      db.cachedItems,
    )..where((t) => t.kind.equals('album') & t.id.isIn(idList))).get();
    return {for (final r in rows) r.id: Album(jsonDecode(r.json) as Json)};
  }

  /// The albums [ids] from the server, [parallel] requests at a time, by ID. Albums that cannot be loaded are left out.
  Future<Map<String, Album>> albums(
    Iterable<String> ids, {
    int parallel = 4,
  }) async {
    final idList = ids.toList();
    final result = <String, Album>{};
    for (var i = 0; i < idList.length; i += parallel) {
      await Future.wait([
        for (final id in idList.skip(i).take(parallel))
          album(id).then<void>((a) => result[id] = a, onError: (Object _) {}),
      ]);
    }
    return result;
  }

  Future<Artist?> cachedArtist(String id) async {
    final json = await _cached('artist', id);
    return json == null ? null : Artist(json as Json);
  }

  /// The cached genres, without asking the server.
  Future<List<Genre>?> cachedGenres() async {
    final json = await _cached('list', 'genres');
    return json == null ? null : jsonList(json).map(Genre.new).toList();
  }

  /// A mix starting from [seed] and continuing with songs that sound like it, from the sonic analysis of the server. Requires the `sonicSimilarity` extension.
  Future<List<Track>> instantMix(Track seed, {int count = 50}) async {
    final similar = await client.getSonicSimilarTracks(seed.id, count: count);
    final mix = [seed, ...similar.where((t) => t.id != seed.id)];
    await cacheTracks(mix);
    return mix;
  }

  /// The most played songs of the artist [artistId]. Requires the `topSongsByArtistId` extension.
  Future<List<Track>> topSongs(String artistId, {int count = 10}) async {
    final tracks = await client.getTopSongs(artistId, count: count);
    await cacheTracks(tracks);
    return tracks;
  }

  /// Songs similar to an album or artist [id], for radio.
  Future<List<Track>> radio({
    String? artistId,
    String? albumId,
    int count = 50,
  }) async {
    final tracks = artistId != null
        ? await client.getSimilarSongs2(artistId, count: count)
        : await client.getSimilarSongs(albumId!, count: count);
    await cacheTracks(tracks);
    return tracks;
  }

  Future<void> setStarred({
    required bool starred,
    String? trackId,
    String? albumId,
    String? artistId,
  }) => starred
      ? client.star(trackId: trackId, albumId: albumId, artistId: artistId)
      : client.unstar(trackId: trackId, albumId: albumId, artistId: artistId);
}
