import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:puffer/data/db/database.dart';
import 'package:puffer/data/repositories/library_repository.dart';
import 'package:puffer/data/subsonic/subsonic_client.dart';

void main() {
  test(
    'a fetched album list is readable from the cache without the server',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      var calls = 0;
      final client = SubsonicClient(
        const ServerCredentials(
          baseUrl: 'http://navidrome',
          username: 'u',
          token: 't',
          salt: 's',
        ),
        httpClient: MockClient((_) async {
          calls++;
          return http.Response(
            jsonEncode({
              'subsonic-response': {
                'status': 'ok',
                'albumList2': {
                  'album': [
                    {'id': 'a1', 'name': 'One'},
                  ],
                },
              },
            }),
            200,
          );
        }),
      );
      final repository = LibraryRepository(client, db, isOffline: () => false);
      expect(await repository.cachedAlbumList('newest', size: 20), isNull);
      await repository.albumList('newest', size: 20);
      expect(
        (await repository.cachedAlbumList('newest', size: 20))!.single.name,
        'One',
      );
      expect(calls, 1);
      await db.close();
    },
  );

  test('every word of a list search must match a field', () {
    expect(matchesQuery('dark side', ['The Dark Side of the Moon']), isTrue);
    expect(
      matchesQuery('floyd moon', ['The Dark Side of the Moon', 'Pink Floyd']),
      isTrue,
    );
    expect(
      matchesQuery('floyd wall', ['The Dark Side of the Moon', 'Pink Floyd']),
      isFalse,
    );
    expect(matchesQuery('  ', ['Anything']), isTrue);
    expect(matchesQuery('x', [null]), isFalse);
  });

  test('an album search asks the server for albums only', () async {
    final db = AppDatabase(NativeDatabase.memory());
    late Uri asked;
    final client = SubsonicClient(
      const ServerCredentials(
        baseUrl: 'http://navidrome',
        username: 'u',
        token: 't',
        salt: 's',
      ),
      httpClient: MockClient((request) async {
        asked = request.url;
        return http.Response(
          jsonEncode({
            'subsonic-response': {
              'status': 'ok',
              'searchResult3': {
                'album': [
                  {'id': 'a1', 'name': 'Moon'},
                ],
              },
            },
          }),
          200,
        );
      }),
    );
    final repository = LibraryRepository(client, db, isOffline: () => false);
    final albums = await repository.searchAlbums('moon');
    expect(albums.single.name, 'Moon');
    expect(asked.queryParameters['albumCount'], '200');
    expect(asked.queryParameters['artistCount'], '0');
    expect(asked.queryParameters['songCount'], '0');
    await db.close();
  });

  test('the artists show from the cache before the server answers', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final client = SubsonicClient(
      const ServerCredentials(
        baseUrl: 'http://navidrome',
        username: 'u',
        token: 't',
        salt: 's',
      ),
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'subsonic-response': {
              'status': 'ok',
              'artists': {
                'index': [
                  {
                    'name': 'A',
                    'artist': [
                      {'id': 'r1', 'name': 'Abba'},
                    ],
                  },
                ],
              },
            },
          }),
          200,
        ),
      ),
    );
    final repository = LibraryRepository(client, db, isOffline: () => false);
    expect(await repository.cachedArtists(), isNull);
    await repository.artists();
    final emitted = await cachedThenFresh(
      repository.cachedArtists(),
      repository.artists,
    ).toList();
    expect(emitted, hasLength(2));
    expect(emitted.first.single.name, 'Abba');
    await db.close();
  });
}
