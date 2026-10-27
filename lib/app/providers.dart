import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
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
  Uri streamUri(Track track) => ref.read(clientProvider)!.streamUri(track.id);

  @override
  Uri? artUri(String? coverArt) {
    if (coverArt == null) return null;
    final local = ref.read(artworkStoreProvider)?.existing(coverArt);
    if (local != null) return local.uri;
    return ref.read(clientProvider)?.coverArtUri(coverArt, size: 800);
  }

  @override
  Future<void> nowPlaying(Track track) async {
    if (ref.read(isOfflineProvider)) return;
    await ref
        .read(clientProvider)
        ?.scrobble(track.id, submission: false)
        .catchError((_) {});
  }

  @override
  Future<void> played(Track track) async {
    await ref.read(downloadManagerProvider)?.markPlayed(track.id);
    if (ref.read(isOfflineProvider)) return;
    await ref
        .read(clientProvider)
        ?.scrobble(track.id, submission: true)
        .catchError((_) {});
  }
}

/// Connects the player to the current session.
final playbackProvider = Provider<PlayerHandler>((ref) {
  final handler = ref.watch(playerHandlerProvider);
  ref.watch(clientProvider);
  handler.source = ref.read(clientProvider) == null
      ? null
      : SessionPlaybackSource(ref);
  return handler;
});
