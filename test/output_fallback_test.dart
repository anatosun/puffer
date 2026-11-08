import 'package:puffer/data/repositories/library_repository.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import 'dart:async';

import 'package:fake_async/fake_async.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:puffer/app/playback_providers.dart';
import 'package:puffer/app/providers.dart';
import 'package:puffer/data/music_assistant/ma_client.dart';
import 'package:puffer/data/music_assistant/ma_models.dart';
import 'package:puffer/playback/ma_playback_controller.dart';
import 'package:puffer/data/subsonic/models.dart';
import 'package:puffer/playback/playback_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeController extends Mock
    implements MusicAssistantPlaybackController {}

class _FakeClient extends Mock implements MusicAssistantClient {}

class _FakeRepository extends Mock implements LibraryRepository {}

class _LocalController extends Mock implements PlaybackController {}

MaQueue _queue(String id, {required String state, bool loaded = true}) =>
    MaQueue({
      'queue_id': id,
      'state': state,
      if (loaded) 'current_item': {'queue_item_id': 'q-$id', 'name': 'Song'},
    });

/// A container whose output is the Music Assistant player `kitchen`, with the queues [queues].
Future<(ProviderContainer, _FakeController)> _onKitchen(
  Map<String, MaQueue> queues,
) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final client = _FakeClient();
  when(() => client.queues).thenReturn(queues);
  final controller = _FakeController();
  when(() => controller.playerId).thenReturn('kitchen');
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      maStatusProvider.overrideWithValue(
        const AsyncData(MaConnectionStatus.connected),
      ),
      maClientProvider.overrideWithValue(client),
      maAllPlayersProvider.overrideWithValue(const AsyncData([])),
      // The controller depends on the output, as in the app.
      playbackControllerProvider.overrideWith((ref) {
        ref.watch(outputProvider);
        return controller;
      }),
    ],
  );
  container.listen(outputProvider, (_, _) {});
  container.read(outputProvider.notifier).select('kitchen');
  return (container, controller);
}

