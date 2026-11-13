import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:puffer/data/subsonic/models.dart';
import 'package:puffer/playback/playback_controller.dart';
import 'package:puffer/playback/radio.dart';

class _FakeController extends Mock implements PlaybackController {}

Track _song(String id) => Track({'id': id, 'title': 'Song $id'});

NowPlaying _playing(String id, {bool shuffle = false}) => NowPlaying(
  track: _song(id),
  title: 'Song $id',
  positionAt: DateTime(2026),
  playing: true,
  shuffle: shuffle,
);

void main() {
  late _FakeController controller;

  setUp(() {
    controller = _FakeController();
    when(() => controller.playTracks(any(), index: any(named: 'index')))
        .thenAnswer((_) async {});
    when(() => controller.replaceUpcoming(any())).thenAnswer((_) async {});
    when(() => controller.setShuffle(any())).thenAnswer((_) async {});
  });

  test(
    'a radio replaces what follows the song that plays, which plays on',
    () async {
      when(() => controller.current).thenReturn(_playing('now'));
      final mix = [_song('now'), _song('a'), _song('b')];
      expect(await playRadio(controller, mix), isTrue);
      final sent =
          verify(() => controller.replaceUpcoming(captureAny())).captured.single
              as List<Track>;
      expect([for (final t in sent) t.id], ['a', 'b']);
      verifyNever(
        () => controller.playTracks(any(), index: any(named: 'index')),
      );
      verifyNever(() => controller.setShuffle(any()));
    },
  );

  test('a radio turns shuffle off, so the mix plays in its order', () async {
    when(() => controller.current).thenReturn(_playing('now', shuffle: true));
    await playRadio(controller, [_song('a')]);
    verifyInOrder([
      () => controller.setShuffle(false),
      () => controller.replaceUpcoming(any()),
    ]);
  });

  test('with nothing loaded, the mix plays from its start', () async {
    when(() => controller.current).thenReturn(null);
    final mix = [_song('a'), _song('b')];
    expect(await playRadio(controller, mix), isTrue);
    verify(() => controller.playTracks(mix)).called(1);
    verifyNever(() => controller.replaceUpcoming(any()));
  });

  test('a mix of only the song that plays changes nothing', () async {
    when(() => controller.current).thenReturn(_playing('now'));
    expect(await playRadio(controller, [_song('now')]), isFalse);
    verifyNever(() => controller.replaceUpcoming(any()));
    verifyNever(() => controller.playTracks(any(), index: any(named: 'index')));
  });

  test('a mix from a menu plays from the song it was made from', () async {
    when(() => controller.current).thenReturn(_playing('now'));
    final mix = [_song('seed'), _song('a')];
    expect(await startMix(controller, mix, seed: 'seed'), isTrue);
    verify(() => controller.playTracks(mix)).called(1);
    verifyNever(() => controller.replaceUpcoming(any()));
  });

  test('a mix from a menu of the song that plays keeps it playing', () async {
    when(() => controller.current).thenReturn(_playing('now'));
    final mix = [_song('now'), _song('a')];
    expect(await startMix(controller, mix, seed: 'now'), isTrue);
    final sent =
        verify(() => controller.replaceUpcoming(captureAny())).captured.single
            as List<Track>;
    expect([for (final t in sent) t.id], ['a']);
    verifyNever(() => controller.playTracks(any(), index: any(named: 'index')));
  });

  test('a mix from a menu with only its seed changes nothing', () async {
    when(() => controller.current).thenReturn(null);
    expect(await startMix(controller, [_song('seed')], seed: 'seed'), isFalse);
    verifyNever(() => controller.playTracks(any(), index: any(named: 'index')));
  });
}
