import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:puffer/data/db/database.dart';
import 'package:puffer/data/repositories/library_repository.dart';
import 'package:puffer/data/subsonic/models.dart';
import 'package:puffer/data/subsonic/subsonic_client.dart';

http.Response ok(Map<String, dynamic> body) => http.Response(
  jsonEncode({
    'subsonic-response': {'status': 'ok', 'version': '1.16.1', ...body},
  }),
  200,
);

void main() {
  late List<String> endpoints;
  late AppDatabase db;

  SubsonicClient client() => SubsonicClient(
    const ServerCredentials(
      baseUrl: 'http://navidrome',
      username: 'u',
      token: 't',
      salt: 's',
    ),
    httpClient: MockClient((request) async {
      final endpoint = request.url.pathSegments.last;
      endpoints.add(endpoint);
      return switch (endpoint) {
        'getSonicSimilarTracks' => ok({
          'sonicMatch': [
            {
              'entry': {'id': 'seed', 'title': 'Seed'},
              'similarity': 1.0,
            },
            {
              'entry': {'id': 'b', 'title': 'B'},
              'similarity': 0.9,
            },
          ],
        }),
        'getSimilarSongs' => ok({
          'similarSongs': {
            'song': [
              {'id': 'c', 'title': 'C'},
            ],
          },
        }),
        'getSimilarSongs2' => ok({
          'similarSongs2': {
            'song': [
              {'id': 'd', 'title': 'D'},
            ],
          },
        }),
        _ => ok({}),
      };
    }),
  );

  setUp(() {
    endpoints = [];
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  const seed = Track({'id': 'seed', 'title': 'Seed'});

  test('instant mix uses sonic similarity when the server offers it, without repeating the seed', () async {
    final c = client()..extensions = {'sonicSimilarity'};
    final mix = await LibraryRepository(
      c,
      db,
      isOffline: () => false,
    ).instantMix(seed);
    expect(mix.map((t) => t.id), ['seed', 'b']);
    expect(endpoints, ['getSonicSimilarTracks']);
  });

  test('instant mix falls back to similar songs', () async {
    final mix = await LibraryRepository(
      client(),
      db,
      isOffline: () => false,
    ).instantMix(seed);
    expect(mix.map((t) => t.id), ['seed', 'c']);
    expect(endpoints, ['getSimilarSongs']);
  });

  test(
    'artist radio uses getSimilarSongs2 and caches the tracks for offline use',
    () async {
      final repository = LibraryRepository(
        client(),
        db,
        isOffline: () => false,
      );
      final radio = await repository.radio(artistId: 'artist');
      expect(radio.map((t) => t.id), ['d']);
      expect((await repository.cachedTracks(['d'])).single.title, 'D');
    },
  );
}
