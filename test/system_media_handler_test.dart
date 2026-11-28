import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:puffer/playback/playback_controller.dart';
import 'package:puffer/playback/player_handler.dart';
import 'package:puffer/playback/system_media_handler.dart';

class _Local extends Mock implements PlayerHandler {}

class _Speaker extends Mock implements PlaybackController {}

void main() {
  late _Local local;
  late BaseAudioHandler streams;
  late _Speaker speaker;
  late SystemMediaHandler system;
  PlaybackController? output;

  setUp(() {
    local = _Local();
    // The streams of a plain handler stand in for those of the player.
    streams = BaseAudioHandler();
    when(() => local.mediaItem).thenAnswer((_) => streams.mediaItem);
    when(() => local.playbackState).thenAnswer((_) => streams.playbackState);
    when(() => local.queue).thenAnswer((_) => streams.queue);
    when(() => local.source).thenReturn(null);
    when(() => local.play()).thenAnswer((_) async {});
    when(() => local.pause()).thenAnswer((_) async {});
    speaker = _Speaker();
    when(() => speaker.play()).thenAnswer((_) async {});
    when(() => speaker.pause()).thenAnswer((_) async {});
    when(() => speaker.next()).thenAnswer((_) async {});
    output = null;
    system = SystemMediaHandler(local)..remoteControls = () => output;
  });

  NowPlaying kitchen({bool playing = true}) => NowPlaying(
    title: 'Song on the kitchen',
    artist: 'Artist',
    positionAt: DateTime.now(),
    playing: playing,
  );

  test('the controls show the player of this device', () async {
    streams.mediaItem.add(const MediaItem(id: 'a', title: 'Song here'));
    await pumpEventQueue();
    expect(system.mediaItem.value?.title, 'Song here');
  });

  test(
    'on a speaker, the controls show it and their buttons act on it',
    () async {
      output = speaker;
      system.showRemote(kitchen());
      expect(system.mediaItem.value?.title, 'Song on the kitchen');
      expect(system.playbackState.value.playing, isTrue);

      // This device changing meanwhile does not show.
      streams.mediaItem.add(const MediaItem(id: 'a', title: 'Song here'));
      await pumpEventQueue();
      expect(system.mediaItem.value?.title, 'Song on the kitchen');

      await system.pause();
      await system.skipToNext();
      verify(() => speaker.pause()).called(1);
      verify(() => speaker.next()).called(1);
      verifyNever(() => local.pause());
    },
  );

  test('back on this device, the controls show it and act on it', () async {
    streams.mediaItem.add(const MediaItem(id: 'a', title: 'Song here'));
    output = speaker;
    system.showRemote(kitchen());

    output = null;
    // A press right after the switch reaches this device, before the controls change.
    await system.play();
    verify(() => local.play()).called(1);
    verifyNever(() => speaker.play());

    system.showRemote(null);
    expect(system.mediaItem.value?.title, 'Song here');
  });
}