void main() {
  test(
    'switching from an idle player leaves the queue of the target',
    () async {
      final (container, controller) = await _onKitchen({
        'kitchen': _queue('kitchen', state: 'idle', loaded: false),
        'living': _queue('living', state: 'playing'),
      });
      await container.read(outputSwitcherProvider).switchTo('living');
      verifyNever(() => controller.transferTo(any()));
      expect(container.read(outputProvider), 'living');
      container.dispose();
    },
  );

  test('with the setting on, a paused queue replaces what the target has '
      'loaded', () async {
    final (container, controller) = await _onKitchen({
      'kitchen': _queue('kitchen', state: 'paused'),
      'living': _queue('living', state: 'playing'),
    });
    when(() => controller.transferTo('living')).thenAnswer((_) async {});
    final switcher = container.read(outputSwitcherProvider);

    await switcher.switchTo('living');
    verifyNever(() => controller.transferTo(any()));

    container.read(outputProvider.notifier).select('kitchen');
    await container.read(movePausedQueueProvider.notifier).set(true);
    await switcher.switchTo('living');
    verify(() => controller.transferTo('living')).called(1);
    expect(container.read(outputProvider), 'living');
    container.dispose();
  });

  test('disconnecting returns to this device and leaves the player', () async {
    final (container, controller) = await _onKitchen({
      'kitchen': _queue('kitchen', state: 'playing'),
    });
    container.read(outputSwitcherProvider).disconnect();
    expect(container.read(outputProvider), isNull);
    verifyNever(controller.stop);
    verifyNever(controller.snapshot);
    container.dispose();
  });

  test('a failed transfer still switches to the player', () async {
    final (container, controller) = await _onKitchen({
      'kitchen': _queue('kitchen', state: 'playing'),
    });
    when(() => controller.transferTo('living'))
        .thenThrow(const MaException(0, 'Player is grouped'));
    await expectLater(
      container.read(outputSwitcherProvider).switchTo('living'),
      throwsA(isA<MaException>()),
    );
    expect(container.read(outputProvider), 'living');
    container.dispose();
  });

  test('the app starts on this device and falls back to it when Music '
      'Assistant stays unreachable', () async {
    SharedPreferences.setMockInitialValues({'ma.output': 'kitchen'});
    final prefs = await SharedPreferences.getInstance();
    fakeAsync((async) {
      final status = StreamController<MaConnectionStatus>();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          maStatusProvider.overrideWith((ref) => status.stream),
        ],
      );
      // Riverpod pauses providers without listeners; in the app the playback controller listens.
      container.listen(outputProvider, (_, _) {});
      final output = container.read(outputProvider.notifier);
      expect(container.read(outputProvider), isNull);

      status.add(MaConnectionStatus.connected);
      async.flushMicrotasks();
      output.select('kitchen');

      // A short drop keeps the player.
      status.add(MaConnectionStatus.connecting);
      async.elapse(const Duration(seconds: 20));
      status.add(MaConnectionStatus.connected);
      async.elapse(maFallbackDelay);
      expect(container.read(outputProvider), 'kitchen');

      status.add(MaConnectionStatus.disconnected);
      async.elapse(maFallbackDelay);
      expect(container.read(outputProvider), isNull);
      container.dispose();
    });
  });

  test('a player out of reach for the fallback delay returns playback to '
      'this device; a short drop keeps it', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    fakeAsync((async) {
      final players = StreamController<List<MaPlayer>>();
      MaPlayer kitchen({required bool available}) => MaPlayer({
        'player_id': 'kitchen',
        'name': 'Kitchen',
        'available': available,
      });
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          maStatusProvider.overrideWithValue(
            const AsyncData(MaConnectionStatus.connected),
          ),
          maAllPlayersProvider.overrideWith((ref) => players.stream),
        ],
      );
      container.listen(outputProvider, (_, _) {});
      players.add([kitchen(available: true)]);
      async.flushMicrotasks();
      container.read(outputProvider.notifier).select('kitchen');

      players.add([kitchen(available: false)]);
      async.elapse(const Duration(seconds: 20));
      players.add([kitchen(available: true)]);
      async.elapse(maFallbackDelay);
      expect(container.read(outputProvider), 'kitchen');

      // Gone from Music Assistant altogether.
      players.add([
        MaPlayer({'player_id': 'living', 'name': 'Living', 'available': true}),
      ]);
      async.elapse(maFallbackDelay);
      expect(container.read(outputProvider), isNull);
      container.dispose();
    });
  });

  test('a song counts as played after half of it or four minutes', () {
    const song = Duration(minutes: 3);
    expect(countsAsPlayed(const Duration(seconds: 89), song), isFalse);
    expect(countsAsPlayed(const Duration(seconds: 90), song), isTrue);
    const long = Duration(minutes: 20);
    expect(countsAsPlayed(const Duration(minutes: 4), long), isTrue);
    expect(countsAsPlayed(const Duration(minutes: 1), Duration.zero), isFalse);
  });

  group('endless radio on a speaker', () {
    setUpAll(() {
      registerFallbackValue(const Track({'id': 'fallback'}));
      registerFallbackValue(<Track>[]);
    });

    NowPlaying atQueueEnd({bool? autoplay, Repeat repeat = Repeat.off}) =>
        NowPlaying(
          track: const Track({'id': 't2', 'title': 'Last'}),
          title: 'Last',
          positionAt: DateTime(2026),
          index: 1,
          autoplay: autoplay,
          repeat: repeat,
          queue: const [
            QueueEntry(id: 'q1', trackId: 't1', title: 'First'),
            QueueEntry(id: 'q2', trackId: 't2', title: 'Last'),
          ],
        );

    Future<(ProviderContainer, _FakeController)> onSpeaker(
      NowPlaying np, {
      bool canMix = false,
    }) async {
      SharedPreferences.setMockInitialValues({'playback.endlessRadio': true});
      final prefs = await SharedPreferences.getInstance();
      final controller = _FakeController();
      when(() => controller.setAutoplay(any())).thenAnswer((_) async {});
      when(() => controller.addTracks(any())).thenAnswer((_) async {});
      // A library whose mix would extend the queue, were the runner to try.
      final repository = _FakeRepository();
      when(() => repository.instantMix(any(), count: any(named: 'count')))
          .thenAnswer(
            (_) async => [
              const Track({'id': 'm1', 'title': 'Mix'}),
            ],
          );
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          playbackControllerProvider.overrideWithValue(controller),
          // Loading first, then the song, as in the app: the runner reacts to that change.
          nowPlayingProvider.overrideWith((ref) => Stream.value(np)),
          canMixProvider.overrideWithValue(canMix),
          repositoryProvider.overrideWithValue(repository),
          connectivityProvider.overrideWithValue(
            const AsyncData([ConnectivityResult.wifi]),
          ),
        ],
      );
      return (container, controller);
    }

    test(
      'is the Autoplay of the player, whatever the setting of this device',
      () async {
        final (container, controller) = await onSpeaker(
          atQueueEnd(autoplay: true),
        );
        container.listen(outputEndlessRadioProvider, (_, _) {});
        await container.read(nowPlayingProvider.future);
        // Available without sonic similarity: Music Assistant fills the queue from its own providers.
        expect(container.read(outputEndlessRadioProvider), (
          available: true,
          on: true,
          blocked: false,
        ));
        await container.read(setEndlessRadioProvider)(false);
        verify(() => controller.setAutoplay(false)).called(1);
        // The setting of this device stays as it was.
        expect(container.read(endlessRadioProvider), isTrue);
        container.dispose();
      },
    );

    test('leaves the queue of the player to its Autoplay', () async {
      // Everything the runner needs is there; only the speaker keeps it from extending the queue.
      final (container, controller) = await onSpeaker(
        atQueueEnd(),
        canMix: true,
      );
      container.listen(endlessRadioRunnerProvider, (_, _) {});
      await container.read(nowPlayingProvider.future);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      verifyNever(() => controller.addTracks(any()));
      container.dispose();
    });

    test(
      'is off and blocked while repeat is on, on a speaker and here',
      () async {
        final (speaker, _) = await onSpeaker(
          atQueueEnd(autoplay: true, repeat: Repeat.all),
        );
        speaker.listen(outputEndlessRadioProvider, (_, _) {});
        await speaker.read(nowPlayingProvider.future);
        expect(speaker.read(outputEndlessRadioProvider), (
          available: true,
          on: false,
          blocked: true,
        ));
        speaker.dispose();

        // On this device the setting stays on, and endless radio comes back once repeat is off.
        SharedPreferences.setMockInitialValues({'playback.endlessRadio': true});
        final prefs = await SharedPreferences.getInstance();
        final here = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            playbackControllerProvider.overrideWithValue(_LocalController()),
            nowPlayingProvider.overrideWithValue(
              AsyncData(atQueueEnd(repeat: Repeat.one)),
            ),
            canMixProvider.overrideWithValue(true),
          ],
        );
        expect(here.read(outputEndlessRadioProvider), (
          available: true,
          on: false,
          blocked: true,
        ));
        expect(here.read(endlessRadioProvider), isTrue);
        here.dispose();
      },
    );
  });
}
