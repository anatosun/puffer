import 'package:flutter_test/flutter_test.dart';
import 'package:puffer/data/subsonic/subsonic_client.dart';
import 'package:puffer/playback/stream_offset.dart';

void main() {
  const credentials = ServerCredentials(
    baseUrl: 'http://navidrome',
    username: 'u',
    token: 't',
    salt: 's',
  );

  group('restartsStream', () {
    bool restarts(
      int target, {
      int offset = 0,
      int buffered = 30,
      bool restartable = true,
    }) => restartsStream(
      target: Duration(seconds: target),
      offset: Duration(seconds: offset),
      buffered: Duration(seconds: buffered),
      restartable: restartable,
    );

    test('a seek inside what has arrived is left to the player', () {
      expect(restarts(10), isFalse);
      expect(restarts(40, offset: 20, buffered: 30), isFalse);
    });

    test('a seek past what has arrived restarts the stream', () {
      expect(restarts(90), isTrue);
    });

    test('a seek before the start of a restarted stream restarts it', () {
      expect(restarts(5, offset: 20), isTrue);
    });

    test('without the ability to restart, the player always seeks', () {
      expect(restarts(90, restartable: false), isFalse);
    });
  });

  group('SubsonicClient.streamUri', () {
    final client = SubsonicClient(credentials);

    test('an offset becomes timeOffset in whole seconds', () {
      final uri = client.streamUri(
        'a',
        format: 'opus',
        maxBitRate: 128,
        offset: const Duration(seconds: 95, milliseconds: 700),
      );
      expect(uri.queryParameters['timeOffset'], '95');
      expect(uri.queryParameters['format'], 'opus');
    });

    test('without an offset there is no timeOffset', () {
      expect(
        client.streamUri('a').queryParameters,
        isNot(contains('timeOffset')),
      );
    });

    test('the extension is read from the list the server reports', () {
      expect(client.hasTranscodeOffset, isFalse);
      client.extensions = {'transcodeOffset'};
      expect(client.hasTranscodeOffset, isTrue);
    });
  });
}
