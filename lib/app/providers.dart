import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../data/artwork_store.dart';
import '../data/db/database.dart';
import '../data/repositories/library_repository.dart';
import '../data/subsonic/models.dart';
import '../data/subsonic/subsonic_client.dart';
import '../downloads/download_manager.dart';
import '../downloads/download_settings.dart';
import '../downloads/transfer_backend.dart';
import '../playback/player_handler.dart';
import '../playback/queue_store.dart';
import '../playback/replay_gain.dart';

// ------------------------------------------------------------ overridden in main()

final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError(),
);
final databaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError(),
);
final playerHandlerProvider = Provider<PlayerHandler>(
  (ref) => throw UnimplementedError(),
);
final supportDirectoryProvider = Provider<Directory>(
  (ref) => throw UnimplementedError(),
);
final initialCredentialsProvider = Provider<ServerCredentials?>((ref) => null);

// ------------------------------------------------------------ session

const _credentialsKey = 'credentials';
const secureStorage = FlutterSecureStorage();

Future<ServerCredentials?> loadCredentials() async {
  try {
    final raw = await secureStorage.read(key: _credentialsKey);
    return raw == null
        ? null
        : ServerCredentials.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  } on Exception {
    return null;
  }
}

class CredentialsNotifier extends Notifier<ServerCredentials?> {
  @override
  ServerCredentials? build() => ref.read(initialCredentialsProvider);

  /// Checks the credentials against the server and stores them.
  Future<void> signIn(ServerCredentials credentials) async {
    final client = SubsonicClient(credentials);
    try {
      await client.ping();
    } finally {
      client.close();
    }
    await secureStorage.write(
      key: _credentialsKey,
      value: jsonEncode(credentials.toJson()),
    );
    state = credentials;
  }

  Future<void> signOut() async {
    await ref.read(downloadManagerProvider)?.removeAll();
    await ref.read(artworkStoreProvider)?.clear();
    await ref.read(queueStoreProvider).clear();
    await secureStorage.delete(key: _credentialsKey);
    state = null;
  }
}

final credentialsProvider =
    NotifierProvider<CredentialsNotifier, ServerCredentials?>(
      CredentialsNotifier.new,
    );

final clientProvider = Provider<SubsonicClient?>((ref) {
  final credentials = ref.watch(credentialsProvider);
  if (credentials == null) return null;
  final client = SubsonicClient(credentials);
  unawaited(client.loadExtensions().catchError((_) => const <String>{}));
  ref.onDispose(client.close);
  return client;
});

// ------------------------------------------------------------ appearance

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() =>
      ThemeMode.values.asNameMap()[ref
          .read(sharedPreferencesProvider)
          .getString('themeMode')] ??
      ThemeMode.system;

  Future<void> set(ThemeMode mode) async {
    state = mode;
    await ref.read(sharedPreferencesProvider).setString('themeMode', mode.name);
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);

/// A boolean setting stored under [key].
class BoolSettingNotifier extends Notifier<bool> {
  BoolSettingNotifier(this.key, this.defaultValue);

  final String key;
  final bool defaultValue;

  @override
  bool build() =>
      ref.read(sharedPreferencesProvider).getBool(key) ?? defaultValue;

  Future<void> set(bool value) async {
    state = value;
    await ref.read(sharedPreferencesProvider).setBool(key, value);
  }
}

/// Backgrounds of album pages and of the player take their colours from the artwork.
final artworkColoursProvider = NotifierProvider<BoolSettingNotifier, bool>(
  () => BoolSettingNotifier('experience.artworkColours', true),
);

/// Plays are reported to the server, which uses them for "Recently played" and "Most played".
final scrobblingProvider = NotifierProvider<BoolSettingNotifier, bool>(
  () => BoolSettingNotifier('playback.scrobble', true),
);

/// Streaming quality, one setting for Wi-Fi and wired networks and one for cellular.
class StreamingQualityNotifier extends Notifier<DownloadQuality> {
  StreamingQualityNotifier(this.key);

