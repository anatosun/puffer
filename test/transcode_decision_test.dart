import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:puffer/data/subsonic/models.dart';
import 'package:puffer/data/subsonic/subsonic_client.dart';
import 'package:puffer/data/subsonic/transcoding.dart';
import 'package:puffer/downloads/download_settings.dart';
import 'package:puffer/playback/stream_offset.dart';
import 'package:puffer/playback/transcode_decider.dart';

http.Response ok(Map<String, dynamic> body) => http.Response(
  jsonEncode({
    'subsonic-response': {'status': 'ok', 'version': '1.16.1', ...body},
  }),
  200,
);

/// The example answer of the OpenSubsonic specification, with an Opus target.
const transcode = {
  'transcodeDecision': {
    'canDirectPlay': false,
    'canTranscode': true,
    'transcodeReason': ['audio bitrate not supported'],
    'transcodeParams': 'eyJ0b2tlbiI6MX0%3D',
    'sourceStream': {
      'protocol': 'http',
      'container': 'flac',
      'codec': 'flac',
      'audioChannels': 2,
      'audioBitrate': 1411000,
      'audioSamplerate': 44100,
      'audioBitdepth': 16,
    },
    'transcodeStream': {
      'protocol': 'http',
      'container': 'ogg',
      'codec': 'opus',
      'audioChannels': 2,
      'audioBitrate': 128000,
      'audioSamplerate': 48000,
    },
  },
};

const directPlay = {
  'transcodeDecision': {'canDirectPlay': true, 'canTranscode': false},
};

const track = Track({'id': 't1', 'suffix': 'flac'});

