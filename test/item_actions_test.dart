import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:puffer/app/playback_providers.dart';
import 'package:puffer/app/providers.dart';
import 'package:puffer/data/subsonic/models.dart';
import 'package:puffer/playback/playback_controller.dart';
import 'package:puffer/ui/widgets/item_actions.dart';
import 'package:puffer/ui/widgets/tiles.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeController extends Mock implements PlaybackController {}

void main() {
  test('a song lists every artist it credits, once each', () {
    const track = Track({
      'id': 't',
      'artist': 'X feat. Y',
      'artistId': 'x',
      'artists': [
        {'id': 'x', 'name': 'X'},
        {'id': 'y', 'name': 'Y'},
        {'id': 'x', 'name': 'X'},
        {'name': 'No id'},
      ],
    });
    expect(track.artists, [(id: 'x', name: 'X'), (id: 'y', name: 'Y')]);
    // Servers without the OpenSubsonic field send one artist.
    const plain = Track({'id': 't', 'artist': 'X', 'artistId': 'x'});
    expect(plain.artists, [(id: 'x', name: 'X')]);
    expect(const Album({'id': 'a'}).artists, isEmpty);
  });

  Future<void> openMenu(
    WidgetTester tester,
    Widget Function(BuildContext context, WidgetRef ref) opener,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          connectivityProvider.overrideWithValue(
            const AsyncData([ConnectivityResult.wifi]),
          ),
          playbackControllerProvider.overrideWithValue(_FakeController()),
        ],
        child: MaterialApp.router(
          routerConfig: GoRouter(
            routes: [
              GoRoute(
                path: '/',
                builder: (_, _) => Material(
                  child: Consumer(
                    builder: (context, ref, _) => opener(context, ref),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  testWidgets('the menu of a song by two artists leads to each of them', (
    tester,
  ) async {
    await openMenu(
      tester,
      (context, ref) => TextButton(
        onPressed: () => showTrackActions(
          context,
          ref,
          const Track({
            'id': 't',
            'title': 'Song',
            'artists': [
              {'id': 'x', 'name': 'Artist X'},
              {'id': 'y', 'name': 'Artist Y'},
            ],
          }),
        ),
        child: const Text('open'),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Go to Artist X'), findsOneWidget);
    expect(find.text('Go to Artist Y'), findsOneWidget);
  });

  testWidgets('the menu of an artist leads to its page', (tester) async {
    await openMenu(
      tester,
      (context, ref) =>
          const ArtistTile(Artist({'id': 'x', 'name': 'Artist X'})),
    );
    await tester.longPress(find.text('Artist X'));
    await tester.pumpAndSettle();
    expect(find.text('Go to Artist X'), findsOneWidget);
  });

  testWidgets('Go to in the menu of the player closes the player', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    const track = Track({
      'id': 't',
      'title': 'Song',
      'artists': [
        {'id': 'x', 'name': 'Artist X'},
      ],
    });
    // The player sits on the root navigator over the tabs, whose navigator holds the pages, as in the app.
    void openPlayer(BuildContext context) =>
        Navigator.of(context, rootNavigator: true).push(
          PageRouteBuilder<void>(
            settings: const RouteSettings(name: 'now-playing'),
            opaque: false,
            pageBuilder: (_, _, _) => Material(
              child: Consumer(
                builder: (context, ref, _) => TextButton(
                  onPressed: () => showTrackActions(context, ref, track),
                  child: const Text('menu'),
                ),
              ),
            ),
          ),
        );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          connectivityProvider.overrideWithValue(
            const AsyncData([ConnectivityResult.wifi]),
          ),
          playbackControllerProvider.overrideWithValue(_FakeController()),
        ],
        child: MaterialApp.router(
          routerConfig: GoRouter(
            routes: [
              ShellRoute(
                builder: (_, _, child) => child,
                routes: [
                  GoRoute(
                    path: '/',
                    builder: (_, _) => Material(
                      child: Builder(
                        builder: (context) => TextButton(
                          onPressed: () => openPlayer(context),
                          child: const Text('player'),
                        ),
                      ),
                    ),
                  ),
                  GoRoute(
                    path: '/artist/:id',
                    builder: (_, s) => Material(
                      child: Text('artist ${s.pathParameters['id']}'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.text('player'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('menu'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Go to Artist X'));
    await tester.tap(find.text('Go to Artist X'));
    await tester.pumpAndSettle();
    expect(find.text('artist x'), findsOneWidget);
    expect(find.text('menu'), findsNothing);
  });
}
