import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:puffer/app/providers.dart';
import 'package:puffer/data/subsonic/subsonic_client.dart';
import 'package:puffer/features/now_playing/waveform.dart';

const _credentials = ServerCredentials(
  baseUrl: 'http://navidrome',
  username: 'u',
  token: 't',
  salt: 's',
);

http.Response _ok(Map<String, Object?> body) => http.Response(
  jsonEncode({
    'subsonic-response': {'status': 'ok', ...body},
  }),
  200,
);

final _extensions = {
  'openSubsonicExtensions': [
    {
      'name': 'songWaveform',
      'versions': [1],
    },
  ],
};

final _waveform = {
  'waveform': {
    'id': 'song-1',
    'duration': 12.5,
    'samples': 4,
    'peaks': [0, 64, 255, 128],
  },
};

// A server with waveforms turned off answers getWaveform with a Subsonic error.
final _disabled = http.Response(
  jsonEncode({
    'subsonic-response': {
      'status': 'failed',
      'error': {'code': 0, 'message': 'waveforms are disabled on this server'},
    },
  }),
  200,
);

/// A client whose server answers each endpoint with [responses], and Subsonic error 70 for the rest.
SubsonicClient _client(
  Map<String, http.Response> responses, {
  List<Uri>? requests,
}) => SubsonicClient(
  _credentials,
  httpClient: MockClient((request) async {
    requests?.add(request.url);
    return responses[request.url.pathSegments.last] ??
        http.Response(
          jsonEncode({
            'subsonic-response': {
              'status': 'failed',
              'error': {'code': 70, 'message': 'not found'},
            },
          }),
          200,
        );
  }),
);

ProviderContainer _container(SubsonicClient client, {bool offline = false}) {
  final c = ProviderContainer(
    overrides: [
      clientProvider.overrideWithValue(client),
      isOfflineProvider.overrideWithValue(offline),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('SubsonicClient', () {
    test('getWaveform sends the id and the number of samples', () async {
      final requests = <Uri>[];
      final client = _client({
        'getWaveform': _ok(_waveform),
      }, requests: requests);
      expect(await client.getWaveform('song-1', samples: 4), [0, 64, 255, 128]);
      expect(requests.single.queryParameters['id'], 'song-1');
      expect(requests.single.queryParameters['samples'], '4');
    });

    test('supports waits for the extensions requested at login', () async {
      final client = _client({'getOpenSubsonicExtensions': _ok(_extensions)});
      final loading = client.loadExtensions();
      expect(await client.supports('songWaveform'), isTrue);
      expect(await client.supports('sonicSimilarity'), isFalse);
      await loading;
    });

    test('supports is false when the extensions cannot be loaded', () async {
      final client = SubsonicClient(
        _credentials,
        httpClient: MockClient((_) async => throw http.ClientException('down')),
      );
      final loading = client.loadExtensions();
      expect(await client.supports('songWaveform'), isFalse);
      await expectLater(loading, throwsA(isA<http.ClientException>()));
    });
  });

  group('waveformProvider', () {
    test('returns the peaks when the server has the extension', () async {
      final client = _client({
        'getOpenSubsonicExtensions': _ok(_extensions),
        'getWaveform': _ok(_waveform),
      });
      client.loadExtensions();
      final c = _container(client);
      expect(await c.read(waveformProvider('song-1').future), [
        0,
        64,
        255,
        128,
      ]);
    });

    test(
      'does not call getWaveform without the songWaveform extension',
      () async {
        final requests = <Uri>[];
        final client = _client({
          'getOpenSubsonicExtensions': _ok({'openSubsonicExtensions': []}),
        }, requests: requests);
        client.loadExtensions();
        final c = _container(client);
        expect(await c.read(waveformProvider('song-1').future), isNull);
        expect(
          requests.map((u) => u.pathSegments.last),
          isNot(contains('getWaveform')),
        );
      },
    );

    test('returns null when the server refuses the request', () async {
      final client = _client({
        'getOpenSubsonicExtensions': _ok(_extensions),
        'getWaveform': _disabled,
      });
      client.loadExtensions();
      final c = _container(client);
      expect(await c.read(waveformProvider('song-1').future), isNull);
    });

    test('returns null offline without any request', () async {
      final requests = <Uri>[];
      final client = _client({
        'getWaveform': _ok(_waveform),
      }, requests: requests);
      final c = _container(client, offline: true);
      expect(await c.read(waveformProvider('song-1').future), isNull);
      expect(requests, isEmpty);
    });
  });

  group('waveformBars', () {
    test('squares the quadratic mean of each group, relative to the loudest '
        'peak', () {
      expect(waveformBars([255, 255, 0, 0], 2), [1.0, 0.0]);
      // sqrt((255² + 0²) / 2) / 255 = 0.707…, squared 0.5
      expect(waveformBars([255, 0, 255, 255], 2)[0], closeTo(0.5, 1e-9));
    });

    test('repeats peaks when there are more bars than peaks', () {
      expect(waveformBars([255, 0], 4), [1.0, 1.0, 0.0, 0.0]);
    });

    test('draws silence as zero heights', () {
      expect(waveformBars([0, 0], 2), [0.0, 0.0]);
    });

    test('returns no bars without peaks', () {
      expect(waveformBars([], 10), isEmpty);
      expect(waveformBars([1, 2], 0), isEmpty);
    });
  });
}
