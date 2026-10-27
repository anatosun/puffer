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
}
