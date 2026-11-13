import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:puffer/app/providers.dart';
import 'package:puffer/data/db/database.dart';
import 'package:puffer/data/repositories/library_repository.dart';
import 'package:puffer/data/subsonic/models.dart';
import 'package:puffer/downloads/download_manager.dart';
import 'package:puffer/features/settings/downloads_settings_page.dart';
import 'package:puffer/ui/messages.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeRepository extends Mock implements LibraryRepository {}

class _FakeManager extends Mock implements DownloadManager {}

const _tracks = [
  Track({'id': 't1', 'artist': 'A', 'album': 'One', 'albumId': 'al1'}),
  Track({'id': 't2', 'artist': 'A', 'album': 'One', 'albumId': 'al1'}),
  Track({'id': 't3', 'artist': 'A', 'album': 'Two', 'albumId': 'al2'}),
  Track({'id': 't4', 'artist': 'B', 'album': 'Three', 'albumId': 'al3'}),
];

void main() {
  setUpAll(() => registerFallbackValue(PinKind.album));

  test('the storage is listed by artist and album, largest first', () {
    final usage = downloadUsage(_tracks, {
      't1': 10,
      't2': 10,
      't3': 50,
      't4': 5,
    });
    expect(usage.map((a) => (a.artist, a.bytes)), [('A', 70), ('B', 5)]);
    expect(usage.first.albums, [
      (id: 'al2', name: 'Two', bytes: 50),
      (id: 'al1', name: 'One', bytes: 20),
    ]);
  });

  /// The Downloads page over a database with [_tracks] downloaded, where album al1 is downloaded on its own.
  Future<(_FakeManager, _FakeRepository)> pumpPage(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    for (final t in _tracks) {
      await db
          .into(db.trackFiles)
          .insert(
            TrackFilesCompanion.insert(
              trackId: t.id,
              status: FileStatus.complete,
              size: const Value(1000),
              createdAt: DateTime(2026),
            ),
          );
    }
    final repository = _FakeRepository();
    when(() => repository.cachedTracks(any())).thenAnswer((_) async => _tracks);
    when(repository.clearWaveforms).thenAnswer((_) async {});
    final manager = _FakeManager();
    when(() => manager.unpin(any(), any())).thenAnswer((_) async {});
    when(manager.removeAll).thenAnswer((_) async {});
    when(manager.syncPins).thenAnswer((_) async => 0);
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const DownloadsSettingsPage()),
        GoRoute(
          path: '/album/:id',
          builder: (_, state) => Text('Album ${state.pathParameters['id']}'),
        ),
      ],
    );
    await tester.binding.setSurfaceSize(const Size(400, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          databaseProvider.overrideWithValue(db),
          isOfflineProvider.overrideWithValue(false),
          repositoryProvider.overrideWithValue(repository),
          downloadManagerProvider.overrideWithValue(manager),
          artworkStoreProvider.overrideWithValue(null),
          syncAutomaticDownloadsProvider.overrideWithValue(() async {}),
          completeTrackIdsProvider.overrideWith(
            (ref) => Stream.value([for (final t in _tracks) t.id]),
          ),
          pinStateProvider.overrideWith(
            (ref, key) =>
                Stream.value(PinState(pinned: key == (PinKind.album, 'al1'))),
          ),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          scaffoldMessengerKey: messengerKey,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (manager, repository);
  }

  /// Leaves the page; the queries of the database close a moment after it goes.
  Future<void> leave(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets(
    'an album of the storage opens, and its download can be removed there',
    (tester) async {
      final (manager, _) = await pumpPage(tester);
      await tester.tap(find.text('A'));
      await tester.pumpAndSettle();
      // Only the album downloaded on its own has its own download to remove.
      expect(find.byTooltip('Remove download'), findsOneWidget);
      await tester.tap(find.byTooltip('Remove download'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
      await tester.pumpAndSettle();
      verify(() => manager.unpin(PinKind.album, 'al1')).called(1);

      await tester.tap(find.text('Two'));
      await tester.pumpAndSettle();
      expect(find.text('Album al2'), findsOneWidget);
      await leave(tester);
    },
  );

  testWidgets(
    'the trash icon at the top asks first, then removes every download with its waveforms',
    (tester) async {
      final (manager, repository) = await pumpPage(tester);
      expect(find.text('Remove all downloads'), findsNothing);
      await tester.tap(find.byTooltip('Remove all downloads'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      verifyNever(manager.removeAll);

      await tester.tap(find.byTooltip('Remove all downloads'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove all'));
      await tester.pumpAndSettle();
      verify(manager.removeAll).called(1);
      verify(repository.clearWaveforms).called(1);
      await leave(tester);
    },
  );

  testWidgets('refresh syncs every download with the server', (tester) async {
    final (manager, _) = await pumpPage(tester);
    await tester.tap(find.byTooltip('Refresh downloads'));
    await tester.pumpAndSettle();
    verify(manager.syncPins).called(1);
    expect(find.text('Downloads are up to date'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await leave(tester);
  });
}
