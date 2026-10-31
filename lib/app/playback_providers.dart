import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/music_assistant/ma_client.dart';
import '../data/music_assistant/ma_models.dart';
import '../playback/ma_playback_controller.dart';
import '../playback/playback_controller.dart';
import '../ui/messages.dart';
import 'providers.dart';

// ------------------------------------------------------------ Music Assistant session

class MaCredentials {
  const MaCredentials({required this.baseUrl, required this.token});

  final Uri baseUrl;
  final String token;

  Map<String, String> toJson() => {
    'baseUrl': baseUrl.toString(),
    'token': token,
  };

  factory MaCredentials.fromJson(Map<String, dynamic> json) => MaCredentials(
    baseUrl: Uri.parse(json['baseUrl'] as String),
    token: json['token'] as String,
  );
}

const _maCredentialsKey = 'music_assistant';

Future<MaCredentials?> loadMaCredentials() async {
  try {
    final raw = await secureStorage.read(key: _maCredentialsKey);
    return raw == null
        ? null
        : MaCredentials.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  } on Exception {
    return null;
  }
}

final initialMaCredentialsProvider = Provider<MaCredentials?>((ref) => null);

class MaCredentialsNotifier extends Notifier<MaCredentials?> {
  @override
  MaCredentials? build() => ref.read(initialMaCredentialsProvider);

  Future<void> signIn({
    required String url,
    required String username,
    required String password,
  }) async {
    final base = normaliseMaUrl(url);
    final token = await maLogin(base, username: username, password: password);
    await _save(MaCredentials(baseUrl: base, token: token));
  }

  Future<void> signInWithToken({required String url, required String token}) =>
      _save(MaCredentials(baseUrl: normaliseMaUrl(url), token: token.trim()));

  Future<void> _save(MaCredentials credentials) async {
    await secureStorage.write(
      key: _maCredentialsKey,
      value: jsonEncode(credentials.toJson()),
    );
    state = credentials;
  }

  Future<void> signOut() async {
    ref.read(outputProvider.notifier).select(null);
    await secureStorage.delete(key: _maCredentialsKey);
    state = null;
  }
}

final maCredentialsProvider =
    NotifierProvider<MaCredentialsNotifier, MaCredentials?>(
      MaCredentialsNotifier.new,
    );

final maClientProvider = Provider<MusicAssistantClient?>((ref) {
  final credentials = ref.watch(maCredentialsProvider);
  if (credentials == null || ref.watch(isOfflineProvider)) return null;
  final client = MusicAssistantClient(credentials.baseUrl, credentials.token);
  unawaited(client.connect());
  ref.onDispose(client.close);
  return client;
});

final maStatusProvider = StreamProvider<MaConnectionStatus>((ref) async* {
  final client = ref.watch(maClientProvider);
  if (client == null) {
    yield MaConnectionStatus.disconnected;
    return;
  }
  yield client.status;
  yield* client.statusStream;
});

/// Players that are shown and able to play, by name, including members following another player.
final maPlayersProvider = StreamProvider<List<MaPlayer>>((ref) async* {
  final client = ref.watch(maClientProvider);
  if (client == null) {
    yield const [];
    return;
  }
  List<MaPlayer> selectable(Map<String, MaPlayer> players) =>
      players.values.where((p) => p.usable).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  yield selectable(client.players);
  yield* client.playersStream.map(selectable);
});

/// The queues of the Music Assistant players, by queue ID, which is the ID of the player.
final maQueuesProvider = StreamProvider<Map<String, MaQueue>>((ref) async* {
  final client = ref.watch(maClientProvider);
  if (client == null) {
    yield const {};
    return;
  }
  yield client.queues;
  yield* client.queuesStream;
});

/// OpenSubsonic providers configured in Music Assistant.
final maSubsonicProvidersProvider = FutureProvider<List<MaProvider>>((
  ref,
) async {
  final client = ref.watch(maClientProvider);
  final status = ref.watch(maStatusProvider).value;
  if (client == null || status != MaConnectionStatus.connected) return const [];
  final providers = await client.musicProviders();
  return providers.where((p) => p.domain == 'opensubsonic').toList();
});

class MaProviderChoiceNotifier extends Notifier<String?> {
  @override
  String? build() =>
      ref.read(sharedPreferencesProvider).getString('ma.subsonicProvider');

  Future<void> set(String? instanceId) async {
    state = instanceId;
    final prefs = ref.read(sharedPreferencesProvider);
    instanceId == null
        ? await prefs.remove('ma.subsonicProvider')
        : await prefs.setString('ma.subsonicProvider', instanceId);
  }
}

final maProviderChoiceProvider =
    NotifierProvider<MaProviderChoiceNotifier, String?>(
      MaProviderChoiceNotifier.new,
    );

/// The Music Assistant provider instance for our Subsonic server: the one the person picked, or the only one configured. Null means tracks are sent as stream URLs.
final maSubsonicInstanceProvider = Provider<String?>((ref) {
  final providers = ref.watch(maSubsonicProvidersProvider).value ?? const [];
  final choice = ref.watch(maProviderChoiceProvider);
  if (choice == 'url') return null;
  if (choice != null && providers.any((p) => p.instanceId == choice)) {
    return choice;
  }
  return providers.length == 1 ? providers.single.instanceId : null;
});

