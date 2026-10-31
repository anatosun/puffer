import 'dart:async';

import 'package:fake_async/fake_async.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:puffer/app/playback_providers.dart';
import 'package:puffer/app/providers.dart';
import 'package:puffer/data/music_assistant/ma_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
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
