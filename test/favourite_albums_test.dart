import 'package:flutter_test/flutter_test.dart';
import 'package:puffer/data/subsonic/models.dart';

Track _song(String id, String albumId) => Track({
  'id': id,
  'title': 'Song $id',
  'album': 'Album $albumId',
  'albumId': albumId,
  'artist': 'Artist',
  'coverArt': 'al-$albumId',
});

void main() {
  test('starred albums come first, then the albums of starred songs', () {
    final albums = favouriteAlbums(
      Starred(
        artists: const [],
        albums: [
          Album({'id': 'a1', 'name': 'One'}),
        ],
        tracks: [_song('s1', 'a2'), _song('s2', 'a1'), _song('s3', 'a2')],
      ),
    );
    expect([for (final a in albums) a.id], ['a1', 'a2']);
    // An album known only from its song takes the song's name, artist and cover.
    expect(albums[1].name, 'Album a2');
    expect(albums[1].artist, 'Artist');
    expect(albums[1].coverArt, 'al-a2');
  });

  test('the cache gives the full album of a starred song', () {
    final albums = favouriteAlbums(
      Starred(artists: const [], albums: const [], tracks: [_song('s1', 'a2')]),
      known: {
        'a2': Album({'id': 'a2', 'name': 'Two', 'songCount': 12}),
      },
    );
    expect(albums.single.name, 'Two');
    expect(albums.single.songCount, 12);
  });

  test('a starred song without an album adds none', () {
    final albums = favouriteAlbums(
      Starred(
        artists: const [],
        albums: const [],
        tracks: [
          Track({'id': 's1', 'title': 'Loose'}),
        ],
      ),
    );
    expect(albums, isEmpty);
  });
}
