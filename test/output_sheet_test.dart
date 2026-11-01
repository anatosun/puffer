import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:puffer/app/playback_providers.dart';
import 'package:puffer/app/providers.dart';
import 'package:puffer/app/sendspin_providers.dart';
import 'package:puffer/data/music_assistant/ma_client.dart';
import 'package:puffer/data/music_assistant/ma_models.dart';
import 'package:puffer/features/cast/output_sheet.dart';
import 'package:puffer/playback/playback_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeController extends Mock implements PlaybackController {}

class _FakeClient extends Mock implements MusicAssistantClient {}

class _FixedOutput extends OutputNotifier {
  _FixedOutput(this.value);

  final String value;

  @override
  String? build() => value;
}

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
  MusicAssistantClient? client,
  String? ownSpeaker,
  String? output,
  NowPlaying? here,
  Map<String, Object> prefs = const {},
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final preferences = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        connectivityProvider.overrideWithValue(const AsyncData([])),
        initialMaCredentialsProvider.overrideWithValue(
          MaCredentials(baseUrl: Uri.parse('http://ma:8095'), token: 't'),
        ),
        maClientProvider.overrideWithValue(client),
        maStatusProvider.overrideWithValue(
          const AsyncData(MaConnectionStatus.connected),
        ),
        maPlayersProvider.overrideWithValue(AsyncData(players)),
        maAllPlayersProvider.overrideWithValue(AsyncData(players)),
        maQueuesProvider.overrideWithValue(AsyncData(queues)),
        nowPlayingProvider.overrideWithValue(AsyncData(here)),
        playbackControllerProvider.overrideWithValue(_FakeController()),
        ownSpeakerIdProvider.overrideWithValue(ownSpeaker),
        if (output != null)
          outputProvider.overrideWith(() => _FixedOutput(output)),
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
  setUpAll(() {
    registerFallbackValue(player('fallback'));
    registerFallbackValue(const MaQueue({'queue_id': 'fallback'}));
  });

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

  testWidgets('a playing or paused speaker pauses or resumes from its row', (
    tester,
  ) async {
    final client = _FakeClient();
    when(() => client.playPause(any(), any())).thenAnswer((_) async {});
    MaQueue queue(String id, String state) => MaQueue({
      'queue_id': id,
      'state': state,
      'current_item': {'queue_item_id': 'q', 'name': 'Song'},
    });
    await openSheet(
      tester,
      [
        player('kitchen', state: 'playing'),
        player('bedroom', state: 'paused'),
        // Many players report idle while their queue is paused.
        player('office'),
        player('tv'),
      ],
      queues: {
        'kitchen': queue('kitchen', 'playing'),
        'bedroom': queue('bedroom', 'paused'),
        'office': queue('office', 'paused'),
      },
      client: client,
    );

    // The idle speaker has neither button.
    expect(find.byTooltip('Pause Kitchen'), findsOneWidget);
    expect(find.byTooltip('Play Bedroom'), findsOneWidget);
    expect(find.byTooltip('Play Office'), findsOneWidget);
    expect(find.byTooltip('Play Tv'), findsNothing);

    await tester.tap(find.byTooltip('Pause Kitchen'));
    await tester.pump();
    final sent = verify(() => client.playPause(captureAny(), captureAny()))
        .captured;
    expect((sent[0] as MaPlayer).id, 'kitchen');
    expect((sent[1] as MaQueue).id, 'kitchen');
    // The sheet stays open, so the output does not change.
    expect(find.text('Play on'), findsOneWidget);
  });

  testWidgets('the phone as a speaker is the This device row', (tester) async {
    await openSheet(
      tester,
      [
        player('phone', state: 'playing'),
        // Music Assistant can list the phone under a merged player of its own.
        MaPlayer({
          'player_id': 'merged',
          'name': 'Merged',
          'available': true,
          'output_protocols': [
            {'output_protocol_id': 'phone'},
          ],
        }),
        player('kitchen'),
      ],
      ownSpeaker: 'phone',
      output: 'merged',
    );

    expect(find.text('Phone'), findsNothing);
    expect(find.text('Merged'), findsNothing);
    expect(find.text('Kitchen'), findsOneWidget);
    // Selected, with no Disconnect, as when the music plays on the phone itself. The highlight marks the selection, without a tick.
    expect(find.byIcon(Icons.check), findsNothing);
    expect(find.text('Disconnect'), findsNothing);
  });

  testWidgets(
    'This device shows its paused track with a play button and its speaker name',
    (tester) async {
      await openSheet(
        tester,
        [player('kitchen')],
        here: NowPlaying(
          title: 'Song',
          artist: 'Band',
          positionAt: DateTime(2026),
        ),
        prefs: {'sendspin.enabled': true, 'sendspin.name': 'Pocket'},
      );

      // The play button says it is paused, so the text does not.
      expect(find.text('Song · Band'), findsOneWidget);
      expect(find.textContaining('Paused'), findsNothing);
      expect(find.byTooltip('Play This device'), findsOneWidget);
      expect(find.text('"Pocket" in Music Assistant'), findsOneWidget);
    },
  );

  testWidgets(
    'speakers sync with this device through its Music Assistant player',
    (tester) async {
      final client = _FakeClient();
      when(() => client.command(any(), any())).thenAnswer((_) async => null);
      await openSheet(
        tester,
        [
          MaPlayer({
            'player_id': 'phone',
            'name': 'Phone',
            'available': true,
            'can_group_with': ['kitchen', 'living'],
          }),
          player('kitchen', syncedTo: 'phone'),
          player('living'),
        ],
        client: client,
        ownSpeaker: 'phone',
        output: 'phone',
      );

      // The phone itself is the This device row, which lists the speakers synced with it.
      expect(find.text('Phone'), findsNothing);
      expect(find.text('with Kitchen'), findsOneWidget);
      // A chain to sync and a broken chain to stop, rather than checkboxes.
      expect(find.byType(Checkbox), findsNothing);
      expect(find.byTooltip('Stop syncing Kitchen'), findsOneWidget);
      expect(find.byTooltip('Sync Living with this device'), findsOneWidget);

      await tester.tap(find.byTooltip('Sync Living with this device'));
      await tester.pump();
      final args =
          verify(() => client.command('players/cmd/set_members', captureAny()))
                  .captured
                  .single
              as Map;
      expect(args['target_player'], 'phone');
      expect(args['player_ids_to_add'], ['living']);
    },
  );
}