  final String key;

  @override
  DownloadQuality build() =>
      DownloadQuality.values.asNameMap()[ref
          .read(sharedPreferencesProvider)
          .getString(key)] ??
      DownloadQuality.original;

  Future<void> set(DownloadQuality quality) async {
    state = quality;
    await ref.read(sharedPreferencesProvider).setString(key, quality.name);
  }
}

final wifiQualityProvider =
    NotifierProvider<StreamingQualityNotifier, DownloadQuality>(
      () => StreamingQualityNotifier('playback.qualityWifi'),
    );
final cellularQualityProvider =
    NotifierProvider<StreamingQualityNotifier, DownloadQuality>(
      () => StreamingQualityNotifier('playback.qualityCellular'),
    );

final replayGainProvider = NotifierProvider<ReplayGainNotifier, ReplayGainMode>(
  ReplayGainNotifier.new,
);

class ReplayGainNotifier extends Notifier<ReplayGainMode> {
  @override
  ReplayGainMode build() =>
      ReplayGainMode.values.asNameMap()[ref
          .read(sharedPreferencesProvider)
          .getString('playback.replayGain')] ??
      ReplayGainMode.track;

  Future<void> set(ReplayGainMode mode) async {
    state = mode;
    await ref
        .read(sharedPreferencesProvider)
        .setString('playback.replayGain', mode.name);
    final handler = ref.read(playerHandlerProvider);
    final track = handler.currentTrack;
    if (track != null) {
      await handler.player.setVolume(replayGainVolume(track, mode));
    }
  }
}

/// The streaming quality for the current network.
final streamingQualityProvider = Provider<DownloadQuality>((ref) {
  final networks = ref.watch(connectivityProvider).value ?? const [];
  final cellular =
      networks.contains(ConnectivityResult.mobile) &&
      !networks.contains(ConnectivityResult.wifi) &&
      !networks.contains(ConnectivityResult.ethernet);
  return ref.watch(cellular ? cellularQualityProvider : wifiQualityProvider);
});

// ------------------------------------------------------------ offline

final connectivityProvider = StreamProvider<List<ConnectivityResult>>((
  ref,
) async* {
  final connectivity = Connectivity();
  yield await connectivity.checkConnectivity();
  yield* connectivity.onConnectivityChanged;
});

class ManualOfflineNotifier extends Notifier<bool> {
  @override
  bool build() =>
      ref.read(sharedPreferencesProvider).getBool('offlineMode') ?? false;

  Future<void> set(bool value) async {
    state = value;
    await ref.read(sharedPreferencesProvider).setBool('offlineMode', value);
  }
}

final manualOfflineProvider = NotifierProvider<ManualOfflineNotifier, bool>(
  ManualOfflineNotifier.new,
);

/// True when the person turned on offline mode or the device has no network.
final isOfflineProvider = Provider<bool>((ref) {
  if (ref.watch(manualOfflineProvider)) return true;
  final results = ref.watch(connectivityProvider).value;
  return results != null && results.every((r) => r == ConnectivityResult.none);
});

// ------------------------------------------------------------ library

final repositoryProvider = Provider<LibraryRepository?>((ref) {
  final client = ref.watch(clientProvider);
  if (client == null) return null;
  return LibraryRepository(
    client,
    ref.watch(databaseProvider),
    isOffline: () => ref.read(isOfflineProvider),
  );
});

final artworkStoreProvider = Provider<ArtworkStore?>((ref) {
  final client = ref.watch(clientProvider);
  if (client == null) return null;
  return ArtworkStore(
    Directory(p.join(ref.watch(supportDirectoryProvider).path, 'artwork')),
    (id) => client.coverArtUri(id, size: 800),
  );
});

// ------------------------------------------------------------ downloads

class DownloadSettingsNotifier extends Notifier<DownloadSettings> {
  @override
  DownloadSettings build() =>
      DownloadSettings.load(ref.read(sharedPreferencesProvider));

