import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:puffer/app/playback_providers.dart';
import 'package:puffer/app/providers.dart';
import 'package:puffer/data/repositories/library_repository.dart';
import 'package:puffer/data/subsonic/models.dart';
import 'package:puffer/features/now_playing/now_playing.dart';
import 'package:puffer/features/now_playing/waveform.dart';
import 'package:puffer/playback/playback_controller.dart';
import 'package:puffer/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeController extends Mock implements PlaybackController {}

class _FakeRepository extends Mock implements LibraryRepository {}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'the mini player fits a Music Assistant output in ${brightness.name} mode',
      (tester) async {
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
            child: MaterialApp(
              theme: buildTheme(brightness),
              home: const Scaffold(bottomNavigationBar: MiniPlayer()),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.text('Some artist · Kitchen'), findsOneWidget);
      },
    );
  }

  for (final (brightness, rating, waveform) in [
    for (final b in Brightness.values) (b, false, false),
    (Brightness.dark, true, false),
    (Brightness.dark, true, true),
  ]) {
    testWidgets(
      'the now-playing screen lays out on a small screen in ${brightness.name} mode${rating ? ' with the rating' : ''}${waveform ? ' and a waveform' : ''}',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          'experience.playerRating': rating,
        });
        final prefs = await SharedPreferences.getInstance();
        final np = NowPlaying(
          track: const Track({'id': 'a', 'title': 'A title', 'userRating': 3}),
          title: 'A title',
          artist: 'An artist',
          album: 'An album',
          positionAt: DateTime.now(),
          duration: const Duration(minutes: 3),
          queue: const [
            QueueEntry(id: 'p', title: 'Played before'),
            QueueEntry(id: 'a', title: 'A title'),
            QueueEntry(id: 'n', title: 'Next one'),
          ],
          index: 1,
        );
        await tester.binding.setSurfaceSize(const Size(360, 640));
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(prefs),
              nowPlayingProvider.overrideWithValue(AsyncData(np)),
              connectivityProvider.overrideWithValue(
                const AsyncData([ConnectivityResult.wifi]),
              ),
              maClientProvider.overrideWithValue(null),
              playbackControllerProvider.overrideWithValue(_FakeController()),
              waveformSupportedProvider.overrideWith((ref) async => waveform),
              waveformProvider.overrideWith(
                (ref, id) async => waveform ? [0, 128, 255, 64] : null,
              ),
            ],
            child: MaterialApp(
              theme: buildTheme(brightness),
              home: const NowPlayingPage(),
            ),
          ),
        );
        // One frame for the waveform support, one for the waveform.
        await tester.pump();
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.text('Next one'), findsOneWidget);
        expect(find.byIcon(Icons.star_rounded), findsNWidgets(rating ? 3 : 0));
        expect(
          find.byWidgetPredicate(
            (w) => w is CustomPaint && w.painter is WaveformPainter,
          ),
          findsNWidgets(waveform ? 1 : 0),
        );

        // Scrolling down continues into the queue, past tracks included.
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -700));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Played before'), findsOneWidget);
        expect(find.text('Next one'), findsWidgets);
      },
    );
  }

  testWidgets('the layout does not move while the waveform of a track loads', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final loading = Completer<List<int>?>();
    final np = NowPlaying(
      track: const Track({'id': 'a', 'title': 'A title'}),
      title: 'A title',
      positionAt: DateTime.now(),
      duration: const Duration(minutes: 3),
    );
    await tester.binding.setSurfaceSize(const Size(360, 640));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          nowPlayingProvider.overrideWithValue(AsyncData(np)),
          connectivityProvider.overrideWithValue(
            const AsyncData([ConnectivityResult.wifi]),
          ),
          maClientProvider.overrideWithValue(null),
          playbackControllerProvider.overrideWithValue(_FakeController()),
          waveformSupportedProvider.overrideWith((ref) async => true),
          waveformProvider.overrideWith((ref, id) => loading.future),
        ],
        child: MaterialApp(
          theme: buildTheme(Brightness.dark),
          home: const NowPlayingPage(),
        ),
      ),
    );
    await tester.pump();
    final whileLoading = tester.getCenter(find.byType(Slider));
    expect(
      find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is WaveformPainter,
      ),
      findsNothing,
    );

    loading.complete([0, 128, 255, 64]);
    await tester.pump();
    await tester.pump();
    expect(
      find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is WaveformPainter,
      ),
      findsOneWidget,
    );
    expect(tester.getCenter(find.byType(Slider)), whileLoading);
  });

  testWidgets('a long press on the play button stops playback', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final controller = _FakeController();
    when(controller.stop).thenAnswer((_) async {});
    final np = NowPlaying(
      title: 'A title',
      artist: 'An artist',
      positionAt: DateTime.now(),
      duration: const Duration(minutes: 3),
      playing: true,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          nowPlayingProvider.overrideWithValue(AsyncData(np)),
          connectivityProvider.overrideWithValue(const AsyncData([])),
          maClientProvider.overrideWithValue(null),
          playbackControllerProvider.overrideWithValue(controller),
        ],
        child: MaterialApp(
          home: const Scaffold(bottomNavigationBar: MiniPlayer()),
        ),
      ),
    );
    await tester.longPress(find.byIcon(Icons.pause_rounded));
    await tester.pump(const Duration(seconds: 2));
    verify(controller.stop).called(1);
  });

  testWidgets('the player closes once nothing plays, but not while the output '
      'switches', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final playing = StreamController<NowPlaying?>();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        nowPlayingProvider.overrideWith((ref) => playing.stream),
        connectivityProvider.overrideWithValue(const AsyncData([])),
        maClientProvider.overrideWithValue(null),
        playbackControllerProvider.overrideWithValue(_FakeController()),
      ],
    );
    addTearDown(container.dispose);
    // The mini player always listens in the app.
    container.listen(nowPlayingProvider, (_, _) {});
    playing.add(
      NowPlaying(
        title: 'Song',
        positionAt: DateTime.now(),
        duration: const Duration(minutes: 3),
      ),
    );
    await tester.binding.setSurfaceSize(const Size(400, 800));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => openNowPlaying(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(NowPlayingPage), findsOneWidget);

    // While the output switches, the new output may report nothing for a while.
    container.read(outputSwitchingProvider.notifier).set(true);
    playing.add(null);
    await tester.pump(const Duration(seconds: 5));
    expect(find.byType(NowPlayingPage), findsOneWidget);

    container.read(outputSwitchingProvider.notifier).set(false);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byType(NowPlayingPage), findsNothing);
    expect(find.text('Nothing playing'), findsNothing);
  });

  testWidgets('the player leaves out what the Experience settings turn off', (
    tester,
  ) async {
    Future<void> pumpPlayer(Map<String, Object> settings) async {
      SharedPreferences.setMockInitialValues(settings);
      final prefs = await SharedPreferences.getInstance();
      final np = NowPlaying(
        track: const Track({'id': 'a', 'title': 'A title'}),
        title: 'A title',
        positionAt: DateTime.now(),
        duration: const Duration(minutes: 3),
        queue: const [
          QueueEntry(id: 'a', title: 'A title'),
          QueueEntry(id: 'n', title: 'Next one'),
        ],
        index: 0,
      );
      await tester.binding.setSurfaceSize(const Size(400, 800));
      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            nowPlayingProvider.overrideWithValue(AsyncData(np)),
            connectivityProvider.overrideWithValue(
              const AsyncData([ConnectivityResult.wifi]),
            ),
            maClientProvider.overrideWithValue(null),
            playbackControllerProvider.overrideWithValue(_FakeController()),
            playingFormatProvider.overrideWithValue((
              codec: 'FLAC',
              quality: '16/44.1 kHz',
            )),
            waveformSupportedProvider.overrideWith((ref) async => false),
          ],
          child: const MaterialApp(home: NowPlayingPage()),
        ),
      );
      await tester.pump();
    }

    await pumpPlayer({});
    expect(find.text('FLAC'), findsOneWidget);
    expect(find.text('16/44.1 kHz'), findsOneWidget);
    expect(find.byIcon(Icons.favorite_border), findsOneWidget);
    expect(find.text('-3:00'), findsOneWidget);
    expect(find.text('Next one'), findsWidgets);

    await pumpPlayer({
      'experience.playerFormat': false,
      'experience.playerFavourite': false,
      'experience.remainingTime': false,
      'experience.upNext': false,
    });
    expect(find.text('FLAC'), findsNothing);
    expect(find.byIcon(Icons.favorite_border), findsNothing);
    // The length of the song instead of the time that remains.
    expect(find.text('3:00'), findsOneWidget);
    // The queue further down is not built yet, so the next song shows nowhere on screen.
    expect(find.text('Next one'), findsNothing);
  });

  testWidgets(
    'the format badges lead through the song info to the streaming quality',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await tester.binding.setSurfaceSize(const Size(400, 800));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            nowPlayingProvider.overrideWithValue(
              AsyncData(
                NowPlaying(
                  track: const Track({'id': 'a', 'title': 'A title'}),
                  title: 'A title',
                  positionAt: DateTime.now(),
                  duration: const Duration(minutes: 3),
                ),
              ),
            ),
            connectivityProvider.overrideWithValue(
              const AsyncData([ConnectivityResult.wifi]),
            ),
            maClientProvider.overrideWithValue(null),
            playbackControllerProvider.overrideWithValue(_FakeController()),
            playingFormatProvider.overrideWithValue((
              codec: 'FLAC',
              quality: '16/44.1',
            )),
            // A downloaded song, which keeps playing its file.
            playingSourceProvider.overrideWithValue(PlayingSource.download),
            waveformSupportedProvider.overrideWith((ref) async => false),
          ],
          child: const MaterialApp(home: NowPlayingPage()),
        ),
      );
      await tester.pump();

      // The badges open the song info, which leads to the streaming quality.
      await tester.tap(find.text('FLAC'));
      await tester.pumpAndSettle();
      expect(find.text('Streaming quality'), findsOneWidget);
      await tester.tap(find.text('Streaming quality'));
      await tester.pumpAndSettle();
      expect(find.text('Streaming quality on Wi-Fi'), findsOneWidget);
      expect(find.textContaining('plays from its download'), findsOneWidget);

      await tester.tap(find.text('Opus 128 kbit/s'));
      await tester.pumpAndSettle();
      expect(prefs.getString('playback.qualityWifi'), 'opus128');
      expect(find.text('Streaming quality on Wi-Fi'), findsNothing);
    },
  );

  testWidgets(
    'a double tap on the artwork adds the song to the library, and a tap on the time shows its length',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repository = _FakeRepository();
      when(
        () => repository.setStarred(
          starred: any(named: 'starred'),
          trackId: any(named: 'trackId'),
        ),
      ).thenAnswer((_) async {});
      await tester.binding.setSurfaceSize(const Size(400, 800));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            nowPlayingProvider.overrideWithValue(
              AsyncData(
                NowPlaying(
                  track: const Track({'id': 'a', 'title': 'A title'}),
                  title: 'A title',
                  positionAt: DateTime.now(),
                  duration: const Duration(minutes: 3),
                ),
              ),
            ),
            connectivityProvider.overrideWithValue(
              const AsyncData([ConnectivityResult.wifi]),
            ),
            maClientProvider.overrideWithValue(null),
            repositoryProvider.overrideWithValue(repository),
            syncAutomaticDownloadsProvider.overrideWithValue(() async {}),
            playbackControllerProvider.overrideWithValue(_FakeController()),
            playingFormatProvider.overrideWithValue(null),
            waveformSupportedProvider.overrideWith((ref) async => false),
          ],
          child: const MaterialApp(home: NowPlayingPage()),
        ),
      );
      await tester.pump();
      expect(find.byIcon(Icons.favorite_border), findsOneWidget);

      final cover = find.byType(Hero);
      await tester.tap(cover);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tap(cover);
      await tester.pumpAndSettle();
      verify(() => repository.setStarred(starred: true, trackId: 'a'))
          .called(1);
      // The heart under the artwork follows the double tap.
      expect(find.byIcon(Icons.favorite), findsOneWidget);

      await tester.tap(find.text('-3:00'));
      await tester.pump();
      expect(find.text('3:00'), findsOneWidget);
      expect(prefs.getBool('experience.remainingTime'), isFalse);
    },
  );
}