// ------------------------------------------------------------ output

/// When the output changes, a paused queue moves to the new output even when that output has something loaded. Off, a paused queue moves only to an output with nothing loaded, so it does not replace what someone else is playing. A playing queue always moves.
final movePausedQueueProvider = NotifierProvider<BoolSettingNotifier, bool>(
  () => BoolSettingNotifier('ma.movePausedQueue', false),
);

/// How long Music Assistant may stay unreachable before playback falls back to this device.
const maFallbackDelay = Duration(seconds: 30);

/// The Music Assistant player the app plays on, or null for this device. The app starts on this device, and comes back to it when Music Assistant stays unreachable for [maFallbackDelay].
class OutputNotifier extends Notifier<String?> {
  Timer? _fallback;

  @override
  String? build() {
    // Earlier versions kept the player across restarts.
    unawaited(ref.read(sharedPreferencesProvider).remove('ma.output'));
    ref.listen(maStatusProvider, (_, _) => _watchConnection());
    ref.onDispose(() => _fallback?.cancel());
    return null;
  }

  void select(String? playerId) {
    state = playerId;
    _watchConnection();
  }

  /// Arms the fallback to this device while a player is selected and Music Assistant is unreachable, and disarms it otherwise.
  void _watchConnection() {
    final connected =
        ref.read(maStatusProvider).value == MaConnectionStatus.connected;
    if (connected || state == null) {
      _fallback?.cancel();
      _fallback = null;
    } else {
      _fallback ??= Timer(maFallbackDelay, () {
        _fallback = null;
        state = null;
      });
    }
  }
}

final outputProvider = NotifierProvider<OutputNotifier, String?>(
  OutputNotifier.new,
);

/// Switches the output and moves the queue with it. It is a provider of its own because [playbackControllerProvider] depends on [outputProvider], so [OutputNotifier] cannot read the controller; it lives for the session, so a switch outlives the sheet that started it.
class OutputSwitcher {
  OutputSwitcher(this._ref);

  final Ref _ref;

  /// Switches the output and moves the queue with it: between two Music Assistant players through Music Assistant, and between this device and a player through the Subsonic tracks of the queue.
  ///
  /// A playing queue always moves. A paused one, such as a queue restored after a restart, moves when the target has nothing loaded or when [movePausedQueueProvider] is on. The output changes even when moving the queue fails; the error still reaches the caller.
  Future<void> switchTo(String? playerId) async {
    if (playerId == _ref.read(outputProvider)) return;
    final source = _ref.read(playbackControllerProvider);
    final queues = _ref.read(maClientProvider)?.queues ?? const {};
    final pausedMoves =
        _ref.read(movePausedQueueProvider) ||
        (playerId == null
            ? _ref.read(playerHandlerProvider).tracks.isEmpty
            : queues[playerId]?.currentItem == null);

    if (source is MusicAssistantPlaybackController && playerId != null) {
      // A transfer replaces the queue of the target with that of the source, even an empty one.
      final from = queues[source.playerId];
      final moving =
          from?.currentItem != null &&
          (from!.state == MaPlaybackState.playing || pausedMoves);
      try {
        if (moving) await source.transferTo(playerId);
      } finally {
        _ref.read(outputProvider.notifier).select(playerId);
      }
      return;
    }

    QueueSnapshot? snapshot;
    try {
      snapshot = await source.snapshot();
      if (snapshot != null && !(snapshot.playing || pausedMoves)) {
        snapshot = null;
      }
      if (snapshot != null) await source.stop();
    } finally {
      _ref.read(outputProvider.notifier).select(playerId);
    }
    if (snapshot == null) return;
    final target = _ref.read(playbackControllerProvider);
    await target.playTracks(snapshot.tracks, index: snapshot.index);
    if (snapshot.position > const Duration(seconds: 5)) {
      await target.seek(snapshot.position);
    }
    if (!snapshot.playing) await target.pause();
  }
}

final outputSwitcherProvider = Provider<OutputSwitcher>(OutputSwitcher.new);

final playbackControllerProvider = Provider<PlaybackController>((ref) {
  final handler = ref.watch(playbackProvider);
  final output = ref.watch(outputProvider);
  final client = ref.watch(maClientProvider);
  final PlaybackController controller;
  if (output != null && client != null) {
    controller = MusicAssistantPlaybackController(
      client,
      output,
      providerInstance: ref.watch(maSubsonicInstanceProvider),
      streamUri: (track) => ref.read(clientProvider)!.streamUri(track.id),
      onError: (e) => showMessage('$e'),
      lookupTrack: (id) async {
        try {
          return await ref.read(repositoryProvider)?.track(id);
        } on Exception {
          return null;
        }
      },
    );
  } else {
    controller = LocalPlaybackController(handler);
  }
  ref.onDispose(controller.dispose);
  return controller;
});

final nowPlayingProvider = StreamProvider<NowPlaying?>(
  (ref) => ref.watch(playbackControllerProvider).state,
);

/// Ticks twice a second while a screen shows the position.
final clockProvider = StreamProvider.autoDispose<DateTime>(
  (ref) =>
      Stream.periodic(const Duration(milliseconds: 500), (_) => DateTime.now()),
);
