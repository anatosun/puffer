import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:puffer/app/playback_providers.dart';
import 'package:puffer/app/providers.dart';
import 'package:puffer/features/now_playing/now_playing.dart';
import 'package:puffer/playback/playback_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeController extends Mock implements PlaybackController {}

void main() {
  testWidgets('the mini player fits a Music Assistant output', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final np = NowPlaying(
      title: 'A rather long title of a song that goes on',
      artist: 'Some artist',
      positionAt: DateTime.now(),
      duration: const Duration(minutes: 3),
      outputName: 'Kitchen',
      volume: 30,
    );
    await tester.binding.setSurfaceSize(const Size(400, 800));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          nowPlayingProvider.overrideWithValue(AsyncData(np)),
          connectivityProvider.overrideWithValue(const AsyncData([])),
          initialMaCredentialsProvider.overrideWithValue(
            MaCredentials(baseUrl: Uri.parse('http://ma:8095'), token: 't'),
          ),
          maClientProvider.overrideWithValue(null),
          playbackControllerProvider.overrideWithValue(_FakeController()),
        ],
        child: const MaterialApp(
          home: Scaffold(bottomNavigationBar: MiniPlayer()),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Some artist · Kitchen'), findsOneWidget);
  });
}
