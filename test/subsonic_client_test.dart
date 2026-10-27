import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:puffer/data/subsonic/subsonic_client.dart';

void main() {
  late List<Uri> requests;
  late SubsonicClient client;

  setUp(() {
    requests = [];
    client = SubsonicClient(
      const ServerCredentials(
        baseUrl: 'http://navidrome',
        username: 'u',
        token: 't',
        salt: 's',
      ),
      httpClient: MockClient((request) async {
        requests.add(request.url);
        return http.Response(
          jsonEncode({
            'subsonic-response': {'status': 'ok'},
          }),
          200,
        );
      }),
    );
  });

  test(
    'reordering replaces the songs of the playlist in the new order',
    () async {
      await client.createPlaylist(playlistId: 'p1', songIds: ['b', 'a']);
      final url = requests.single;
      expect(url.pathSegments.last, 'createPlaylist');
      expect(url.queryParameters['playlistId'], 'p1');
      expect(url.queryParametersAll['songId'], ['b', 'a']);
      expect(url.queryParameters.containsKey('name'), isFalse);
    },
  );

  test('adding and removing send one parameter per song', () async {
    await client.updatePlaylist(
      'p1',
      songIdsToAdd: ['x', 'y'],
      songIndexesToRemove: [3],
    );
    final url = requests.single;
    expect(url.queryParametersAll['songIdToAdd'], ['x', 'y']);
    expect(url.queryParametersAll['songIndexToRemove'], ['3']);
  });

  test('renaming sends only the name', () async {
    await client.updatePlaylist('p1', name: 'Road trip');
    final url = requests.single;
    expect(url.queryParameters['name'], 'Road trip');
    expect(url.queryParametersAll.containsKey('songIdToAdd'), isFalse);
  });

  test('album lists by genre and by years send their filters', () async {
    await client.getAlbumList('byGenre', genre: 'Jazz');
    await client.getAlbumList('byYear', fromYear: 1990, toYear: 1999);
    expect(requests[0].queryParameters['genre'], 'Jazz');
    expect(requests[0].queryParameters.containsKey('fromYear'), isFalse);
    expect(requests[1].queryParameters['fromYear'], '1990');
    expect(requests[1].queryParameters['toYear'], '1999');
  });
}
