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
import 'package:shared_preferences/shared_preferences.dart';

class _FakeController extends Mock
    implements MusicAssistantPlaybackController {}

class _FakeClient extends Mock implements MusicAssistantClient {}

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
}
