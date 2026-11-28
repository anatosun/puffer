import 'dart:async';

import 'package:audio_service/audio_service.dart';

import '../data/repositories/library_repository.dart';
import '../data/subsonic/models.dart';

/// Plays [tracks] on this device from [index].
typedef CarPlay = Future<void> Function(
  List<Track> tracks, {
  int index,
  bool shuffle,
});

const _browsableHint = 'android.media.browse.CONTENT_STYLE_BROWSABLE_HINT';
const _playableHint = 'android.media.browse.CONTENT_STYLE_PLAYABLE_HINT';

/// Extras of an item whose children show as a list rather than a grid.
const _listChildren = {_browsableHint: 1};

/// Extras of the browse root: the car offers search, browsable children show as a grid and songs as a list.
const carRootExtras = <String, dynamic>{
  'android.media.browse.SEARCH_SUPPORTED': true,
  _browsableHint: 2,
  _playableHint: 1,
};

/// Whether a car shows [children] of [parent] as a grid, by the content-style hints of [parent] or else of the root. A list mixing items that open and items that play, as search gives, shows as a list.
bool carShowsGrid(MediaItem? parent, List<MediaItem> children) {
  if (children.isEmpty) return false;
  final String key;
  if (children.every((c) => c.playable == false)) {
    key = _browsableHint;
  } else if (children.every((c) => c.playable == true)) {
    key = _playableHint;
  } else {
    return false;
  }
  return (parent?.extras?[key] ?? carRootExtras[key]) == 2;
}

/// The library as a car browses it through the media session (Android Auto). It reads only from [repository], so it shows the cached library offline.
///
/// A media ID is a path of components, each percent-encoded so a Subsonic ID may hold any character: `album/<id>` lists the songs of an album and `album/<id>/<index>` plays it from a song; playlists follow the same form; `artist/<id>` lists the albums of an artist; `song/<id>` plays a song of a search result within its album. The tabs are `recentAlbums`, `playlists`, `artists` and `albums`. The system asks for [AudioService.recentRootId] to offer the queue again after a restart; its one item is `resume`.
class CarLibrary {
  CarLibrary({
    required this.repository,
    required this.play,
    required this.resume,
    required this.nowPlaying,
    required this.art,
    required this.prepareArt,
  });

  final LibraryRepository repository;
  final CarPlay play;

  /// Plays the queue that is loaded.
  final Future<void> Function() resume;

  /// The song loaded in the player, if any.
  final MediaItem? Function() nowPlaying;

  /// A URI the car can read for the artwork of [coverArt], when it is on this device.
  final Uri? Function(String? coverArt) art;

  /// Fetches the artwork of [coverArts] to this device, so [art] finds it.
  final Future<void> Function(Iterable<String?> coverArts) prepareArt;

  /// How long a list waits for its artwork. Covers that arrive later show the next time the list opens.
  static const artBudget = Duration(seconds: 2);

  /// Lists of albums and artists are cut at this length, which a driver never scrolls to the end of.
  static const maxItems = 300;

  static const resumeId = 'resume';

  Future<List<MediaItem>> children(String parentId) async {
    final parts = _parts(parentId);
    try {
      return await switch (parts) {
        [AudioService.browsableRootId] => Future.value(_tabs),
        [AudioService.recentRootId] => Future.value(_resumeItems()),
        ['recentAlbums'] => _albums(await repository.albumList('recent')),
        ['albums'] => _albums(
          await repository.albumList('alphabeticalByName', size: 500),
        ),
        ['playlists'] => _playlists(await repository.playlists()),
        ['artists'] => _artists(await repository.artists()),
        ['artist', final id] => _albums((await repository.artist(id)).albums),
        ['album', final id] => _songs(
          (await repository.album(id)).songs,
          (i) => _id(['album', id, '$i']),
        ),
        ['playlist', final id] => _songs(
          (await repository.playlist(id)).entries,
          (i) => _id(['playlist', id, '$i']),
        ),
        _ => Future.value(const <MediaItem>[]),
      };
    } on Object {
      // Offline, an item never opened before has nothing cached.
      return const [];
    }
  }

  Future<void> playFromId(String mediaId) async {
    final parts = _parts(mediaId);
    switch (parts) {
      case [resumeId]:
        await resume();
      case ['album', final id, ...final rest]:
        await _playAt((await repository.album(id)).songs, rest);
      case ['playlist', final id, ...final rest]:
        await _playAt((await repository.playlist(id)).entries, rest);
      case ['song', final id]:
        await _playSong(await repository.track(id));
    }
  }

  Future<List<MediaItem>> search(String query) async {
    if (query.trim().isEmpty) return const [];
    try {
      final result = _library(await repository.search(query));
      final songs = result.tracks.take(10).toList();
      final albums = result.albums.take(10).toList();
      final artists = result.artists.take(10).toList();
      await _prepare([
        ...songs.map((t) => t.coverArt),
        ...albums.map((a) => a.coverArt),
        ...artists.map((a) => a.coverArt),
      ]);
      return [
        for (final t in songs) _song(t, _id(['song', t.id])),
        for (final a in albums) _album(a),
        for (final a in artists) _artist(a),
      ];
    } on Object {
      return const [];
    }
  }

