import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/music_assistant/ma_client.dart';
import '../data/music_assistant/ma_models.dart';
import '../data/db/database.dart';
import '../downloads/download_settings.dart';
import '../playback/audio_format.dart';
import '../playback/endless_radio.dart';
import '../playback/sleep_timer.dart';
import '../playback/ma_playback_controller.dart';
import '../playback/playback_controller.dart';
import '../ui/messages.dart';
import 'providers.dart';
import 'sendspin_providers.dart';

export '../playback/audio_format.dart' show PlayingSource;

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

/// The connection to Music Assistant. It lives while signed in, apart from offline mode: a moment without network (Wi-Fi roaming, the device dozing) must not drop the connection, since the app then plays on this device. The client reconnects by itself, and [OutputNotifier] comes back to this device only when it stays disconnected.
final maClientProvider = Provider<MusicAssistantClient?>((ref) {
  final credentials = ref.watch(maCredentialsProvider);
  if (credentials == null || ref.watch(manualOfflineProvider)) return null;
  final client = MusicAssistantClient(credentials.baseUrl, credentials.token);
  unawaited(client.connect());
  ref.onDispose(client.close);
  return client;
});

/// Music Assistant sends the time of every speaker that plays, each second, which keeps the phone's radio awake. The connection rests once the app has been out of sight for a minute while this device is the output and the phone is no speaker, since then nothing in the app follows Music Assistant; it comes back when the app shows.
final maRestProvider = Provider<void>((ref) {
  final client = ref.watch(maClientProvider);
  if (client == null) return;
  if (ref.watch(appVisibleProvider) ||
      ref.watch(outputProvider) != null ||
      ref.watch(sendspinEnabledProvider)) {
    client.wake();
    return;
  }
  final timer = Timer(const Duration(minutes: 1), client.rest);
  ref.onDispose(timer.cancel);
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

/// The Music Assistant player the app plays on, or null for this device. The app starts on this device, and comes back to it only when the connection to the player is lost for [maFallbackDelay]: Music Assistant stays unreachable, or the player stays unavailable or gone.
class OutputNotifier extends Notifier<String?> {
  Timer? _fallback;

  @override
  String? build() {
    // Earlier versions kept the player across restarts.
    unawaited(ref.read(sharedPreferencesProvider).remove('ma.output'));
    ref.listen(maStatusProvider, (_, _) => _watchConnection());
    ref.listen(maAllPlayersProvider, (_, _) => _watchConnection());
    ref.onDispose(() => _fallback?.cancel());
    return null;
  }

  void select(String? playerId) {
    state = playerId;
    _watchConnection();
  }

  /// Arms the fallback to this device while a player is selected and out of reach, and disarms it otherwise.
  void _watchConnection() {
    final connected =
        ref.read(maStatusProvider).value == MaConnectionStatus.connected;
    final players = ref.read(maAllPlayersProvider).value;
    // An empty list is one not loaded yet, which says nothing about the player.
    final playerReachable =
        players == null ||
        players.isEmpty ||
        players.any((p) => p.id == state && p.available);
    if ((connected && playerReachable) || state == null) {
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

/// Whether [OutputSwitcher.switchTo] is moving the queue to another output. Meanwhile the new output can report nothing playing, which screens should not take as the end of playback.
class OutputSwitchingNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool switching) => state = switching;
}

final outputSwitchingProvider = NotifierProvider<OutputSwitchingNotifier, bool>(
  OutputSwitchingNotifier.new,
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
    final switching = _ref.read(outputSwitchingProvider.notifier);
    switching.set(true);
    try {
      await _switchTo(playerId);
    } finally {
      switching.set(false);
    }
  }

  Future<void> _switchTo(String? playerId) async {
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

  /// Hands control back to this device and leaves the player as it is: it keeps playing, and the queue of this device stays where it was.
  void disconnect() => _ref.read(outputProvider.notifier).select(null);
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
      // Only whether the output is this phone counts: the player list changes with every volume step, and a new controller would lose the Subsonic track until it looks it up again.
      thisDevice: ref.watch(
        ownPlayerIdsProvider.select((ids) => ids.contains(output)),
      ),
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

/// Every Music Assistant player, hidden ones included.
final maAllPlayersProvider = StreamProvider<List<MaPlayer>>((ref) async* {
  final client = ref.watch(maClientProvider);
  if (client == null) {
    yield const [];
    return;
  }
  yield client.players.values.toList();
  yield* client.playersStream.map((p) => p.values.toList());
});

/// The players that stand for this phone as a speaker: its own Sendspin player, which Music Assistant names by the client id, and any player that plays through it. The Play on sheet shows them as "This device".
final ownPlayerIdsProvider = Provider<Set<String>>((ref) {
  final own = ref.watch(ownSpeakerIdProvider);
  if (own == null) return const {};
  return {
    own,
    for (final p in ref.watch(maAllPlayersProvider).value ?? const <MaPlayer>[])
      if (p.isBackedBy(own)) p.id,
  };
});

/// The Music Assistant player whose queue plays on this phone as a speaker: the leader of the group the phone follows, or the phone itself. Null while the speaker is off or Music Assistant does not list it.
final speakerSourceProvider = Provider<String?>((ref) {
  final ids = ref.watch(ownPlayerIdsProvider);
  if (ids.isEmpty) return null;
  final players = ref.watch(maAllPlayersProvider).value ?? const <MaPlayer>[];
  // A shown player that plays through the phone comes before the hidden protocol player under it.
  final own = [
    for (final p in players)
      if (ids.contains(p.id)) p,
  ]..sort((a, b) => (a.usable ? 0 : 1).compareTo(b.usable ? 0 : 1));
  if (own.isEmpty) return null;
  final p = own.first;
  return p.syncedTo ?? p.activeGroup ?? p.id;
});

/// The player whose queue plays on this phone right now, or null while the speaker is silent.
final _playingSpeakerSourceProvider = Provider<String?>((ref) {
  final playing = ref.watch(sendspinStatusProvider).value?.playing ?? false;
  return playing ? ref.watch(speakerSourceProvider) : null;
});

/// When Music Assistant starts playing on this phone as a speaker, or puts it in another group, the app follows that player or group, so the mini player and the player show what plays here with every control, as for any output. It follows even when the person had picked another speaker: the phone joined from outside (the Music Assistant interface, another app) is what plays here now. Only a change follows, so a speaker picked afterwards stays picked.
final followSpeakerProvider = Provider<void>((ref) {
  ref.listen(_playingSpeakerSourceProvider, (previous, source) {
    if (source == null || source == previous) return;
    if (ref.read(outputProvider) != source) {
      ref.read(outputProvider.notifier).select(source);
    }
  });
});

/// Where the audio of the current song comes from, which decides what the streaming quality changes.
final playingSourceProvider = Provider.autoDispose<PlayingSource?>((ref) {
  final id = ref.watch(nowPlayingProvider.select((s) => s.value?.track?.id));
  return id == null ? null : ref.watch(deliveryProvider(id)).source;
});

/// What this device gets of the song [trackId]. Music Assistant fetches the original file for the song it plays. Otherwise the downloaded file plays, whose extension tells whether it was transcoded, or else the stream at the streaming quality.
final deliveryProvider = Provider.autoDispose.family<Delivery, String>((
  ref,
  trackId,
) {
  final playingId = ref.watch(
    nowPlayingProvider.select((s) => s.value?.track?.id),
  );
  if (ref.watch(outputProvider) != null && playingId == trackId) {
    return (
      source: PlayingSource.musicAssistant,
      format: null,
      maxBitRate: null,
      size: null,
    );
  }
  final file = ref.watch(trackFileProvider(trackId)).value;
  final path = file?.path;
  if (file?.status == FileStatus.complete && path != null) {
    final dot = path.lastIndexOf('.');
    return (
      source: PlayingSource.download,
      format: dot < 0 ? null : path.substring(dot + 1),
      maxBitRate: null,
      size: file!.size,
    );
  }
  final quality = ref.watch(streamingQualityProvider);
  // On servers with the `transcoding` extension, the server chose the stream of the song.
  final choice = ref.watch(transcodeDeciderProvider)?.cached(trackId, quality);
  if (choice != null) {
    final stream = choice.stream;
    return (
      source: PlayingSource.stream,
      format: choice.transcoded ? stream?.extension : null,
      maxBitRate: choice.transcoded && stream?.audioBitrate != null
          ? stream!.audioBitrate! ~/ 1000
          : null,
      size: null,
    );
  }
  return (
    source: PlayingSource.stream,
    format: quality.format,
    maxBitRate: quality.maxBitRate,
    size: null,
  );
});

/// Plays the past queue at [index] again from the song and position it had reached, and drops it from the past queues. The queue it replaces takes its place there.
final playPastQueueProvider = Provider<Future<void> Function(int index)>(
  (ref) => (index) async {
    final queues = ref.read(pastQueuesProvider).value ?? const [];
    if (index >= queues.length) return;
    final queue = queues[index];
    await ref.read(pastQueuesProvider.notifier).removeAt(index);
    final controller = ref.read(playbackControllerProvider);
    await controller.playTracks(queue.tracks, index: queue.index);
    if (queue.position > const Duration(seconds: 1)) {
      await controller.seek(queue.position);
    }
  },
);

/// Sets the streaming quality of the current network. A song streaming on this device reloads at the new quality from where it was.
final setStreamingQualityProvider =
    Provider<Future<void> Function(DownloadQuality)>(
      (ref) => (quality) async {
        await ref
            .read(ref.read(currentQualitySettingProvider).notifier)
            .set(quality);
        if (ref.read(playingSourceProvider) == PlayingSource.stream) {
          await ref.read(playerHandlerProvider).reloadSources();
        }
      },
    );

/// The format of the track that plays, as [describeFormat] puts it.
final playingFormatProvider = Provider.autoDispose<PlayingFormat?>((ref) {
  final track = ref.watch(nowPlayingProvider.select((s) => s.value?.track));
  if (track == null) return null;
  final delivery = ref.watch(deliveryProvider(track.id));
  return describeFormat(
    track,
    format: delivery.format,
    maxBitRate: deliveredBitRate(track, delivery),
  );
});

/// Pauses playback when the sleep timer ends. After a set time, on this device the volume first fades out over [sleepFade]. At the end of a song or album, playback pauses as the next song or album starts, back at its beginning.
final sleepTimerRunnerProvider = Provider<void>((ref) {
  Timer? timer;
  void stop() => ref.read(sleepTimerProvider.notifier).set(null);

  Future<void> fadeAndPause() async {
    stop();
    final controller = ref.read(playbackControllerProvider);
    if (ref.read(outputProvider) != null) return controller.pause();
    final player = ref.read(playerHandlerProvider).player;
    final from = player.volume;
    const steps = 40;
    for (var i = 1; i <= steps && player.playing; i++) {
      await Future<void>.delayed(sleepFade ~/ steps);
      await player.setVolume(from * (1 - i / steps));
    }
    await controller.pause();
    await player.setVolume(from);
  }

  ref.listen(sleepTimerProvider, (_, sleep) {
    timer?.cancel();
    final end = sleep?.endsAt;
    if (end == null) return;
    timer = Timer(
      end.difference(DateTime.now()),
      () => unawaited(fadeAndPause()),
    );
  }, fireImmediately: true);

  ref.listen(nowPlayingProvider, (_, next) {
    final sleep = ref.read(sleepTimerProvider);
    if (sleep == null) return;
    final np = next.value;
    if (np == null) return stop();
    if (!sleep.endsWith(np.track)) return;
    stop();
    unawaited(() async {
      final controller = ref.read(playbackControllerProvider);
      await controller.pause();
      await controller.seek(Duration.zero);
    }());
  });
  ref.onDispose(() => timer?.cancel());
});

/// Endless radio for the output in use. On a Music Assistant player it is the player's Autoplay, which Music Assistant fills itself from its providers; on this device it is the app's own, which needs sonic similarity on the server.
///
/// A queue that repeats never runs out, so while repeat is on endless radio is off and blocked. Music Assistant switches Autoplay off itself then; on this device the setting stays, and endless radio comes back with repeat off.
final outputEndlessRadioProvider =
    Provider<({bool available, bool on, bool blocked})>((ref) {
      final repeat = ref.watch(
        nowPlayingProvider.select((s) => s.value?.repeat ?? Repeat.off),
      );
      final blocked = repeat != Repeat.off;
      if (ref.watch(playbackControllerProvider)
          is MusicAssistantPlaybackController) {
        final on = ref.watch(
          nowPlayingProvider.select((s) => s.value?.autoplay ?? false),
        );
        return (available: true, on: on && !blocked, blocked: blocked);
      }
      // Its songs come from the server, so offline the button goes.
      return (
        available: ref.watch(canMixProvider) && !ref.watch(isOfflineProvider),
        on: ref.watch(endlessRadioProvider) && !blocked,
        blocked: blocked,
      );
    });

/// Turns endless radio on or off for the output in use: the Autoplay of a Music Assistant player, or the setting of this device.
final setEndlessRadioProvider = Provider<Future<void> Function(bool on)>(
  (ref) => (on) async {
    final controller = ref.read(playbackControllerProvider);
    if (controller is MusicAssistantPlaybackController) {
      await controller.setAutoplay(on);
    } else {
      await ref.read(endlessRadioProvider.notifier).set(on);
    }
  },
);

/// Endless radio on this device: when the last song of a queue that does not repeat starts, songs that sound like it are added to the queue. Each song extends the queue once. A Music Assistant player fills its queue itself through Autoplay, so it is left alone.
final endlessRadioRunnerProvider = Provider<void>((ref) {
  String? extendedFrom;
  ref.listen(nowPlayingProvider, (_, next) {
    final np = next.value;
    if (np == null || !atQueueEnd(np)) return;
    if (ref.read(playbackControllerProvider)
        is MusicAssistantPlaybackController) {
      return;
    }
    final track = np.track!;
    if (extendedFrom == track.id ||
        !ref.read(endlessRadioProvider) ||
        !ref.read(canMixProvider) ||
        ref.read(isOfflineProvider)) {
      return;
    }
    extendedFrom = track.id;
    unawaited(() async {
      try {
        final mix = await endlessMix(ref.read(repositoryProvider)!, track);
        final more = songsToAdd(mix, [for (final e in np.queue) e.id]);
        // The songs come too late when the queue ran out or another took its place while the server answered.
        final now = ref.read(nowPlayingProvider).value;
        if (now?.queue.lastOrNull?.trackId != track.id) return;
        if (more.isNotEmpty) {
          await ref.read(playbackControllerProvider).addTracks(more);
        }
      } on Exception {
        // The queue ends as it would without endless radio.
      }
    }());
  });
});

/// Reports plays on the Music Assistant player in use to the Subsonic server, when [maScrobblingProvider] and [scrobblingProvider] are on: "now playing" when a song starts, and a play once it [countsAsPlayed]. Music Assistant does not report them itself.
final maScrobbleRunnerProvider = Provider<void>((ref) {
  String? started;
  String? submitted;
  Timer? check;
  bool reports() =>
      ref.read(outputProvider) != null &&
      ref.read(maScrobblingProvider) &&
      ref.read(scrobblingProvider) &&
      !ref.read(isOfflineProvider);

  void evaluate(NowPlaying? np) {
    check?.cancel();
    final track = np?.track;
    if (np == null || track == null || !reports()) return;
    final client = ref.read(clientProvider);
    if (client == null) return;
    if (np.playing && started != track.id) {
      started = track.id;
      unawaited(
        client.scrobble(track.id, submission: false).catchError((_) {}),
      );
    }
    if (submitted == track.id || !np.playing) return;
    if (countsAsPlayed(np.positionNow(), np.duration)) {
      submitted = track.id;
      unawaited(client.scrobble(track.id, submission: true).catchError((_) {}));
      return;
    }
    // Music Assistant reports the position only now and then, so the threshold is checked again while the song plays.
    check = Timer(const Duration(seconds: 10), () {
      evaluate(ref.read(nowPlayingProvider).value);
    });
  }

  ref.listen(nowPlayingProvider, (_, next) => evaluate(next.value));
  ref.onDispose(() => check?.cancel());
});

/// Turns crossfade on or off for the queue of the Music Assistant player in use, following the crossfade setting. Music Assistant sets the length of the fade per player, and never fades between songs of the same album.
final maCrossfadeProvider = Provider<void>((ref) {
  final output = ref.watch(outputProvider);
  final client = ref.watch(maClientProvider);
  final on = ref.watch(crossfadeProvider) > 0;
  final connected =
      ref.watch(maStatusProvider).value == MaConnectionStatus.connected;
  if (output == null || client == null || !connected) return;
  unawaited(() async {
    try {
      await client.command('player_queues/crossfade', {
        'queue_id': output,
        'crossfade_enabled': on,
      });
    } on Exception {
      // An older server without the command keeps its own setting.
    }
  }());
});

final nowPlayingProvider = StreamProvider<NowPlaying?>(
  (ref) => ref.watch(playbackControllerProvider).state,
);

/// Whether the app shows on the screen. The clocks below stop while it does not, so the phone can sleep between songs.
class AppVisibleNotifier extends Notifier<bool> {
  @override
  bool build() {
    final listener = AppLifecycleListener(
      onStateChange: (s) => state = _visible(s),
    );
    ref.onDispose(listener.dispose);
    return _visible(WidgetsBinding.instance.lifecycleState);
  }

  /// Inactive still shows, as under the notification shade; an unknown state counts as showing.
  static bool _visible(AppLifecycleState? s) =>
      s == null ||
      s == AppLifecycleState.resumed ||
      s == AppLifecycleState.inactive;
}

final appVisibleProvider = NotifierProvider<AppVisibleNotifier, bool>(
  AppVisibleNotifier.new,
);

Stream<DateTime> _ticks(bool on) => on
    ? Stream.periodic(const Duration(milliseconds: 500), (_) => DateTime.now())
    : const Stream.empty();

/// Ticks twice a second while the app shows, for a countdown.
final clockProvider = StreamProvider.autoDispose<DateTime>(
  (ref) => _ticks(ref.watch(appVisibleProvider)),
);

/// Ticks twice a second while a song plays and the app shows, for the position. A paused position does not move, and each change of the player brings a new [NowPlaying].
final positionClockProvider = StreamProvider.autoDispose<DateTime>(
  (ref) => _ticks(
    ref.watch(appVisibleProvider) &&
        ref.watch(nowPlayingProvider.select((s) => s.value?.playing ?? false)),
  ),
);
