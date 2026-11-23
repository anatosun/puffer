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
import 'package:puffer/features/now_playing/now_playing_below.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeController extends Mock implements PlaybackController {}

void main() {
  for (final size in const [Size(800, 480), Size(480, 320)]) {
    testWidgets(
      'on a screen of ${size.width.toInt()} × ${size.height.toInt()} the player puts the artwork beside the controls',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final songs = StreamController<NowPlaying?>();
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
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
        songs.add(
          NowPlaying(
            track: Track(const {'id': 'a', 'title': 'Song'}),
            title: 'Song',
            artist: 'Artist',
            album: 'Album',
            positionAt: DateTime(2026),
            duration: const Duration(minutes: 3),
          ),
        );
        await tester.pump();
        await tester.pump();
        expect(tester.takeException(), isNull);
        final art = tester.getRect(find.byType(NowPlayingArtwork));
        final title = tester.getRect(find.text('Song'));
        // The artwork fills most of the height or half the width, and the title sits to its right.
        expect(art.height, greaterThan(size.height * 0.6));
        expect(title.left, greaterThan(art.right));
        await songs.close();
      },
    );
  }
}
