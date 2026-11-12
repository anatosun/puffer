import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:puffer/app/playback_providers.dart';
import 'package:puffer/app/providers.dart';
import 'package:puffer/data/repositories/library_repository.dart';
import 'package:puffer/data/subsonic/models.dart';
import 'package:puffer/playback/playback_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeController extends Mock implements PlaybackController {}

class _FakeRepository extends Mock implements LibraryRepository {}

void main() {
  setUpAll(() {
    registerFallbackValue(const Track({'id': 'fallback'}));
    registerFallbackValue(<Track>[]);
  });

  final last = NowPlaying(
    track: const Track({'id': 't2', 'title': 'Last'}),
    title: 'Last',
    positionAt: DateTime(2026),
    index: 1,
    queue: const [
      QueueEntry(id: 't1', trackId: 't1', title: 'First'),
      QueueEntry(id: 't2', trackId: 't2', title: 'Last'),
    ],
  );

  /// The runner at the last song of the queue, with a server that answers the mix when the test completes [mix].
  Future<(StreamController<NowPlaying?>, _FakeController)> atLastSong(
    Completer<List<Track>> mix,
  ) async {
    SharedPreferences.setMockInitialValues({'playback.endlessRadio': true});
    final prefs = await SharedPreferences.getInstance();
    final controller = _FakeController();
    when(() => controller.addTracks(any())).thenAnswer((_) async {});
    final repository = _FakeRepository();
    when(() => repository.instantMix(any(), count: any(named: 'count')))
        .thenAnswer((_) => mix.future);
    final playing = StreamController<NowPlaying?>();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        playbackControllerProvider.overrideWithValue(controller),
        nowPlayingProvider.overrideWith((ref) => playing.stream),
        canMixProvider.overrideWithValue(true),
        repositoryProvider.overrideWithValue(repository),
        connectivityProvider.overrideWithValue(
          const AsyncData([ConnectivityResult.wifi]),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.listen(endlessRadioRunnerProvider, (_, _) {});
    playing.add(last);
    await container.read(nowPlayingProvider.future);
    return (playing, controller);
  }

  test('endless radio adds the mix after the last song', () async {
    final mix = Completer<List<Track>>();
    final (_, controller) = await atLastSong(mix);
    mix.complete(const [
      Track({'id': 't2'}),
      Track({'id': 'm1'}),
    ]);
    await pumpEventQueue();
    final added =
        verify(() => controller.addTracks(captureAny())).captured.single
            as List<Track>;
    expect(added.map((t) => t.id), ['m1']);
  });

  test(
    'a mix that comes after the queue ran out does not start it again',
    () async {
      final mix = Completer<List<Track>>();
      final (playing, controller) = await atLastSong(mix);
      // The last song ends before the server answers, and the player goes.
      playing.add(null);
      await pumpEventQueue();
      mix.complete(const [
        Track({'id': 'm1'}),
      ]);
      await pumpEventQueue();
      verifyNever(() => controller.addTracks(any()));
    },
  );
}
