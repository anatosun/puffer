import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';

import '../db/database.dart';
import '../subsonic/models.dart';
import '../subsonic/subsonic_client.dart';

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

  Future<void> _put(String kind, String id, Object json) => db
      .into(db.cachedItems)
      .insertOnConflictUpdate(
        CachedItemsCompanion.insert(
          kind: kind,
          id: id,
          json: jsonEncode(json),
          updatedAt: DateTime.now(),
        ),
      );

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
  Future<List<Album>?> cachedAlbumList(String type, {int size = 50}) async {
    final json = await _cached('list', _albumListKey(type, size, 0));
    return json == null ? null : jsonList(json).map(Album.new).toList();
  }

  /// The cached playlists, without asking the server.
  Future<List<Playlist>?> cachedPlaylists() async {
    final json = await _cached('list', 'playlists');
    return json == null ? null : jsonList(json).map(Playlist.new).toList();
  }

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

  Future<Album?> cachedAlbum(String id) async {
    final json = await _cached('album', id);
    return json == null ? null : Album(json as Json);
  }

  /// A mix starting from [seed] and continuing with songs that sound like it: from the sonic analysis of the server when it offers one, otherwise from its similar songs.
  Future<List<Track>> instantMix(Track seed, {int count = 50}) async {
    final similar = client.hasSonicSimilarity
        ? await client.getSonicSimilarTracks(seed.id, count: count)
        : await client.getSimilarSongs(seed.id, count: count);
    final mix = [seed, ...similar.where((t) => t.id != seed.id)];
    await cacheTracks(mix);
    return mix;
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
