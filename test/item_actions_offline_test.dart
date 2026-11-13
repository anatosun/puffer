import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:puffer/app/playback_providers.dart';
import 'package:puffer/app/providers.dart';
import 'package:puffer/data/repositories/library_repository.dart';
import 'package:puffer/downloads/download_manager.dart';
import 'package:puffer/playback/playback_controller.dart';
import 'package:puffer/ui/widgets/item_actions.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeController extends Mock implements PlaybackController {}

class _FakeRepository extends Mock implements LibraryRepository {}

class _FakeManager extends Mock implements DownloadManager {}

void main() {
  /// Opens the menu of an album that is [pinned] or not, online or [offline].
  Future<void> open(
    WidgetTester tester, {
    required bool offline,
    required bool pinned,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          isOfflineProvider.overrideWithValue(offline),
          pinStateProvider.overrideWith(
            (ref, key) => Stream.value(PinState(pinned: pinned)),
          ),
          downloadManagerProvider.overrideWithValue(_FakeManager()),
          repositoryProvider.overrideWithValue(_FakeRepository()),
          playbackControllerProvider.overrideWithValue(_FakeController()),
          canMixProvider.overrideWithValue(false),
          starredProvider.overrideWith((ref) async => null),
        ],
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () => showItemActions(
                context,
                ref,
                kind: PinKind.album,
                id: 'a1',
                title: 'One',
                starred: false,
                tracks: () async => const [],
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('online, the menu offers to download and to add to the library', (
    tester,
  ) async {
    await open(tester, offline: false, pinned: false);
    expect(find.text('Download'), findsOneWidget);
    expect(find.text('Add to library'), findsOneWidget);
    expect(find.text('Add to playlist'), findsOneWidget);
  });

  testWidgets('offline, the menu leaves out what needs the server', (
    tester,
  ) async {
    await open(tester, offline: true, pinned: false);
    expect(find.text('Download'), findsNothing);
    expect(find.text('Add to library'), findsNothing);
    expect(find.text('Add to playlist'), findsNothing);
    expect(find.text('Play next'), findsOneWidget);
  });

  testWidgets('offline, a download can still be removed', (tester) async {
    await open(tester, offline: true, pinned: true);
    expect(find.text('Remove download'), findsOneWidget);
  });
}
