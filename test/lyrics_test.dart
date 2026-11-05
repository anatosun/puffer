import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:puffer/data/db/database.dart';
import 'package:puffer/data/repositories/library_repository.dart';
import 'package:puffer/data/subsonic/models.dart';
import 'package:puffer/data/subsonic/subsonic_client.dart';

const _synced = {
  'lang': 'eng',
  'synced': true,
  'offset': 500,
  'line': [
    {'start': 1000, 'value': 'First'},
    {'start': 5000, 'value': ''},
    {'start': 9000, 'value': 'Third'},
  ],
};

const _plain = {
  'lang': 'eng',
  'synced': false,
  'line': [
    {'value': 'Only text'},
  ],
};

void main() {
  group('Lyrics', () {
    test('timed lyrics come before plain ones, and the offset moves the lines earlier', () {
      final lyrics = Lyrics.pick({
        'structuredLyrics': [_plain, _synced],
      })!;
      expect(lyrics.synced, isTrue);
      expect(lyrics.lines.map((l) => l.start), [
        const Duration(milliseconds: 500),
        const Duration(milliseconds: 4500),
        const Duration(milliseconds: 8500),
      ]);
    });

    test(
      'plain lyrics have no times, and a song without text has no lyrics',
      () {
        final lyrics = Lyrics.pick({
          'structuredLyrics': [_plain],
        })!;
        expect(lyrics.lines.single.start, isNull);
        expect(Lyrics.pick(null), isNull);
        expect(
          Lyrics.pick({
            'structuredLyrics': [
              {
                'synced': false,
                'line': [
                  {'value': '  '},
                ],
              },
            ],
          }),
          isNull,
        );
      },
    );

    test('the current line is the last one that has started', () {
      final lines = Lyrics(_synced).lines;
      expect(currentLyricLine(lines, Duration.zero), isNull);
      expect(currentLyricLine(lines, const Duration(seconds: 1)), 0);
      expect(currentLyricLine(lines, const Duration(seconds: 5)), 1);
      expect(currentLyricLine(lines, const Duration(minutes: 1)), 2);
    });
  });

  group('LibraryRepository.lyrics', () {
    late AppDatabase db;
    var online = true;
    var calls = 0;

    SubsonicClient client({bool supported = true}) => SubsonicClient(
      const ServerCredentials(
        baseUrl: 'http://navidrome',
        username: 'u',
        token: 't',
        salt: 's',
      ),
      httpClient: MockClient((request) async {
        calls++;
        return http.Response(
          jsonEncode({
            'subsonic-response': {
              'status': 'ok',
              'version': '1.16.1',
              'lyricsList': {
                'structuredLyrics': [_synced],
              },
            },
          }),
          200,
        );
      }),
    )..extensions = supported ? {'songLyrics'} : const {};

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      online = true;
      calls = 0;
    });
    tearDown(() => db.close());

    test(
      'lyrics are fetched once online and read from the cache offline',
      () async {
        final repository = LibraryRepository(
          client(),
          db,
          isOffline: () => !online,
        );
        expect((await repository.lyrics('a'))?.lines.first.text, 'First');
        online = false;
        expect((await repository.lyrics('a'))?.lines.first.text, 'First');
        expect(await repository.lyrics('never-loaded'), isNull);
        expect(calls, 1);
      },
    );

    test('a server without the extension is not asked', () async {
      final repository = LibraryRepository(
        client(supported: false),
        db,
        isOffline: () => false,
      );
      expect(await repository.lyrics('a'), isNull);
      expect(calls, 0);
    });
  });
}
