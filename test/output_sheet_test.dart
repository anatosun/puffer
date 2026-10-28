import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:puffer/app/playback_providers.dart';
import 'package:puffer/app/providers.dart';
import 'package:puffer/data/music_assistant/ma_client.dart';
import 'package:puffer/data/music_assistant/ma_models.dart';
import 'package:puffer/features/cast/output_sheet.dart';
import 'package:puffer/playback/playback_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeController extends Mock implements PlaybackController {}

MaPlayer player(
  String id, {
  String? syncedTo,
  List<String> members = const [],
}) => MaPlayer({
  'player_id': id,
  'name': id[0].toUpperCase() + id.substring(1),
  'available': true,
  'playback_state': 'idle',
  'synced_to': ?syncedTo,
  'group_members': members,
});

void main() {
  testWidgets(
    'grouped speakers show under their leader with an ungroup button',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            connectivityProvider.overrideWithValue(const AsyncData([])),
            initialMaCredentialsProvider.overrideWithValue(
              MaCredentials(baseUrl: Uri.parse('http://ma:8095'), token: 't'),
            ),
            maClientProvider.overrideWithValue(null),
            maStatusProvider.overrideWithValue(
              const AsyncData(MaConnectionStatus.connected),
            ),
            maPlayersProvider.overrideWithValue(
              AsyncData([
                player('bedroom'),
                player('kitchen', members: ['kitchen', 'living']),
                player('living', syncedTo: 'kitchen'),
              ]),
            ),
            nowPlayingProvider.overrideWithValue(const AsyncData(null)),
            playbackControllerProvider.overrideWithValue(_FakeController()),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showOutputSheet(context),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Kitchen'), findsOneWidget);
      expect(find.text('With Living'), findsOneWidget);
      expect(find.text('Living'), findsOneWidget);
      expect(find.text('In group with Kitchen'), findsOneWidget);
      expect(find.text('Bedroom'), findsOneWidget);
      // One ungroup button for the group on the leader, one for the follower.
      expect(find.byIcon(Icons.link_off), findsNWidgets(2));
    },
  );
}