void main() {
  late List<http.Request> requests;
  late Map<String, dynamic> answer;

  SubsonicClient client() => SubsonicClient(
    const ServerCredentials(
      baseUrl: 'http://navidrome',
      username: 'u',
      token: 't',
      salt: 's',
    ),
    httpClient: MockClient((request) async {
      requests.add(request);
      return ok(answer);
    }),
  );

  setUp(() {
    requests = [];
    answer = transcode;
  });

  test(
    'getTranscodeDecision posts the client info as JSON and reads the answer',
    () async {
      final info = clientInfoFor(
        DownloadQuality.opus128,
        ClientPlatform.android,
      );
      final decision = await client().getTranscodeDecision('t1', info);
      final request = requests.single;
      expect(request.method, 'POST');
      expect(request.url.path, '/rest/getTranscodeDecision');
      expect(request.url.queryParameters['mediaId'], 't1');
      expect(request.url.queryParameters['mediaType'], 'song');
      expect(request.headers['Content-Type'], startsWith('application/json'));
      expect(jsonDecode(request.body), info.toJson());
      expect(decision.canTranscode, isTrue);
      expect(decision.transcodeStream!.extension, 'opus');
      expect(decision.transcodeStream!.audioBitrate, 128000);
    },
  );

  test(
    'the transcode stream keeps the escaped parameters as the server sent them',
    () {
      final uri = client().transcodeStreamUri(
        't1',
        'eyJ0b2tlbiI6MX0%3D',
        offset: const Duration(seconds: 42),
      );
      expect(uri.path, '/rest/getTranscodeStream');
      expect(uri.query, contains('transcodeParams=eyJ0b2tlbiI6MX0%3D'));
      expect(uri.queryParameters['mediaId'], 't1');
      expect(uri.queryParameters['mediaType'], 'song');
      expect(uri.queryParameters['offset'], '42');
      expect(startsPartWay(uri), isTrue);
      expect(startsPartWay(client().transcodeStreamUri('t1', 'x')), isFalse);
    },
  );

  test('a lower quality caps the bit rate and lets playable files through', () {
    final json = clientInfoFor(
      DownloadQuality.opus128,
      ClientPlatform.android,
    ).toJson();
    expect(json['maxAudioBitrate'], 128000);
    expect(json['maxTranscodingAudioBitrate'], 128000);
    expect(json['transcodingProfiles'], [
      {'container': 'ogg', 'audioCodec': 'opus', 'protocol': 'http'},
    ]);
    expect(
      (json['directPlayProfiles'] as List).map(
        (p) => ((p as Map)['audioCodecs'] as List).join(','),
      ),
      contains('mp3'),
    );
  });

  test('Apple systems get MP3 for Opus, which AVPlayer does not play', () {
    final json = clientInfoFor(
      DownloadQuality.opus192,
      ClientPlatform.apple,
    ).toJson();
    expect(json['transcodingProfiles'], [
      {'container': 'mp3', 'audioCodec': 'mp3', 'protocol': 'http'},
    ]);
    expect(jsonEncode(json['directPlayProfiles']), isNot(contains('ogg')));
  });

  test(
    'the original quality has no cap and converts only what cannot play',
    () {
      final json = clientInfoFor(
        DownloadQuality.original,
        ClientPlatform.desktop,
      ).toJson();
      expect(json.containsKey('maxAudioBitrate'), isFalse);
      expect(json['directPlayProfiles'], [
        {
          'containers': [],
          'audioCodecs': [],
          'protocols': ['http'],
        },
      ]);
      expect(
        (json['transcodingProfiles'] as List).map(
          (p) => (p as Map)['audioCodec'],
        ),
        ['flac', 'mp3'],
      );
    },
  );

  test(
    'the decider keeps each answer for an hour and asks once at a time',
    () async {
      var now = DateTime(2026, 11, 6, 12);
      final decider = TranscodeDecider(
        client(),
        platform: ClientPlatform.android,
        now: () => now,
      );
      expect(decider.cached('t1', DownloadQuality.opus128), isNull);
      final both = await Future.wait([
        decider.decide(track, DownloadQuality.opus128),
        decider.decide(track, DownloadQuality.opus128),
      ]);
      expect(requests, hasLength(1));
      expect(both.first!.transcoded, isTrue);
      expect(both.first!.transcodeParams, 'eyJ0b2tlbiI6MX0%3D');
      expect(decider.cached('t1', DownloadQuality.opus128), same(both.first));

      // Another quality is another question.
      answer = directPlay;
      final original = await decider.decide(track, DownloadQuality.original);
      expect(original!.transcoded, isFalse);
      expect(requests, hasLength(2));

      now = now.add(const Duration(minutes: 61));
      expect(decider.cached('t1', DownloadQuality.opus128), isNull);
      await decider.decide(track, DownloadQuality.opus128);
      expect(requests, hasLength(3));
    },
  );

  test(
    'without a usable answer the decider gives none, and asks again later',
    () async {
      answer = const {
        'transcodeDecision': {
          'canDirectPlay': false,
          'canTranscode': false,
          'errorReason': 'no compatible playback profile found',
        },
      };
      final decider = TranscodeDecider(
        client(),
        platform: ClientPlatform.android,
      );
      expect(await decider.decide(track, DownloadQuality.opus128), isNull);
      expect(await decider.decide(track, DownloadQuality.opus128), isNull);
      expect(requests, hasLength(2));
    },
  );

  test('a failed request leaves the app on the stream endpoint', () async {
    final failing = SubsonicClient(
      const ServerCredentials(
        baseUrl: 'http://navidrome',
        username: 'u',
        token: 't',
        salt: 's',
      ),
      httpClient: MockClient((_) async => http.Response('', 405)),
    );
    final decider = TranscodeDecider(failing, platform: ClientPlatform.apple);
    expect(await decider.decide(track, DownloadQuality.mp3320), isNull);
  });

  test('stream extensions follow what the player recognises', () {
    StreamDetails details(String container, String codec) =>
        StreamDetails({'container': container, 'codec': codec});
    expect(details('ogg', 'opus').extension, 'opus');
    expect(details('mp4', 'aac').extension, 'm4a');
    expect(details('mp3', 'mp3').extension, 'mp3');
    expect(details('', 'flac').extension, 'flac');
  });
}
