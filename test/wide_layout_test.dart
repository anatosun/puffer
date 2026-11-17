import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:puffer/app/playback_providers.dart';
import 'package:puffer/app/providers.dart';
import 'package:puffer/data/subsonic/models.dart';
import 'package:puffer/features/cast/output_sheet.dart';
import 'package:puffer/features/collection/album_page.dart';
import 'package:puffer/features/now_playing/now_playing_below.dart';
import 'package:puffer/features/now_playing/player_bar.dart';
import 'package:puffer/playback/playback_controller.dart';
import 'package:puffer/ui/sheets.dart';
import 'package:puffer/ui/theme.dart';
import 'package:puffer/ui/widgets/tiles.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeController extends Mock implements PlaybackController {}

void main() {
  testWidgets('in a wide window the cover of an album sits beside its title', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final album = Album({
      'id': 'al1',
      'name': 'An album with a long name',
      'artist': 'An artist',
      'song': [
        for (var i = 1; i <= 20; i++)
          {'id': 't$i', 'title': 'Song $i', 'track': i, 'duration': 200},
      ],
    });
    tester.view
      ..physicalSize = const Size(1400, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          connectivityProvider.overrideWithValue(const AsyncData([])),
          albumProvider.overrideWith((ref, id) => Stream.value(album)),
          nowPlayingProvider.overrideWithValue(const AsyncData(null)),
          playbackControllerProvider.overrideWithValue(_FakeController()),
          maClientProvider.overrideWithValue(null),
        ],
        child: MaterialApp(
          theme: buildTheme(Brightness.dark),
          home: const AlbumPage('al1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final title = tester.getTopLeft(
      find.text('An album with a long name').last,
    );
    final play = tester.getCenter(find.byTooltip('Play'));
    expect(title.dx, greaterThan(220));
    expect(play.dx, greaterThan(220));
    expect(find.text('Song 1'), findsOneWidget);
  });

  testWidgets('the player bar and the queue panel fit a wide window', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final np = NowPlaying(
      title: 'A rather long title of a song that goes on and on',
      artist: 'Some artist',
      positionAt: DateTime.now(),
      duration: const Duration(minutes: 3),
      outputName: 'Kitchen',
      volume: 30,
      index: 0,
      queue: const [
        QueueEntry(id: 'q1', trackId: 't1', title: 'First'),
        QueueEntry(id: 'q2', trackId: 't2', title: 'Second'),
      ],
    );
    tester.view
      ..physicalSize = const Size(1000, 700)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
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
          theme: buildTheme(Brightness.dark),
          home: const Scaffold(
            body: Row(
              children: [
                Expanded(child: SizedBox()),
                QueuePanel(),
              ],
            ),
            bottomNavigationBar: PlayerBar(),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Second'), findsOneWidget);
    expect(find.byTooltip('Next'), findsOneWidget);
    expect(find.text('Some artist · Kitchen'), findsOneWidget);
  });

  Future<void> openMenu(
    WidgetTester tester,
    Size window, {
    required PointerDeviceKind kind,
  }) async {
    tester.view
      ..physicalSize = window
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: PointerRecorder(
          child: Builder(
            builder: (context) => Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 300, top: 200),
                child: TextButton(
                  onPressed: () => showSheet<void>(
                    context: context,
                    builder: (_) => const ListTile(title: Text('Menu entry')),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final at = tester.getCenter(find.text('Open'));
    final pointer = await tester.createGesture(kind: kind);
    await pointer.down(at);
    await pointer.up();
    await tester.pumpAndSettle();
  }

  testWidgets('in a wide window a menu opens at the mouse pointer', (
    tester,
  ) async {
    await openMenu(
      tester,
      const Size(1400, 900),
      kind: PointerDeviceKind.mouse,
    );
    expect(find.byType(BottomSheet), findsNothing);
    final open = tester.getCenter(find.text('Open'));
    final menu = tester.getTopLeft(find.text('Menu entry'));
    expect((menu - open).distance, lessThan(80));
  });

  testWidgets('on a phone a menu slides up from the bottom', (tester) async {
    await openMenu(tester, const Size(400, 800), kind: PointerDeviceKind.touch);
    expect(find.byType(BottomSheet), findsOneWidget);
  });

  testWidgets('in a wide window a song row shows its artist and album as '
      'columns', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    tester.view
      ..physicalSize = const Size(1400, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const track = Track({
      'id': 't1',
      'title': 'A song',
      'artist': 'An artist',
      'album': 'An album',
      'albumId': 'al1',
      'duration': 200,
    });
    Widget row({required bool numbered}) => ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        connectivityProvider.overrideWithValue(const AsyncData([])),
        nowPlayingProvider.overrideWithValue(const AsyncData(null)),
        maClientProvider.overrideWithValue(null),
      ],
      child: MaterialApp(
        home: Material(
          child: TrackTile(
            tracks: const [track],
            index: 0,
            showArtwork: !numbered,
            showNumber: numbered,
          ),
        ),
      ),
    );
    await tester.pumpWidget(row(numbered: false));
    await tester.pump();
    expect(tester.takeException(), isNull);
    final title = tester.getTopLeft(find.text('A song'));
    final artist = tester.getTopLeft(find.text('An artist'));
    final album = tester.getTopLeft(find.text('An album'));
    expect(artist.dy, closeTo(title.dy, 4));
    expect(artist.dx, greaterThan(title.dx));
    expect(album.dx, greaterThan(artist.dx));

    // On the page of the album, the album column goes.
    await tester.pumpWidget(row(numbered: true));
    await tester.pump();
    expect(find.text('An album'), findsNothing);
  });

  testWidgets('songs dropped on the queue panel go to the end of the queue', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final controller = _FakeController();
    when(() => controller.addTracks(any())).thenAnswer((_) async {});
    tester.view
      ..physicalSize = const Size(1200, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const song = Track({'id': 's1', 'title': 'Dragged'});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          connectivityProvider.overrideWithValue(const AsyncData([])),
          nowPlayingProvider.overrideWithValue(const AsyncData(null)),
          maClientProvider.overrideWithValue(null),
          playbackControllerProvider.overrideWithValue(controller),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                Expanded(
                  child: SongsDraggable(
                    songs: DraggedSongs('Dragged', () async => const [song]),
                    child: const SizedBox(height: 60, child: Text('Source')),
                  ),
                ),
                const QueuePanel(),
              ],
            ),
          ),
        ),
      ),
    );
    final from = tester.getCenter(find.text('Source'));
    final to = tester.getCenter(find.byType(QueuePanel));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(from);
    await tester.pump();
    await mouse.down(from);
    for (var i = 1; i <= 10; i++) {
      await mouse.moveTo(Offset.lerp(from, to, i / 10)!);
      await tester.pump();
    }
    await mouse.up();
    await tester.pumpAndSettle();
    verify(() => controller.addTracks([song])).called(1);
  });

  for (final (window, playing, shown) in [
    (const Size(1400, 900), true, false),
    (const Size(1400, 900), false, true),
    (const Size(400, 800), true, true),
  ]) {
    testWidgets('the speaker button of a page shows: $shown, in a window '
        '${window.width.toInt()} wide, playing: $playing', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      tester.view
        ..physicalSize = window
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            connectivityProvider.overrideWithValue(
              const AsyncData([ConnectivityResult.wifi]),
            ),
            initialMaCredentialsProvider.overrideWithValue(
              MaCredentials(baseUrl: Uri.parse('http://ma:8095'), token: 't'),
            ),
            maClientProvider.overrideWithValue(null),
            nowPlayingProvider.overrideWithValue(
              AsyncData(
                playing
                    ? NowPlaying(title: 'Song', positionAt: DateTime(2026))
                    : null,
              ),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(body: Center(child: PageOutputButton())),
          ),
        ),
      );
      await tester.pump();
      expect(find.byTooltip('Play on'), shown ? findsOneWidget : findsNothing);
    });
  }
}
