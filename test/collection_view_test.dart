import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:puffer/app/playback_providers.dart';
import 'package:puffer/app/providers.dart';
import 'package:puffer/data/subsonic/models.dart';
import 'package:puffer/features/collection/album_page.dart';
import 'package:puffer/playback/playback_controller.dart';
import 'package:puffer/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeController extends Mock implements PlaybackController {}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'the album page stretches and collapses in ${brightness.name} mode',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final album = Album({
          'id': 'al1',
          'name': 'An album with a long name',
          'artist': 'An artist',
          'year': 1999,
          'song': [
            for (var i = 1; i <= 30; i++)
              {'id': 't$i', 'title': 'Song $i', 'track': i, 'duration': 200},
          ],
        });
        await tester.binding.setSurfaceSize(const Size(400, 860));
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(prefs),
              connectivityProvider.overrideWithValue(const AsyncData([])),
              albumProvider.overrideWith((ref, id) async => album),
              nowPlayingProvider.overrideWithValue(const AsyncData(null)),
              playbackControllerProvider.overrideWithValue(_FakeController()),
              maClientProvider.overrideWithValue(null),
            ],
            child: MaterialApp(
              theme: buildTheme(brightness),
              home: const AlbumPage('al1'),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Song 1'), findsOneWidget);

        // Pull down to stretch, then scroll far enough to collapse the header.
        await tester.drag(find.byType(CustomScrollView), const Offset(0, 300));
        await tester.pump();
        expect(tester.takeException(), isNull);
        await tester.pumpAndSettle();
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -900));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Song 12'), findsOneWidget);
        expect(find.text('Song 1'), findsNothing);
      },
    );
  }
}
