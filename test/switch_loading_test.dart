import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:puffer/app/playback_providers.dart';
import 'package:puffer/playback/playback_controller.dart';

class _FakeController extends Mock implements PlaybackController {}

void main() {
  test(
    'while the queue moves, the song that played shows as loading',
    () async {
      final states = StreamController<NowPlaying?>.broadcast();
      final controller = _FakeController();
      when(() => controller.state).thenAnswer((_) => states.stream);
      when(() => controller.current).thenReturn(null);
      final container = ProviderContainer(
        overrides: [playbackControllerProvider.overrideWithValue(controller)],
      );
      addTearDown(container.dispose);
      final shown = <NowPlaying?>[];
      container.listen(
        nowPlayingProvider,
        (_, next) => shown.add(next.value),
        fireImmediately: true,
      );
      await Future<void>.delayed(Duration.zero);

      final song = NowPlaying(
        title: 'A song',
        playing: true,
        position: const Duration(seconds: 30),
        positionAt: DateTime.now(),
      );
      states.add(song);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(nowPlayingProvider).value?.playing, isTrue);

      // The switch stops the source, which then reports nothing.
      container.read(outputSwitchingProvider.notifier).set(true);
      states.add(null);
      await Future<void>.delayed(Duration.zero);
      final loading = container.read(nowPlayingProvider).value;
      expect(loading?.title, 'A song');
      expect(loading?.buffering, isTrue);
      expect(loading?.playing, isFalse);

      // Once the switch ends, the output's own state shows again.
      container.read(outputSwitchingProvider.notifier).set(false);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(nowPlayingProvider).value, isNull);
    },
  );
}
