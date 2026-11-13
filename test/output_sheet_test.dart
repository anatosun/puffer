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
import 'package:puffer/ui/player_icons.dart';
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
  int? groupVolume,
  String? type,
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
  'group_volume': ?groupVolume,
  'type': ?type,
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

      // The group has no name: the group icon, the number of its speakers and, while idle, their names. Every speaker follows under it, the leading one included, without a caption.
      expect(find.text('2 speakers'), findsOneWidget);
      expect(find.text('Kitchen, Living'), findsOneWidget);
      expect(find.text('Kitchen'), findsOneWidget);
      expect(find.text('Living'), findsOneWidget);
      expect(find.textContaining('group'), findsNothing);
      expect(find.text('Bedroom'), findsOneWidget);
      expect(
        tester.widgetList<PlayerIcon>(find.byType(PlayerIcon)).map((i) => i.id),
        contains('speakers'),
      );
      // One ungroup button for the group on the leader, one for the follower.
      expect(find.byIcon(Icons.link_off), findsNWidgets(2));
    },
  );

  testWidgets(
    'every speaker of a playing group has a volume of its own, the leader '
    'included, beside the volume of the group',
    (tester) async {
      final client = _FakeClient();
      when(() => client.setVolume(any(), any(), alone: any(named: 'alone')))
          .thenAnswer((_) async {});
      await openSheet(tester, [
        player(
          'kitchen',
          members: ['kitchen', 'living'],
          state: 'playing',
          volume: 30,
          groupVolume: 45,
        ),
        player('living', syncedTo: 'kitchen', volume: 60),
      ], client: client);
      // The group, the leader alone and the follower.
      expect(find.byType(Slider), findsNWidgets(3));
      expect(find.text('45'), findsOneWidget);
      expect(find.text('30'), findsOneWidget);
      expect(find.text('60'), findsOneWidget);

      // The leader's own slider, second in the list, sets its volume alone.
      final leaderSlider = find.byType(Slider).at(1);
      await tester.drag(leaderSlider, const Offset(40, 0));
      await tester.pump();
      final sent = verify(
        () => client.setVolume(
          captureAny(),
          any(),
          alone: captureAny(named: 'alone'),
        ),
      ).captured;
      expect((sent[0] as MaPlayer).id, 'kitchen');
      expect(sent[1], isTrue);
    },
  );

  testWidgets('the speakers of a fixed group show under it', (tester) async {
    await openSheet(tester, [
      player('party', type: 'group', members: ['kitchen', 'living']),
      player('kitchen'),
      player('living'),
    ]);
    // A fixed group keeps the name it has in Music Assistant; its speakers follow under it, and on rows of their own further down.
    expect(find.text('Party'), findsOneWidget);
    expect(find.text('Kitchen'), findsNWidgets(2));
    expect(find.text('Living'), findsNWidgets(2));
  });

  testWidgets('a playing group shows its speakers, the song and the album', (
    tester,
  ) async {
    await openSheet(
      tester,
      [
        player('kitchen', members: ['kitchen', 'living'], state: 'playing'),
        player('living', syncedTo: 'kitchen'),
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
              'album': {'name': 'Record'},
            },
          },
        }),
      },
    );
    expect(find.text('2 speakers'), findsOneWidget);
    expect(find.text('Song · Band'), findsOneWidget);
    expect(find.text('Record'), findsOneWidget);
    // While it plays, the names of the speakers are in the rows below rather than on the group.
    expect(find.text('Kitchen, Living'), findsNothing);
  });

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

    // Icons of the shared Music Assistant set; an old server's MDI name goes through the set's legacy map.
    Iterable<String> icons() => tester
        .widgetList<PlayerIcon>(find.byType(PlayerIcon))
        .map((i) => playerIconId(i.id));
    expect(icons(), containsAll(['kitchen', 'tv', 'smartphone']));
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

  testWidgets(
    'This device, advertised in Music Assistant, can sync with the speaker '
    'in use',
    (tester) async {
      final client = _FakeClient();
      when(() => client.command(any(), any())).thenAnswer((_) async => null);
      await openSheet(
        tester,
        [
          player('phone'),
          MaPlayer({
            'player_id': 'kitchen',
            'name': 'Kitchen',
            'available': true,
            'playback_state': 'playing',
            'can_group_with': ['phone'],
          }),
        ],
        client: client,
        ownSpeaker: 'phone',
        output: 'kitchen',
      );
      await tester.tap(find.byTooltip('Sync this device with Kitchen'));
      await tester.pump();
      final sent = verify(
        () => client.command('players/cmd/set_members', captureAny()),
      ).captured.single;
      expect(sent, {
        'target_player': 'kitchen',
        'player_ids_to_add': ['phone'],
      });
    },
  );

  testWidgets('synced with the speaker in use, This device can leave it', (
    tester,
  ) async {
    await openSheet(
      tester,
      [
        player('phone', syncedTo: 'kitchen'),
        player('kitchen', members: ['kitchen', 'phone'], state: 'playing'),
      ],
      ownSpeaker: 'phone',
      output: 'kitchen',
    );
    // Listed under the group it follows, as This device, with the chain to leave it, and nowhere else.
    expect(find.text('This device'), findsOneWidget);
    expect(find.byTooltip('Stop syncing this device'), findsOneWidget);
    expect(find.byTooltip('Sync this device with Kitchen'), findsNothing);
    final underGroup = tester.getTopLeft(find.text('This device'));
    final kitchen = tester.getTopLeft(find.text('Kitchen'));
    expect(underGroup.dy, greaterThan(kitchen.dy));
    expect(underGroup.dx, kitchen.dx, reason: 'indented like the speakers');
  });

  testWidgets('play/pause buttons stand in the same column, with or '
      'without a chain beside them', (tester) async {
    final client = _FakeClient();
    MaPlayer playing(String id, {List<String> groupable = const []}) =>
        MaPlayer({
          'player_id': id,
          'name': id[0].toUpperCase() + id.substring(1),
          'available': true,
          'playback_state': 'playing',
          'can_group_with': groupable,
        });
    MaQueue queue(String id) => MaQueue({
      'queue_id': id,
      'state': 'playing',
      'current_item': {'queue_item_id': 'q-$id', 'name': 'Song'},
    });
    await openSheet(
      tester,
      [
        // The output, which can sync with Living but not with Kitchen.
        playing('office', groupable: ['living']),
        playing('kitchen'),
        playing('living'),
      ],
      queues: {
        for (final id in ['office', 'kitchen', 'living']) id: queue(id),
      },
      client: client,
      output: 'office',
    );
    expect(find.byTooltip('Sync Living with Office'), findsOneWidget);
    expect(find.byTooltip('Sync Kitchen with Office'), findsNothing);
    final withChain = tester.getCenter(find.byTooltip('Pause Living'));
    final withoutChain = tester.getCenter(find.byTooltip('Pause Kitchen'));
    expect(withChain.dx, withoutChain.dx);
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