  Future<void> update(DownloadSettings settings) async {
    final automaticChanged =
        settings.automaticDownloads != state.automaticDownloads;
    state = settings;
    await settings.save(ref.read(sharedPreferencesProvider));
    if (automaticChanged) await ref.read(syncAutomaticDownloadsProvider)();
    await ref.read(downloadManagerProvider)?.optimizeStorage();
  }
}

final downloadSettingsProvider =
    NotifierProvider<DownloadSettingsNotifier, DownloadSettings>(
      DownloadSettingsNotifier.new,
    );

final _transferBackendProvider = Provider<TransferBackend>(
  (ref) => BackgroundDownloaderBackend(),
);

final downloadManagerProvider = Provider<DownloadManager?>((ref) {
  final repository = ref.watch(repositoryProvider);
  final client = ref.watch(clientProvider);
  final artwork = ref.watch(artworkStoreProvider);
  if (repository == null || client == null || artwork == null) return null;

  Future<void> art(String? coverArt) async {
    if (coverArt != null) await artwork.ensure(coverArt).catchError((_) {});
  }

  Future<List<Track>> resolve(PinKind kind, String id) async {
    switch (kind) {
      case PinKind.track:
        return [await repository.track(id)];
      case PinKind.album:
        final album = await repository.album(id);
        await art(album.coverArt);
        return album.songs;
      case PinKind.playlist:
        final playlist = await repository.playlist(id);
        await art(playlist.coverArt);
        return playlist.entries;
      case PinKind.artist:
        final artist = await repository.artist(id);
        await art(artist.coverArt);
        final tracks = <Track>[];
        for (final a in artist.albums) {
          final album = await repository.album(a.id);
          await art(album.coverArt);
          tracks.addAll(album.songs);
        }
        return tracks;
    }
  }

  final manager = DownloadManager(
    db: ref.watch(databaseProvider),
    backend: ref.watch(_transferBackendProvider),
    resolve: resolve,
    urlFor: (track, quality) => client.downloadUri(
      track.id,
      format: quality.format,
      maxBitRate: quality.maxBitRate,
    ),
    settings: () => ref.read(downloadSettingsProvider),
    fetchArtwork: art,
  );
  unawaited(manager.start());
  ref.onDispose(manager.dispose);
  return manager;
});

/// Pins the starred items when automatic downloads are on, and releases automatic pins otherwise.
final syncAutomaticDownloadsProvider = Provider<Future<void> Function()>(
  (ref) => () async {
    final manager = ref.read(downloadManagerProvider);
    final client = ref.read(clientProvider);
    if (manager == null || client == null || ref.read(isOfflineProvider)) {
      return;
    }
    final starred = ref.read(downloadSettingsProvider).automaticDownloads
        ? await client.getStarred()
        : const Starred(artists: [], albums: [], tracks: []);
    await manager.syncAutomatic(starred);
  },
);

/// Runs once per session: syncs pinned containers and automatic downloads.
final startupSyncProvider = FutureProvider<void>((ref) async {
  final manager = ref.watch(downloadManagerProvider);
  if (manager == null || ref.read(isOfflineProvider)) return;
  await manager.syncPins();
  await ref.read(syncAutomaticDownloadsProvider)();
});

final pinStateProvider = StreamProvider.family<PinState, (PinKind, String)>((
  ref,
  key,
) {
  final manager = ref.watch(downloadManagerProvider);
  return manager == null
      ? Stream.value(PinState.none)
      : manager.watchPin(key.$1, key.$2);
});

final trackFileProvider = StreamProvider.family<TrackFile?, String>((
  ref,
  trackId,
) {
  final manager = ref.watch(downloadManagerProvider);
  return manager == null ? Stream.value(null) : manager.watchTrack(trackId);
});

