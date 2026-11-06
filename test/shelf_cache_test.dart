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

  test('a playlist shows from the cache before the server answers', () async {
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
              'playlist': {
                'id': 'p1',
                'name': 'Long',
                'entry': [
                  for (var i = 0; i < 3000; i++)
                    {'id': 't$i', 'title': 'Song $i'},
                ],
              },
            },
          }),
          200,
        ),
      ),
    );
    final repository = LibraryRepository(client, db, isOffline: () => false);
    expect(await repository.cachedPlaylist('p1'), isNull);
    await repository.playlist('p1');
    final emitted = await cachedThenFresh(
      repository.cachedPlaylist('p1'),
      () => repository.playlist('p1'),
    ).toList();
    expect(emitted, hasLength(2));
    expect(emitted.first.entries, hasLength(3000));
    expect(emitted.first.entries.last.title, 'Song 2999');
    await db.close();
  });

  test('a cached playlist opens offline', () async {
    final db = AppDatabase(NativeDatabase.memory());
    var offline = false;
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
              'playlist': {
                'id': 'p1',
                'name': 'Mix',
                'entry': [
                  {'id': 't1', 'title': 'One'},
                ],
              },
            },
          }),
          200,
        ),
      ),
    );
    final repository = LibraryRepository(client, db, isOffline: () => offline);
    await repository.playlist('p1');
    offline = true;
    final emitted = await cachedThenFresh(
      repository.cachedPlaylist('p1'),
      () => repository.playlist('p1'),
    ).toList();
    expect(emitted.first.entries.single.title, 'One');
    await db.close();
  });

  test('albums load a few at a time and skip the missing ones', () async {
    final db = AppDatabase(NativeDatabase.memory());
    var inFlight = 0, most = 0;
    final client = SubsonicClient(
      const ServerCredentials(
        baseUrl: 'http://navidrome',
        username: 'u',
        token: 't',
        salt: 's',
      ),
      httpClient: MockClient((request) async {
        inFlight++;
        most = inFlight > most ? inFlight : most;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        inFlight--;
        final id = request.url.queryParameters['id']!;
        final body = id == 'gone'
            ? {
                'status': 'failed',
                'error': {'code': 70, 'message': 'not found'},
              }
            : {
                'status': 'ok',
                'album': {
                  'id': id,
                  'name': 'Album $id',
                  'song': [
                    {'id': '$id-1', 'title': 'Song'},
                  ],
                },
              };
        return http.Response(jsonEncode({'subsonic-response': body}), 200);
      }),
    );
    final repository = LibraryRepository(client, db, isOffline: () => false);
    final ids = [for (var i = 0; i < 10; i++) 'a$i', 'gone'];
    final albums = await repository.albums(ids);
    expect(albums.keys, hasLength(10));
    expect(albums.containsKey('gone'), isFalse);
    expect(most, lessThanOrEqualTo(4));
    final cached = await repository.cachedAlbums(ids);
    expect(cached.keys.toSet(), albums.keys.toSet());
    await db.close();
  });

  test('large JSON decodes the same in another isolate', () async {
    final big = {
      'entry': [
        for (var i = 0; i < 20000; i++) {'id': 't$i', 'title': 'Song $i'},
      ],
    };
    final text = jsonEncode(big);
    expect(text.length, greaterThan(256 * 1024));
    final decoded = await decodeLarge(text) as Map<String, dynamic>;
    expect((decoded['entry'] as List).length, 20000);
    expect(await decodeLarge('{"a":1}'), {'a': 1});
  });
}
