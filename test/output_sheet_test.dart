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
  String state = 'idle',
  String? icon,
  int? volume,
  bool private = false,
}) => MaPlayer({
  'player_id': id,
  'name': id[0].toUpperCase() + id.substring(1),
  'available': true,
  'playback_state': state,
  'synced_to': ?syncedTo,
  'group_members': members,
  'icon': ?icon,
  'volume_level': ?volume,
  'private': private,
});

Future<void> openSheet(
  WidgetTester tester,
  List<MaPlayer> players, {
  Map<String, MaQueue> queues = const {},
}) async {
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
        maPlayersProvider.overrideWithValue(AsyncData(players)),
        maQueuesProvider.overrideWithValue(AsyncData(queues)),
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
  // The playing bars animate, so the sheet is pumped for its opening rather than until it settles.
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  testWidgets(
    'grouped speakers show under their leader with an ungroup button',
    (tester) async {
      await openSheet(tester, [
        player('bedroom'),
        player('kitchen', members: ['kitchen', 'living']),
        player('living', syncedTo: 'kitchen'),
      ]);

      expect(find.text('Kitchen'), findsOneWidget);
      expect(find.text('With Living'), findsOneWidget);
      expect(find.text('Living'), findsOneWidget);
      expect(find.text('In group with Kitchen'), findsOneWidget);
      expect(find.text('Bedroom'), findsOneWidget);
      // One ungroup button for the group on the leader, one for the follower.
      expect(find.byIcon(Icons.link_off), findsNWidgets(2));
    },
  );

  testWidgets('players show their icon, what they play and their volume', (
    tester,
  ) async {
    // The maPlayersProvider leaves out private players, as the sheet relies on.
    expect(player('browser', private: true).usable, isFalse);
    await openSheet(
      tester,
      [
        player('kitchen', icon: 'kitchen', state: 'playing', volume: 40),
        player('tv', icon: 'mdi-television', volume: 20),
      ],
      queues: {
        'kitchen': const MaQueue({
          'queue_id': 'kitchen',
          'state': 'playing',
          'current_item': {
            'queue_item_id': 'q1',
            'name': 'Song',
            'media_item': {
              'name': 'Song',
              'artists': [
                {'name': 'Band'},
              ],
            },
          },
        }),
      },
    );

    expect(find.byIcon(Icons.kitchen), findsOneWidget);
    expect(find.byIcon(Icons.tv), findsOneWidget);
    expect(find.text('Song · Band'), findsOneWidget);
    // Only the playing speaker has a slider; the idle one keeps its row short.
    expect(find.byType(Slider), findsOneWidget);
    expect(find.text('40'), findsOneWidget);
  });
}