final completeTrackIdsProvider = StreamProvider<List<String>>((ref) {
  final manager = ref.watch(downloadManagerProvider);
  return manager == null
      ? Stream.value(const [])
      : manager.watchCompleteTrackIds();
});

/// Metadata of every downloaded track.
final downloadedTracksProvider = FutureProvider<List<Track>>((ref) async {
  final ids = await ref.watch(completeTrackIdsProvider.future);
  final repository = ref.watch(repositoryProvider);
  return repository == null ? const [] : repository.cachedTracks(ids);
});

final downloadedTrackIdSetProvider = Provider<Set<String>>(
  (ref) => {...?ref.watch(completeTrackIdsProvider).value},
);

// ------------------------------------------------------------ playback

class SessionPlaybackSource implements PlaybackSource {
  SessionPlaybackSource(this.ref);

  final Ref ref;

  @override
  Future<String?> localPath(String trackId) async =>
      ref.read(downloadManagerProvider)?.localPath(trackId);

  @override
  Uri streamUri(Track track) {
    final quality = ref.read(streamingQualityProvider);
    return ref
        .read(clientProvider)!
        .streamUri(
          track.id,
          format: quality.format,
          maxBitRate: quality.maxBitRate,
        );
  }

  @override
  Uri? artUri(String? coverArt) {
    if (coverArt == null) return null;
    final local = ref.read(artworkStoreProvider)?.existing(coverArt);
    if (local != null) return local.uri;
    return ref.read(clientProvider)?.coverArtUri(coverArt, size: 800);
  }

  @override
  double volumeFor(Track track) =>
      replayGainVolume(track, ref.read(replayGainProvider));

  @override
  Future<void> nowPlaying(Track track) async {
    if (ref.read(isOfflineProvider) || !ref.read(scrobblingProvider)) return;
    await ref
        .read(clientProvider)
        ?.scrobble(track.id, submission: false)
        .catchError((_) {});
  }

  @override
  Future<void> played(Track track) async {
    await ref.read(downloadManagerProvider)?.markPlayed(track.id);
    if (ref.read(isOfflineProvider) || !ref.read(scrobblingProvider)) return;
    await ref
        .read(clientProvider)
        ?.scrobble(track.id, submission: true)
        .catchError((_) {});
  }
}

final queueStoreProvider = Provider<QueueStore>(
  (ref) => QueueStore(
    File(p.join(ref.watch(supportDirectoryProvider).path, 'queue.json')),
  ),
);

/// Restores the queue of this device once per session and saves it when it changes, when playback pauses, and every 15 seconds while playing.
final queuePersistenceProvider = Provider<void>((ref) {
  final handler = ref.watch(playbackProvider);
  final store = ref.watch(queueStoreProvider);
  if (handler.source == null) return;

  var restored = false;
  Timer? pending;
  void save() {
    if (!restored) return;
    pending?.cancel();
    pending = Timer(const Duration(seconds: 1), () {
      store.save(
        handler.tracks,
        handler.player.currentIndex ?? 0,
        handler.player.position,
      );
    });
  }

  () async {
    final saved = await store.load();
    if (saved != null && handler.tracks.isEmpty) {
      await handler.restore(saved.tracks, saved.index, saved.position);
    }
    restored = true;
  }();

  final subscriptions = [
    handler.queue.listen((_) => save()),
    handler.player.currentIndexStream.listen((_) => save()),
    handler.player.playingStream.listen((_) => save()),
  ];
  final timer = Timer.periodic(const Duration(seconds: 15), (_) {
    if (handler.player.playing) save();
  });
  ref.onDispose(() {
    pending?.cancel();
    timer.cancel();
    for (final s in subscriptions) {
      s.cancel();
    }
  });
});

/// Connects the player to the current session.
final playbackProvider = Provider<PlayerHandler>((ref) {
  final handler = ref.watch(playerHandlerProvider);
  ref.watch(clientProvider);
  handler.source = ref.read(clientProvider) == null
      ? null
      : SessionPlaybackSource(ref);
  return handler;
});
