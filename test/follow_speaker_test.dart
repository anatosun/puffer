import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:puffer/app/playback_providers.dart';
import 'package:puffer/app/providers.dart';
import 'package:puffer/app/sendspin_providers.dart';
import 'package:puffer/data/music_assistant/ma_client.dart';
import 'package:puffer/data/music_assistant/ma_models.dart';
import 'package:puffer/sendspin/session.dart';
import 'package:puffer/playback/player_handler.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

MaPlayer player(
  String id, {
  String? syncedTo,
  bool hidden = false,
  List<String> protocols = const [],
}) => MaPlayer({
  'player_id': id,
  'name': id,
  'available': true,
  'hide_in_ui': hidden,
  'synced_to': ?syncedTo,
  'output_protocols': [
    for (final p in protocols)
      {
        'output_protocol_id': p,
        'name': 'Sendspin',
        'protocol_domain': 'sendspin',
      },
  ],
});

Future<(ProviderContainer, StreamController<SendspinStatus>)> setUp(
  List<MaPlayer> players,
) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final status = StreamController<SendspinStatus>();
  final c = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      ownSpeakerIdProvider.overrideWithValue('phone'),
      maPlayersProvider.overrideWithValue(
        AsyncData([
          for (final p in players)
            if (p.usable) p,
        ]),
      ),
      maAllPlayersProvider.overrideWithValue(AsyncData(players)),
      maStatusProvider.overrideWithValue(
        const AsyncData(MaConnectionStatus.connected),
      ),
      sendspinStatusProvider.overrideWith((ref) => status.stream),
    ],
  );
  c.listen(followSpeakerProvider, (_, _) {});
  return (c, status);
}

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  controllerTests();
  test(
    'music starting on the phone as a speaker shows in the player',
    () async {
      final (c, status) = await setUp([player('phone'), player('kitchen')]);
      status.add(const SendspinStatus(connected: true));
      await settle();
      expect(c.read(outputProvider), isNull);

      status.add(const SendspinStatus(connected: true, playing: true));
      await settle();
      expect(c.read(outputProvider), 'phone');
    },
  );

  test('a phone playing in a group follows the leader of the group', () async {
    final (c, status) = await setUp([
      player('phone', syncedTo: 'kitchen'),
      player('kitchen'),
    ]);
    status.add(const SendspinStatus(connected: true, playing: true));
    await settle();
    expect(c.read(outputProvider), 'kitchen');
  });

  test('a speaker the person picked stays the output', () async {
    final (c, status) = await setUp([player('phone'), player('kitchen')]);
    c.read(outputProvider.notifier).select('kitchen');
    status.add(const SendspinStatus(connected: true, playing: true));
    await settle();
    expect(c.read(outputProvider), 'kitchen');
  });

  test(
    'a player that Music Assistant merged over the phone counts as the phone',
    () async {
      final (c, status) = await setUp([
        player('phone', hidden: true),
        player('up_puffer', protocols: ['phone']),
        player('kitchen'),
      ]);
      expect(c.read(ownPlayerIdsProvider), {'phone', 'up_puffer'});
      status.add(const SendspinStatus(connected: true, playing: true));
      await settle();
      expect(c.read(outputProvider), 'up_puffer');
    },
  );
}

class _Handler extends Mock implements PlayerHandler {}

class _Kitchen extends OutputNotifier {
  @override
  String? build() => 'kitchen';
}

void controllerTests() {
  test('a change in the players, such as a volume step, keeps the playback controller', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final players = StreamController<List<MaPlayer>>();
    final client = MusicAssistantClient(Uri.parse('http://ma:8095'), 't');
    final c = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        playbackProvider.overrideWithValue(_Handler()),
        outputProvider.overrideWith(_Kitchen.new),
        maClientProvider.overrideWithValue(client),
        maSubsonicInstanceProvider.overrideWithValue(null),
        ownSpeakerIdProvider.overrideWithValue('phone'),
        maAllPlayersProvider.overrideWith((ref) => players.stream),
      ],
    );
    addTearDown(c.dispose);
    c.listen(playbackControllerProvider, (_, _) {});
    players.add([player('kitchen'), player('phone')]);
    await settle();
    final before = c.read(playbackControllerProvider);
    players.add([
      MaPlayer({'player_id': 'kitchen', 'name': 'kitchen', 'volume_level': 40}),
      player('phone'),
    ]);
    await settle();
    expect(identical(c.read(playbackControllerProvider), before), isTrue);
  });
}
