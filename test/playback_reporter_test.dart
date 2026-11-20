import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:puffer/data/subsonic/subsonic_client.dart';
import 'package:puffer/playback/playback_reporter.dart';

const starting = PlaybackReportState.starting;
const playing = PlaybackReportState.playing;
const paused = PlaybackReportState.paused;
const stopped = PlaybackReportState.stopped;

void main() {
  late PlaybackReporter reporter;
  final t0 = DateTime.utc(2026, 11, 20, 12);

  List<PlaybackReport> at(
    int seconds, {
    String? track = 'a',
    bool play = true,
    int? position,
  }) => reporter.update(
    trackId: track,
    playing: play,
    position: Duration(seconds: position ?? seconds),
    now: t0.add(Duration(seconds: seconds)),
  );

  PlaybackReport r(String id, PlaybackReportState s, int seconds) =>
      PlaybackReport(id, s, Duration(seconds: seconds));

  setUp(() => reporter = PlaybackReporter());

  test('a song that starts playing reports starting, then playing', () {
    expect(at(0), [r('a', starting, 0), r('a', playing, 0)]);
  });

  test('a song loaded paused reports nothing until it plays', () {
    expect(at(0, play: false, position: 30), isEmpty);
    expect(at(5, position: 30), [r('a', starting, 30), r('a', playing, 30)]);
  });

  test('pausing and playing on report paused and playing', () {
    at(0);
    expect(at(20, play: false), [r('a', paused, 20)]);
    expect(at(60, position: 20), [r('a', playing, 20)]);
  });

  test('nothing is reported while the state stays the same', () {
    at(0);
    expect(at(10), isEmpty);
    expect(at(30), isEmpty);
  });

  test('a seek reports the new position in the same state', () {
    at(0);
    expect(at(10, position: 120), [r('a', playing, 120)]);
    at(20, play: false, position: 130);
    expect(at(25, play: false, position: 40), [r('a', paused, 40)]);
  });

  test('the next song stops the previous one before it starts', () {
    at(0);
    expect(at(180, track: 'b', position: 0), [
      r('a', stopped, 180),
      r('b', starting, 0),
      r('b', playing, 0),
    ]);
  });

  test('a song that starts over, as on repeat, stops and starts again', () {
    at(0);
    expect(at(200, position: 0), [
      r('a', stopped, 200),
      r('a', starting, 0),
      r('a', playing, 0),
    ]);
  });

  test('the end of the queue stops the song', () {
    at(0);
    expect(at(30, track: null), [r('a', stopped, 30)]);
    expect(at(40, track: null), isEmpty);
  });

  test('a song that never played is not stopped', () {
    at(0, play: false);
    expect(at(5, track: 'b', play: false), isEmpty);
  });

  test('the client sends the state and position to reportPlayback', () async {
    late Uri request;
    final client = SubsonicClient(
      const ServerCredentials(
        baseUrl: 'http://navidrome',
        username: 'u',
        token: 't',
        salt: 's',
      ),
      httpClient: MockClient((req) async {
        request = req.url;
        return http.Response(
          '{"subsonic-response":{"status":"ok","version":"1.16.1"}}',
          200,
        );
      }),
    );
    await client.reportPlayback(
      'a',
      state: 'paused',
      position: const Duration(seconds: 12, milliseconds: 345),
      ignoreScrobble: true,
    );
    expect(request.pathSegments.last, 'reportPlayback');
    expect(request.queryParameters['mediaId'], 'a');
    expect(request.queryParameters['mediaType'], 'song');
    expect(request.queryParameters['positionMs'], '12345');
    expect(request.queryParameters['state'], 'paused');
    expect(request.queryParameters['ignoreScrobble'], 'true');
  });
}
