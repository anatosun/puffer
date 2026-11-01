import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:puffer/app/playback_providers.dart';
import 'package:puffer/app/providers.dart';
import 'package:puffer/data/subsonic/models.dart';
import 'package:puffer/features/now_playing/now_playing.dart';
import 'package:puffer/features/now_playing/waveform.dart';
import 'package:puffer/playback/playback_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeController extends Mock implements PlaybackController {}

void main() {
  testWidgets(
    'the window shrinking while the artwork cross-fades to the next song keeps the player inside it',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final songs = StreamController<NowPlaying?>();
      NowPlaying song(String id) => NowPlaying(
        track: Track({'id': id, 'title': id}),
        title: id,
        positionAt: DateTime(2026),
        duration: const Duration(minutes: 3),
      );
      await tester.binding.setSurfaceSize(const Size(720, 1000));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            nowPlayingProvider.overrideWith((ref) => songs.stream),
            connectivityProvider.overrideWithValue(
              const AsyncData([ConnectivityResult.wifi]),
            ),
            maClientProvider.overrideWithValue(null),
            playbackControllerProvider.overrideWithValue(_FakeController()),
            playingFormatProvider.overrideWithValue(null),
            waveformSupportedProvider.overrideWith((ref) async => false),
          ],
          child: const MaterialApp(home: NowPlayingPage()),
        ),
      );
      songs.add(song('a'));
      await tester.pump();
      await tester.pump();
      // The next song starts a fade; the window then shrinks before the fade ends.
      songs.add(song('b'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.binding.setSurfaceSize(const Size(720, 760));
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      await songs.close();
    },
  );
}