  /// Plays what a person asked for by voice. [extras] may name what the query is (`android.intent.extra.focus`) and the album or artist it names. An empty query plays the loaded queue, or else the album played last.
  Future<void> playFromSearch(
    String query, [
    Map<String, dynamic>? extras,
  ]) async {
    if (query.trim().isEmpty) {
      if (nowPlaying() != null) return resume();
      final recent = await repository.albumList('recent', size: 1);
      if (recent.isNotEmpty) {
        await play((await repository.album(recent.first.id)).songs);
      }
      return;
    }
    final focus = extras?['android.intent.extra.focus'] as String?;
    final named = switch (focus) {
      _albumFocus => extras?['android.intent.extra.album'],
      _artistFocus => extras?['android.intent.extra.artist'],
      _ => null,
    };
    final result = _library(
      await repository.search(named is String ? named : query),
    );
    final artist = result.artists.firstOrNull;
    final album = result.albums.firstOrNull;
    final song = result.tracks.firstOrNull;
    if (focus == _artistFocus && artist != null) {
      return _playArtist(artist.id);
    }
    if (focus == _albumFocus && album != null) {
      return play((await repository.album(album.id)).songs);
    }
    if (song != null) return _playSong(song);
    if (album != null) return play((await repository.album(album.id)).songs);
    if (artist != null) return _playArtist(artist.id);
  }

  /// The results of the library itself: the car leaves out what a server such as octo-fiesta offers from outside it.
  static SearchResult _library(SearchResult result) =>
      result.shown(showExternal: false).result;

  /// Shuffles the songs of the first albums of an artist, fetched one after the other.
  Future<void> _playArtist(String id) async {
    final albums = (await repository.artist(id)).albums.take(10);
    final songs = <Track>[];
    for (final a in albums) {
      songs.addAll((await repository.album(a.id)).songs);
    }
    if (songs.isNotEmpty) await play(songs, shuffle: true);
  }

  /// Plays [track] within its album, so the album goes on after it; alone when the album cannot be had.
  Future<void> _playSong(Track track) async {
    final albumId = track.albumId;
    List<Track> songs = const [];
    if (albumId != null) {
      try {
        songs = (await repository.album(albumId)).songs;
      } on Object {
        // Plays the song alone.
      }
    }
    final index = songs.indexWhere((t) => t.id == track.id);
    if (index >= 0) return play(songs, index: index);
    await play([track]);
  }

  Future<void> _playAt(List<Track> tracks, List<String> rest) async {
    if (tracks.isEmpty) return;
    final index = rest.isEmpty ? 0 : int.tryParse(rest.first) ?? 0;
    await play(tracks, index: index.clamp(0, tracks.length - 1));
  }

  static const _tabs = [
    MediaItem(id: 'recentAlbums', title: 'Recent', playable: false),
    MediaItem(
      id: 'playlists',
      title: 'Playlists',
      playable: false,
      extras: _listChildren,
    ),
    MediaItem(
      id: 'artists',
      title: 'Artists',
      playable: false,
      extras: _listChildren,
    ),
    MediaItem(id: 'albums', title: 'Albums', playable: false),
  ];

  List<MediaItem> _resumeItems() {
    final item = nowPlaying();
    return item == null ? const [] : [item.copyWith(id: resumeId)];
  }

  Future<List<MediaItem>> _albums(List<Album> albums) async {
    final shown = albums.take(maxItems).toList();
    await _prepare(shown.map((a) => a.coverArt));
    return [for (final a in shown) _album(a)];
  }

  Future<List<MediaItem>> _artists(List<Artist> artists) async {
    final shown = artists.take(maxItems).toList();
    await _prepare(shown.map((a) => a.coverArt));
    return [for (final a in shown) _artist(a)];
  }

  Future<List<MediaItem>> _playlists(List<Playlist> playlists) async {
    await _prepare(playlists.map((p) => p.coverArt));
    return [
      for (final p in playlists)
        MediaItem(
          id: _id(['playlist', p.id]),
          title: p.name,
          artUri: art(p.coverArt),
          playable: false,
        ),
    ];
  }

  Future<List<MediaItem>> _songs(
    List<Track> tracks,
    String Function(int index) id,
  ) async {
    await _prepare(tracks.map((t) => t.coverArt));
    return [for (final (i, t) in tracks.indexed) _song(t, id(i))];
  }

  MediaItem _album(Album a) => MediaItem(
    id: _id(['album', a.id]),
    title: a.name,
    artist: a.artist,
    artUri: art(a.coverArt),
    playable: false,
  );

  MediaItem _artist(Artist a) => MediaItem(
    id: _id(['artist', a.id]),
    title: a.name,
    artUri: art(a.coverArt),
    playable: false,
  );

  MediaItem _song(Track t, String id) => MediaItem(
    id: id,
    title: t.title,
    artist: t.artist,
    album: t.album,
    duration: t.duration,
    artUri: art(t.coverArt),
    playable: true,
  );

  /// Fetches the covers of a list within [artBudget]. The covers of an album's songs are mostly one, so each is asked for once.
  Future<void> _prepare(Iterable<String?> coverArts) async {
    final missing = {
      for (final c in coverArts.nonNulls)
        if (art(c) == null) c,
    };
    if (missing.isEmpty) return;
    await prepareArt(missing).timeout(artBudget, onTimeout: () {});
  }
}

const _albumFocus = 'vnd.android.cursor.item/album';
const _artistFocus = 'vnd.android.cursor.item/artist';

String _id(List<String> parts) => parts.map(Uri.encodeComponent).join('/');

List<String> _parts(String id) =>
    id.split('/').map(Uri.decodeComponent).toList();
