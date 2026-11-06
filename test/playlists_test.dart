import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:puffer/app/playlist_history.dart';
import 'package:puffer/data/repositories/library_repository.dart';
import 'package:puffer/data/subsonic/models.dart';
import 'package:puffer/data/subsonic/subsonic_client.dart';
import 'package:puffer/features/collection/add_songs_sheet.dart';
import 'package:puffer/features/collection/playlist_edit.dart';

http.Response _ok([Map<String, Object?> body = const {}]) => http.Response(
  jsonEncode({
    'subsonic-response': {'status': 'ok', ...body},
  }),
  200,
);

SubsonicClient _client(
  List<http.Request> sent, {
  List<String> extensions = const [],
}) => SubsonicClient(
  const ServerCredentials(
    baseUrl: 'http://navidrome',
    username: 'u',
    token: 't',
    salt: 's',
  ),
  httpClient: MockClient((request) async {
    if (request.url.path.endsWith('getOpenSubsonicExtensions')) {
      return _ok({
        'openSubsonicExtensions': [
          for (final e in extensions)
            {
              'name': e,
              'versions': [1],
            },
        ],
      });
    }
    sent.add(request);
    return _ok();
  }),
);

void main() {
  group('saving songs to a playlist', () {
    test('with formPost the song IDs go in a form body', () async {
      final sent = <http.Request>[];
      final client = _client(sent, extensions: ['formPost']);
      await client.loadExtensions();
      final ids = [for (var i = 0; i < 2000; i++) 'song-$i'];
      await client.createPlaylist(name: 'Long', songIds: ids);
      final request = sent.single;
      expect(request.method, 'POST');
      expect(request.url.query, isEmpty);
      final form = Uri.splitQueryString(request.body);
      expect(form['name'], 'Long');
      expect(form['t'], 't');
      expect(
        RegExp('songId=').allMatches(request.body).length,
        2000,
        reason: 'every song is sent, in a repeated field',
      );
    });

    test('without formPost they go in the URL', () async {
      final sent = <http.Request>[];
      final client = _client(sent);
      await client.loadExtensions();
      await client.createPlaylist(name: 'Short', songIds: ['a', 'b']);
      final request = sent.single;
      expect(request.method, 'GET');
      expect(request.url.queryParametersAll['songId'], ['a', 'b']);
    });

    test('the description and visibility are sent', () async {
      final sent = <http.Request>[];
      final client = _client(sent);
      await client.loadExtensions();
      await client.updatePlaylist('p1', comment: 'Road trip', isPublic: true);
      final query = sent.single.url.queryParameters;
      expect(query['comment'], 'Road trip');
      expect(query['public'], 'true');
      expect(query['playlistId'], 'p1');
    });
  });

  test('songs already in the playlist are told apart', () {
    final split = splitDuplicates(['a', 'b', 'c'], ['b', 'x']);
    expect(split.fresh, ['a', 'c']);
    expect(split.duplicates, 1);
    expect(splitDuplicates(['a'], const []).duplicates, 0);
  });

  test('a playlist reads its description and visibility', () {
    const p = Playlist({
      'id': 'p',
      'comment': '  For the road ',
      'public': true,
    });
    expect(p.comment, 'For the road');
    expect(p.isPublic, isTrue);
    expect(const Playlist({'id': 'p', 'comment': ' '}).comment, isNull);
    expect(const Playlist({'id': 'p'}).isPublic, isFalse);
  });

  test('the mosaic takes the first four different covers', () {
    final tracks = [
      for (final c in ['a', 'a', null, 'b', 'c', 'b', 'd', 'e'])
        Track({'id': 'x', 'title': 'x', 'coverArt': ?c}),
    ];
    expect(playlistCovers(tracks), ['a', 'b', 'c', 'd']);
    expect(playlistCovers(tracks.take(2)), ['a']);
  });

  group('playlist sorting', () {
    final playlists = [
      const Playlist({
        'id': '1',
        'name': 'beta',
        'songCount': 10,
        'changed': '2026-01-01T00:00:00Z',
      }),
      const Playlist({
        'id': '2',
        'name': 'Alpha',
        'songCount': 10,
        'changed': '2026-03-01T00:00:00Z',
      }),
      const Playlist({
        'id': '3',
        'name': 'gamma',
        'songCount': 99,
        'changed': '2026-02-01T00:00:00Z',
      }),
    ];
    List<String> names(PlaylistSort sort) => [
      for (final p in sortPlaylists(playlists, sort, const {})) p.name,
    ];

    test('most songs first, ties by name', () {
      expect(names(PlaylistSort.songs), ['gamma', 'Alpha', 'beta']);
    });

    test('recently changed first', () {
      expect(names(PlaylistSort.changed), ['Alpha', 'gamma', 'beta']);
    });
  });

  test('songs tapped in the sheet are added one after another', () async {
    final order = <String>[];
    final adder = PlaylistAdder((id) async {
      await Future<void>.delayed(Duration(milliseconds: id == 'a' ? 20 : 1));
      if (id == 'bad') throw Exception('nope');
      order.add(id);
    }, ['old']);
    expect(adder.added, {'old'});
    final a = adder.add('a');
    final b = adder.add('b');
    final bad = adder.add('bad');
    expect(adder.added, containsAll(['a', 'b', 'bad']));
    await Future.wait([a, b, bad]);
    expect(order, ['a', 'b']);
    expect(
      adder.added.contains('bad'),
      isFalse,
      reason: 'a failed add shows no check',
    );
    expect(adder.changed, isTrue);
  });
}
