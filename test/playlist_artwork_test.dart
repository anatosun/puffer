import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:puffer/app/providers.dart';
import 'package:puffer/data/subsonic/models.dart';
import 'package:puffer/ui/widgets/tiles.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('the mosaic fits a list row smaller than its size', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          connectivityProvider.overrideWithValue(const AsyncData([])),
          clientProvider.overrideWithValue(null),
          playlistCoversProvider.overrideWith(
            (ref, id) async => ['a', 'b', 'c', 'd'],
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: Center(
              // The box a compact ListTile gives its leading widget, as on the desktop: 52 wide, 48 high.
              child: SizedBox(
                width: 52,
                height: 48,
                child: PlaylistArtwork(Playlist({'id': 'p1'}), size: 52),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(PlaylistArtwork)), const Size(52, 48));
  });
}
