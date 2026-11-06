import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:puffer/app/providers.dart';
import 'package:puffer/data/db/database.dart';
import 'package:puffer/data/repositories/library_repository.dart';
import 'package:puffer/data/subsonic/models.dart';
import 'package:puffer/data/subsonic/server_address.dart';
import 'package:puffer/data/subsonic/subsonic_client.dart';
import 'package:puffer/features/settings/server_settings.dart';

http.Response ok(Map<String, Object?> body) => http.Response(
  jsonEncode({
    'subsonic-response': {'status': 'ok', ...body},
  }),
  200,
);

const credentials = ServerCredentials(
  baseUrl: 'https://music.example.com',
  username: 'u',
  token: 't',
  salt: 's',
  localUrl: 'http://192.168.1.10:4533',
);

void main() {
  group('address', () {
    test(
      'the local address is used on Wi-Fi when the server answers there',
      () async {
        final address = await chooseAddress(
          credentials,
          onLocalNetwork: true,
          answers: (_) async => true,
        );
        expect(address, 'http://192.168.1.10:4533');
      },
    );

    test(
      'the public address is used when the local one does not answer',
      () async {
        final address = await chooseAddress(
          credentials,
          onLocalNetwork: true,
          answers: (_) async => false,
        );
        expect(address, 'https://music.example.com');
      },
    );

    test('on mobile data the local address is not tried', () async {
      var probed = false;
      final address = await chooseAddress(
        credentials,
        onLocalNetwork: false,
        answers: (_) async => probed = true,
      );
      expect(address, 'https://music.example.com');
      expect(probed, isFalse);
    });

    test('a server answers only with a Subsonic response', () async {
      final yes = await serverAnswers(
        credentials,
        'http://192.168.1.10:4533',
        httpClient: MockClient((request) async {
          expect(request.url.host, '192.168.1.10');
          return ok({});
        }),
      );
      final no = await serverAnswers(
        credentials,
        'http://192.168.1.10:4533',
        httpClient: MockClient((_) async => http.Response('<html>', 200)),
      );
      expect(yes, isTrue);
      expect(no, isFalse);
    });

    test('the local address is stored with the credentials', () {
      final restored = ServerCredentials.fromJson(credentials.toJson());
      expect(restored.localUrl, 'http://192.168.1.10:4533');
    });
  });

  group('editing the connection', () {
    ServerCredentials edit({
      String address = 'https://music.example.com',
      String local = '',
      String username = 'u',
      String password = '',
      String apiKey = '',
      bool useApiKey = false,
      ServerCredentials current = credentials,
    }) => editedCredentials(
      current,
      address: address,
      localAddress: local,
      username: username,
      password: password,
      apiKey: apiKey,
      useApiKey: useApiKey,
    );

    test('an empty password keeps the token', () {
      final c = edit(address: 'music.example.org/');
      expect(c.baseUrl, 'https://music.example.org');
      expect((c.token, c.salt), ('t', 's'));
      expect(c.localUrl, isNull);
    });

    test('a local address without a scheme uses http', () {
      expect(
        edit(local: '192.168.1.10:4533').localUrl,
        'http://192.168.1.10:4533',
      );
    });

    test('another username needs the password', () {
      expect(() => edit(username: 'v'), throwsFormatException);
      final c = edit(username: 'v', password: 'secret');
      expect(c.username, 'v');
      expect(c.token, isNot('t'));
    });

    test('switching to an API key needs the key, and an empty key keeps the current one', () {
      expect(() => edit(useApiKey: true), throwsFormatException);
      final withKey = edit(useApiKey: true, apiKey: 'k1');
      expect((withKey.apiKey, withKey.token), ('k1', null));
      expect(edit(current: withKey, useApiKey: true).apiKey, 'k1');
      expect(() => edit(current: withKey), throwsFormatException);
    });
  });

  group('client', () {
    test('requests go to the address in use', () async {
      final hosts = <String>[];
      final client = SubsonicClient(
        credentials,
        baseUrl: credentials.localUrl,
        httpClient: MockClient((r) async {
          hosts.add(r.url.host);
          return ok({});
        }),
      );
      await client.ping();
      client.baseUrl = credentials.baseUrl;
      await client.ping();
      expect(hosts, ['192.168.1.10', 'music.example.com']);
    });

    test(
      'server details, administrator role and scan status are read',
      () async {
        final client = SubsonicClient(
          credentials,
          httpClient: MockClient(
            (r) async => switch (r.url.pathSegments.last) {
              'ping' => ok({
                'version': '1.16.1',
                'type': 'navidrome',
                'serverVersion': '0.53.3',
                'openSubsonic': true,
              }),
              'getUser' => ok({
                'user': {
                  'username': r.url.queryParameters['username'],
                  'adminRole': true,
                },
              }),
              _ => ok({
                'scanStatus': {
                  'scanning': false,
                  'count': 1200,
                  'lastScan': '2026-11-01T10:00:00Z',
                },
              }),
            },
          ),
        );
        final info = await client.serverInfo();
        expect(info.server, 'navidrome 0.53.3');
        expect(info.openSubsonic, isTrue);
        expect(await client.isAdmin(), isTrue);
        final scan = await client.getScanStatus();
        expect(scan.scanning, isFalse);
        expect(scan.count, 1200);
        expect(scanStatusLabel(scan), startsWith('Last scan 2026-11-01'));
      },
    );
  });

  group('refreshing the cache', () {
    late AppDatabase db;
    late List<String> fetched;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      fetched = [];
    });
    tearDown(() => db.close());

    Future<void> cache(String kind, String id, Object json) => db
        .into(db.cachedItems)
        .insert(
          CachedItemsCompanion.insert(
            kind: kind,
            id: id,
            json: jsonEncode(json),
            updatedAt: DateTime(2026),
          ),
        );

    test(
      'keeps what downloads need, drops the rest and reloads the kept items',
      () async {
        await cache('track', 't1', {
          'id': 't1',
          'albumId': 'a1',
          'artistId': 'r1',
        });
        await cache('track', 't2', {
          'id': 't2',
          'albumId': 'a2',
          'artistId': 'r2',
        });
        await cache('album', 'a1', {'id': 'a1', 'name': 'Old name'});
        await cache('album', 'a2', {'id': 'a2'});
        await cache('artist', 'r2', {'id': 'r2'});
        await cache('playlist', 'p1', {'id': 'p1'});
        await cache('playlist', 'p2', {'id': 'p2'});
        await cache('list', 'artists', []);
        await db
            .into(db.trackFiles)
            .insert(
              TrackFilesCompanion.insert(
                trackId: 't1',
                status: FileStatus.complete,
                createdAt: DateTime(2026),
              ),
            );
        await db
            .into(db.pins)
            .insert(
              PinsCompanion.insert(
                kind: 'playlist',
                itemId: 'p1',
                createdAt: DateTime(2026),
              ),
            );

        final client = SubsonicClient(
          credentials,
          httpClient: MockClient((r) async {
            final id = r.url.queryParameters['id']!;
            fetched.add('${r.url.pathSegments.last} $id');
            return switch (r.url.pathSegments.last) {
              'getAlbum' => ok({
                'album': {
                  'id': id,
                  'name': 'New name',
                  'song': [
                    {'id': 't1', 'albumId': 'a1', 'artistId': 'r1'},
                  ],
                },
              }),
              'getArtist' => ok({
                'artist': {'id': id},
              }),
              _ => ok({
                'playlist': {'id': id, 'entry': <Object>[]},
              }),
            };
          }),
        );
        final progress = <(int, int)>[];
        await LibraryRepository(
          client,
          db,
          isOffline: () => false,
        ).refreshCache(onProgress: (d, t) => progress.add((d, t)));

        final rows = await db.select(db.cachedItems).get();
        expect(
          {for (final r in rows) '${r.kind} ${r.id}'},
          {'track t1', 'album a1', 'artist r1', 'playlist p1'},
        );
        expect(
          fetched,
          unorderedEquals(['getAlbum a1', 'getArtist r1', 'getPlaylist p1']),
        );
        final album = rows.firstWhere((r) => r.kind == 'album');
        expect(jsonDecode(album.json)['name'], 'New name');
        expect(progress.last, (3, 3));
      },
    );
  });

  group('external items', () {
    test('items fetched through a proxy such as octo-fiesta are recognised by their ID', () {
      expect(isExternalId('ext-qobuz-album-123'), isTrue);
      expect(isExternalId('al-4f2a'), isFalse);
      expect(isExternalId('42'), isFalse);
    });

    test('background work leaves external items out unless the setting allows them', () {
      final albums = ['al-1', 'ext-qobuz-album-2', 'al-3'];
      expect(forBackground(albums, (a) => a, includeExternal: false), [
        'al-1',
        'al-3',
      ]);
      expect(forBackground(albums, (a) => a, includeExternal: true), albums);
    });

    test('a page shows the external items only after "More"', () {
      final albums = ['al-1', 'ext-qobuz-album-2', 'al-3'];
      final hidden = shownItems(albums, (a) => a, showExternal: false);
      expect(hidden.items, ['al-1', 'al-3']);
      expect(hidden.more, isTrue);
      final shown = shownItems(albums, (a) => a, showExternal: true);
      expect(shown.items, albums);
      expect(shown.more, isFalse);
      final local = shownItems(['al-1'], (a) => a, showExternal: false);
      expect(local.more, isFalse);
    });

    test('search results leave the external ones for "More"', () {
      final result = SearchResult(
        artists: [
          const Artist({'id': 'ar-1', 'name': 'A'}),
        ],
        albums: [
          const Album({'id': 'ext-deezer-album-9', 'name': 'B'}),
        ],
        tracks: [
          const Track({'id': 'tr-1', 'title': 'C'}),
          const Track({'id': 'ext-deezer-song-7', 'title': 'D'}),
        ],
      );
      final hidden = result.shown(showExternal: false);
      expect(hidden.more, isTrue);
      expect(hidden.result.artists, hasLength(1));
      expect(hidden.result.albums, isEmpty);
      expect([for (final t in hidden.result.tracks) t.id], ['tr-1']);
      final shown = result.shown(showExternal: true);
      expect(shown.more, isFalse);
      expect(shown.result.tracks, hasLength(2));
    });

    test('external items wait for "More" only on octo-fiesta', () async {
      ProviderContainer container(Set<String> extensions) {
        final c = ProviderContainer(
          overrides: [extensionsProvider.overrideWith((ref) => extensions)],
        );
        addTearDown(c.dispose);
        return c;
      }

      final octo = container({'octoFiesta'});
      await octo.read(extensionsProvider.future);
      final sub = octo.listen(externalShownProvider('artist:1'), (_, _) {});
      expect(sub.read(), isFalse);
      octo.read(externalShownProvider('artist:1').notifier).show();
      expect(sub.read(), isTrue);
      expect(octo.read(externalShownProvider('artist:2')), isFalse);

      final navidrome = container({'songLyrics'});
      await navidrome.read(extensionsProvider.future);
      expect(navidrome.read(externalShownProvider('artist:1')), isTrue);
    });
  });
}
