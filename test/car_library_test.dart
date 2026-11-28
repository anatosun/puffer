import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:puffer/data/repositories/library_repository.dart';
import 'package:puffer/data/subsonic/models.dart';
import 'package:puffer/playback/car_library.dart';

class _Repo extends Mock implements LibraryRepository {}

Map<String, dynamic> _song(String id, {String? albumId, String? cover}) => {
  'id': id,
  'title': 'Song $id',
  'albumId': ?albumId,
  'coverArt': ?cover,
};

Album _album(String id, List<String> songs, {String? cover}) => Album({
  'id': id,
  'name': 'Album $id',
  'coverArt': ?cover,
  'song': [for (final s in songs) _song(s, albumId: id, cover: cover)],
});

/// The IDs of [tracks] as one string: two lists are never equal, so records holding them cannot be compared.
String _ids(List<Track> tracks) => tracks.map((t) => t.id).join(' ');

void main() {
  late _Repo repo;
  late List<(String, int, bool)> played;
  late int resumed;
  late MediaItem? loaded;
  late Set<String> artOnDevice;
  late List<List<String?>> asked;

  CarLibrary library() => CarLibrary(
    repository: repo,
    play: (tracks, {index = 0, shuffle = false}) async =>
        played.add((_ids(tracks), index, shuffle)),
    resume: () async => resumed++,
    nowPlaying: () => loaded,
    art: (c) => artOnDevice.contains(c) ? Uri.parse('content://art/$c') : null,
    prepareArt: (covers) async {
      asked.add(covers.toList());
      artOnDevice.addAll(covers.nonNulls);
    },
  );

  void albumIs(Album album) =>
      when(() => repo.album(album.id)).thenAnswer((_) async => album);
  void trackIs(Track track) =>
      when(() => repo.track(track.id)).thenAnswer((_) async => track);

  setUp(() {
    repo = _Repo();
    played = [];
    resumed = 0;
    loaded = null;
    artOnDevice = {};
    asked = [];
  });

  test('the root has four tabs, all browsable', () async {
    final tabs = await library().children(AudioService.browsableRootId);
    expect(
      [for (final t in tabs) t.id],
      ['recentAlbums', 'playlists', 'artists', 'albums'],
    );
    expect(tabs.every((t) => t.playable == false), isTrue);
  });

  test('an album lists its songs; a song plays the album from it', () async {
    albumIs(_album('a1', ['x', 'y', 'z']));
    final car = library();
    final songs = await car.children('album/a1');
    expect(
      [for (final s in songs) s.id],
      ['album/a1/0', 'album/a1/1', 'album/a1/2'],
    );
    expect(songs.every((s) => s.playable == true), isTrue);
    await car.playFromId(songs[1].id);
    expect(played, [('x y z', 1, false)]);
  });

  test('IDs holding a slash or a colon survive the media ID', () async {
    albumIs(_album('al/1:2', ['s']));
    final car = library();
    final songs = await car.children('album/${Uri.encodeComponent('al/1:2')}');
    await car.playFromId(songs.single.id);
    expect(played.single.$1, 's');
    verify(() => repo.album('al/1:2')).called(2);
  });

  test('an artist lists its albums, which open rather than play', () async {
    when(() => repo.artist('r')).thenAnswer(
      (_) async => Artist({
        'id': 'r',
        'name': 'R',
        'album': [
          {'id': 'a1', 'name': 'One'},
          {'id': 'a2', 'name': 'Two'},
        ],
      }),
    );
    final albums = await library().children('artist/r');
    expect([for (final a in albums) a.id], ['album/a1', 'album/a2']);
    expect(albums.every((a) => a.playable == false), isTrue);
  });

  test('offline, an item with nothing cached lists nothing', () async {
    when(() => repo.playlist('p')).thenThrow(Exception('offline'));
    expect(await library().children('playlist/p'), isEmpty);
  });

  test('a song found by search plays within its album', () async {
    trackIs(Track(_song('y', albumId: 'a1')));
    albumIs(_album('a1', ['x', 'y']));
    await library().playFromId('song/y');
    expect(played, [('x y', 1, false)]);
  });

  test('a song whose album cannot be had plays alone', () async {
    trackIs(Track(_song('y', albumId: 'a1')));
    when(() => repo.album('a1')).thenThrow(Exception('offline'));
    await library().playFromId('song/y');
    expect(played, [('y', 0, false)]);
  });

  test('the recent root offers the loaded song, which resumes', () async {
    final car = library();
    expect(await car.children(AudioService.recentRootId), isEmpty);
    loaded = const MediaItem(id: 'x', title: 'Song x');
    final items = await car.children(AudioService.recentRootId);
    expect(items.single.id, CarLibrary.resumeId);
    expect(items.single.title, 'Song x');
    await car.playFromId(items.single.id);
    expect(resumed, 1);
  });

  test('a list fetches each missing cover once, and shows it', () async {
    artOnDevice = {'known'};
    albumIs(_album('a1', ['x', 'y'], cover: 'c1'));
    final songs = await library().children('album/a1');
    expect(asked, [
      ['c1'],
    ]);
    final art = Uri.parse('content://art/c1');
    expect(songs.every((s) => s.artUri == art), isTrue);
  });

  test('a list does not wait long for its covers', () async {
    albumIs(_album('a1', ['x'], cover: 'c1'));
    final car = CarLibrary(
      repository: repo,
      play: (tracks, {index = 0, shuffle = false}) async {},
      resume: () async {},
      nowPlaying: () => null,
      art: (_) => null,
      prepareArt: (_) => Future.delayed(const Duration(minutes: 1)),
    );
    final songs = await car
        .children('album/a1')
        .timeout(CarLibrary.artBudget * 2);
    expect(songs.single.artUri, isNull);
  });

  test('search gives songs, albums and artists', () async {
    when(() => repo.search('q')).thenAnswer(
      (_) async => SearchResult(
        artists: [
          Artist({'id': 'r', 'name': 'R'}),
        ],
        albums: [_album('a1', [])],
        tracks: [Track(_song('y'))],
      ),
    );
    final items = await library().search('q');
    expect([for (final i in items) i.id], ['song/y', 'album/a1', 'artist/r']);
    expect([for (final i in items) i.playable], [true, false, false]);
  });

  group('voice', () {
    test('an empty request resumes the loaded queue', () async {
      loaded = const MediaItem(id: 'x', title: 'Song x');
      await library().playFromSearch('');
      expect(resumed, 1);
    });

    test('an empty request with nothing loaded plays the last album', () async {
      when(() => repo.albumList('recent', size: 1))
          .thenAnswer((_) async => [_album('a1', [])]);
      albumIs(_album('a1', ['x', 'y']));
      await library().playFromSearch('');
      expect(played, [('x y', 0, false)]);
    });

    test('a request for an artist shuffles the songs of its albums', () async {
      when(() => repo.search('R')).thenAnswer(
        (_) async => SearchResult(
          artists: [
            Artist({'id': 'r', 'name': 'R'}),
          ],
          albums: const [],
          tracks: [Track(_song('other'))],
        ),
      );
      when(() => repo.artist('r')).thenAnswer(
        (_) async => Artist({
          'id': 'r',
          'album': [
            {'id': 'a1'},
            {'id': 'a2'},
          ],
        }),
      );
      albumIs(_album('a1', ['x']));
      albumIs(_album('a2', ['y']));
      await library().playFromSearch('play R', {
        'android.intent.extra.focus': 'vnd.android.cursor.item/artist',
        'android.intent.extra.artist': 'R',
      });
      expect(played, [('x y', 0, true)]);
    });

    test('a request without a focus plays the first song found', () async {
      when(() => repo.search('y')).thenAnswer(
        (_) async => SearchResult(
          artists: const [],
          albums: [_album('a2', [])],
          tracks: [Track(_song('y'))],
        ),
      );
      await library().playFromSearch('y');
      expect(played, [('y', 0, false)]);
    });
  });

  group('layout', () {
    test('albums show as a grid, artists and playlists as a list', () async {
      final tabs = await library().children(AudioService.browsableRootId);
      final albums = [
        const MediaItem(id: 'album/a', title: 'A', playable: false),
      ];
      final artists = [
        const MediaItem(id: 'artist/r', title: 'R', playable: false),
      ];
      expect(
        carShowsGrid(tabs.firstWhere((t) => t.id == 'albums'), albums),
        isTrue,
      );
      expect(
        carShowsGrid(tabs.firstWhere((t) => t.id == 'artists'), artists),
        isFalse,
      );
      expect(
        carShowsGrid(tabs.firstWhere((t) => t.id == 'playlists'), albums),
        isFalse,
      );
    });

    test('songs, and search results that mix kinds, show as a list', () {
      const song = MediaItem(id: 'album/a/0', title: 'S');
      const album = MediaItem(id: 'album/a', title: 'A', playable: false);
      expect(carShowsGrid(null, [song]), isFalse);
      expect(carShowsGrid(null, [song, album]), isFalse);
      expect(carShowsGrid(null, [album]), isTrue);
    });
  });
}
