import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../data/artwork_cache.dart';
import '../data/artwork_store.dart';
import '../data/db/database.dart';
import '../data/repositories/library_repository.dart';
import '../data/subsonic/models.dart';
import '../data/subsonic/server_address.dart';
import '../data/subsonic/subsonic_client.dart';
import '../downloads/download_manager.dart';
import '../downloads/download_settings.dart';
import '../downloads/transfer_backend.dart';
import '../playback/past_queues.dart';
import '../playback/player_handler.dart';
import '../playback/prefetch_cache.dart';
import '../playback/queue_store.dart';
import '../playback/replay_gain.dart';
import '../playback/sleep_timer.dart';
import '../playback/transcode_decider.dart';

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
    await _store(credentials);
  }

  /// Replaces the connection details of the signed-in server, keeping the downloads and the library cache. The server has to answer at the address or, failing that, at the local address.
  Future<void> updateConnection(ServerCredentials credentials) async {
    final client = SubsonicClient(credentials);
    try {
      await client.ping();
    } on Exception {
      final local = credentials.localUrl;
      if (local == null || !await serverAnswers(credentials, local)) rethrow;
    } finally {
      client.close();
    }
    await _store(credentials);
  }

  Future<void> _store(ServerCredentials credentials) async {
    await secureStorage.write(
      key: _credentialsKey,
      value: jsonEncode(credentials.toJson()),
    );
    state = credentials;
  }

  Future<void> signOut() async {
    await ref.read(downloadManagerProvider)?.removeAll();
    await ref.read(artworkStoreProvider)?.clear();
    await ref.read(artworkCacheProvider).emptyCache();
    ref.invalidate(lockScreenArtProvider);
    await ref.read(prefetchCacheProvider).clear();
    await ref.read(queueStoreProvider).clear();
    await ref.read(pastQueuesProvider.notifier).clear();
    await secureStorage.delete(key: _credentialsKey);
    state = null;
  }
}

final credentialsProvider =
    NotifierProvider<CredentialsNotifier, ServerCredentials?>(
      CredentialsNotifier.new,
    );

const _addressKey = 'server.address';

/// The address the client sends requests to, the public or the local one.
class ActiveAddressNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String address) {
    state = address;
    unawaited(
      ref.read(sharedPreferencesProvider).setString(_addressKey, address),
    );
  }
}

final activeAddressProvider = NotifierProvider<ActiveAddressNotifier, String?>(
  ActiveAddressNotifier.new,
);

/// The client of the signed-in server. With a local address, it starts on the address used last and, on every change of network, uses the local address when the server answers there.
final clientProvider = Provider<SubsonicClient?>((ref) {
  final credentials = ref.watch(credentialsProvider);
  if (credentials == null) return null;
  final local = credentials.localUrl;
  final last = ref.read(sharedPreferencesProvider).getString(_addressKey);
  final client = SubsonicClient(
    credentials,
    baseUrl: local != null && last == local ? local : null,
  );
  var disposed = false;
  ref.onDispose(() {
    disposed = true;
    client.close();
  });
  unawaited(client.loadExtensions());
  Future.microtask(() {
    if (!disposed) ref.read(activeAddressProvider.notifier).set(client.baseUrl);
  });
  if (local != null) {
    var probe = 0;
    ref.listen(connectivityProvider, (_, next) async {
      final networks = next.value;
      if (networks == null) return;
      final current = ++probe;
      final address = await chooseAddress(
        credentials,
        onLocalNetwork:
            networks.contains(ConnectivityResult.wifi) ||
            networks.contains(ConnectivityResult.ethernet),
        answers: (url) => serverAnswers(credentials, url),
      );
      if (disposed || current != probe) return;
      client.baseUrl = address;
      ref.read(activeAddressProvider.notifier).set(address);
    }, fireImmediately: true);
  }
  return client;
});

/// The OpenSubsonic extensions of the server, once they have arrived. Widgets watch this instead of reading [SubsonicClient.extensions], which fills in later.
final extensionsProvider = FutureProvider<Set<String>>((ref) async {
  final client = ref.watch(clientProvider);
  return client == null ? const {} : await client.loadExtensions();
});

/// Whether the server reports the OpenSubsonic extension [name]. False until the extensions arrive.
final hasExtensionProvider = Provider.family<bool, String>(
  (ref, name) => ref.watch(extensionsProvider).value?.contains(name) ?? false,
);

/// Whether the server finds songs that sound alike, through the OpenSubsonic `sonicSimilarity` extension. Instant mix and radio need it.
final canMixProvider = Provider<bool>(
  (ref) => ref.watch(hasExtensionProvider('sonicSimilarity')),
);

/// Whether the server finds the top songs of an artist by its id, through the OpenSubsonic `topSongsByArtistId` extension.
final hasTopSongsProvider = Provider<bool>(
  (ref) => ref.watch(hasExtensionProvider('topSongsByArtistId')),
);

/// Asks the server how each song should reach this device, on servers with the OpenSubsonic `transcoding` extension. Null on other servers, which get the `format` and `maxBitRate` of the `stream` endpoint instead.
final transcodeDeciderProvider = Provider<TranscodeDecider?>((ref) {
  final client = ref.watch(clientProvider);
  if (client == null || !ref.watch(hasExtensionProvider('transcoding'))) {
    return null;
  }
  return TranscodeDecider(client);
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

/// The player shows the rating of the current track, which can be changed there.
final playerRatingProvider = NotifierProvider<BoolSettingNotifier, bool>(
  () => BoolSettingNotifier('experience.playerRating', false),
);

/// Track rows (albums, playlists, search, the queue) show the rating of the song as stars next to its title. The stars only display; the menu of the song changes them.
final trackStarsProvider = NotifierProvider<BoolSettingNotifier, bool>(
  () => BoolSettingNotifier('experience.trackStars', true),
);

/// Track rows show a heart at the right edge for songs in the library. The heart only displays; the menu of the song changes it.
final trackHeartsProvider = NotifierProvider<BoolSettingNotifier, bool>(
  () => BoolSettingNotifier('experience.trackHearts', true),
);

/// The artwork of the player is covered by the lyrics of the song. A tap on the artwork toggles it, and the choice stays for the next songs.
final lyricsShownProvider = NotifierProvider<BoolSettingNotifier, bool>(
  () => BoolSettingNotifier('player.lyricsShown', false),
);

/// Home greets the person by the time of day; otherwise its title is "Home".
final greetingProvider = NotifierProvider<BoolSettingNotifier, bool>(
  () => BoolSettingNotifier('experience.greeting', true),
);

/// Home opens with the album played last, to resume it.
final continueListeningProvider = NotifierProvider<BoolSettingNotifier, bool>(
  () => BoolSettingNotifier('experience.continueListening', true),
);

/// The running sleep timer, or null. [sleepTimerRunnerProvider] pauses playback when it ends.
class SleepTimerNotifier extends Notifier<SleepTimer?> {
  @override
  SleepTimer? build() => null;

  void set(SleepTimer? timer) => state = timer;
}

final sleepTimerProvider = NotifierProvider<SleepTimerNotifier, SleepTimer?>(
  SleepTimerNotifier.new,
);

/// When the last song of the queue plays, songs that sound like it are added, so the music does not stop. Needs the `sonicSimilarity` extension.
final endlessRadioProvider = NotifierProvider<BoolSettingNotifier, bool>(
  () => BoolSettingNotifier('playback.endlessRadio', false),
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

/// Seconds over which one song fades into the next, 0 for none. Songs of the same album never fade.
class CrossfadeNotifier extends Notifier<int> {
  static const _key = 'playback.crossfade';
  static const choices = [0, 2, 4, 6, 8, 12];

  @override
  int build() => ref.read(sharedPreferencesProvider).getInt(_key) ?? 0;

  Future<void> set(int seconds) async {
    state = seconds;
    await ref.read(sharedPreferencesProvider).setInt(_key, seconds);
  }
}

final crossfadeProvider = NotifierProvider<CrossfadeNotifier, int>(
  CrossfadeNotifier.new,
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

/// Whether the phone streams over cellular: a mobile connection without Wi-Fi or a wired one.
final onCellularProvider = Provider<bool>((ref) {
  final networks = ref.watch(connectivityProvider).value ?? const [];
  return networks.contains(ConnectivityResult.mobile) &&
      !networks.contains(ConnectivityResult.wifi) &&
      !networks.contains(ConnectivityResult.ethernet);
});

/// The streaming quality setting of the current network.
final currentQualitySettingProvider =
    Provider<NotifierProvider<StreamingQualityNotifier, DownloadQuality>>(
      (ref) => ref.watch(onCellularProvider)
          ? cellularQualityProvider
          : wifiQualityProvider,
    );

/// The streaming quality for the current network.
final streamingQualityProvider = Provider<DownloadQuality>(
  (ref) => ref.watch(ref.watch(currentQualitySettingProvider)),
);

// ------------------------------------------------------------ external items

/// Whether work the person did not start song by song (the albums of a downloaded artist, the songs fetched ahead) includes items from external providers, whose IDs start with `ext-`. Off by default: a proxy such as octo-fiesta downloads each of them in full from the provider. Changing it syncs the downloads again.
class ExternalInBackgroundNotifier extends BoolSettingNotifier {
  ExternalInBackgroundNotifier() : super('server.externalInBackground', false);

  @override
  Future<void> set(bool value) async {
    await super.set(value);
    await ref.read(downloadManagerProvider)?.syncPins();
  }
}

final externalInBackgroundProvider =
    NotifierProvider<ExternalInBackgroundNotifier, bool>(
      ExternalInBackgroundNotifier.new,
    );

/// Whether the server is the octo-fiesta proxy, which mixes items from external providers into the artists and the search results of the library.
final octoFiestaProvider = Provider<bool>(
  (ref) => reportsOctoFiesta(ref.watch(extensionsProvider).value ?? const {}),
);

/// Whether the page named by the key (an artist, a search) shows the external items after a tap on "More". On other servers every item shows.
class ExternalShownNotifier extends Notifier<bool> {
  ExternalShownNotifier(this.page);

  final String page;

  @override
  bool build() => !ref.watch(octoFiestaProvider);

  void show() => state = true;
}

final externalShownProvider = NotifierProvider.autoDispose
    .family<ExternalShownNotifier, bool, String>(ExternalShownNotifier.new);

// ------------------------------------------------------------ songs fetched ahead

class PrefetchModeNotifier extends Notifier<PrefetchMode> {
  static const _key = 'playback.prefetch';

  @override
  PrefetchMode build() =>
      PrefetchMode.values.asNameMap()[ref
          .read(sharedPreferencesProvider)
          .getString(_key)] ??
      PrefetchMode.wifi;

  Future<void> set(PrefetchMode mode) async {
    state = mode;
    await ref.read(sharedPreferencesProvider).setString(_key, mode.name);
  }
}

final prefetchModeProvider =
    NotifierProvider<PrefetchModeNotifier, PrefetchMode>(
      PrefetchModeNotifier.new,
    );

class PrefetchLimitNotifier extends Notifier<int> {
  static const _key = 'playback.prefetchLimit';

  @override
  int build() =>
      ref.read(sharedPreferencesProvider).getInt(_key) ?? prefetchLimits[1];

  Future<void> set(int bytes) async {
    state = bytes;
    await ref.read(sharedPreferencesProvider).setInt(_key, bytes);
    await ref.read(prefetchCacheProvider).evict();
  }
}

final prefetchLimitProvider = NotifierProvider<PrefetchLimitNotifier, int>(
  PrefetchLimitNotifier.new,
);

/// The songs fetched ahead of playback, in their own folder next to the downloads.
/// The IDs of the songs fetched ahead of playback, in play order, so that what belongs to them (their waveforms) loads with them.
class PrefetchedTrackIdsNotifier extends Notifier<List<String>> {
  @override
  List<String> build() => const [];

  void set(List<String> ids) {
    if (ids.length == state.length &&
        Iterable.generate(ids.length).every((i) => ids[i] == state[i])) {
      return;
    }
    state = ids;
  }
}

final prefetchedTrackIdsProvider =
    NotifierProvider<PrefetchedTrackIdsNotifier, List<String>>(
      PrefetchedTrackIdsNotifier.new,
    );

final prefetchCacheProvider = Provider<PrefetchCache>((ref) {
  final cache = PrefetchCache(
    Directory(p.join(ref.watch(supportDirectoryProvider).path, 'prefetch')),
    maxBytes: ref.read(prefetchLimitProvider),
  );
  ref.listen(prefetchLimitProvider, (_, bytes) => cache.maxBytes = bytes);
  ref.onDispose(cache.close);
  return cache;
});

/// The size of the songs fetched ahead, for the settings. Invalidated after a clear.
final prefetchSizeProvider = FutureProvider.autoDispose<int>(
  (ref) => ref.watch(prefetchCacheProvider).size(),
);

/// Deletes the songs fetched ahead, except those the queue plays from.
final clearPrefetchCacheProvider = Provider<Future<void> Function()>(
  (ref) => () async {
    final queue = ref.read(playerHandlerProvider).tracks;
    final source = SessionPlaybackSource(ref);
    await ref
        .read(prefetchCacheProvider)
        .clear(keep: {for (final t in queue) source.cacheName(t)});
    ref.invalidate(prefetchSizeProvider);
  },
);

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

/// Whether downloads wait for Wi-Fi: downloads over cellular are off and the device has no Wi-Fi or Ethernet. Unknown connectivity does not hold them.
final waitingForWifiProvider = Provider<bool>((ref) {
  if (ref.watch(downloadSettingsProvider).overCellular) return false;
  final results = ref.watch(connectivityProvider).value;
  return results != null &&
      !results.any(
        (r) => r == ConnectivityResult.wifi || r == ConnectivityResult.ethernet,
      );
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

/// The disk cache of the cover images shown in the app and on the lock screen. One for the whole run of the app, since two cache managers must not share a database; it signs each request with the credentials of the current session.
final artworkCacheProvider = Provider<CacheManager>((ref) {
  final manager = artworkCacheManager(
    () => ref.read(clientProvider)?.credentials.authParams,
  );
  ref.onDispose(manager.dispose);
  unawaited(_purgeSignedArtwork(ref.read(sharedPreferencesProvider)));
  return manager;
});

const _purgedSignedArtworkKey = 'purgedSignedArtwork';

/// Empties the default image cache once. Versions before the artwork cache stored the cover images there under URLs that held the credentials.
Future<void> _purgeSignedArtwork(SharedPreferences prefs) async {
  if (prefs.getBool(_purgedSignedArtworkKey) ?? false) return;
  try {
    await DefaultCacheManager().emptyCache();
    await prefs.setBool(_purgedSignedArtworkKey, true);
  } on Object {
    // Tried again at the next start.
  }
}

/// Lock-screen artwork of songs that are not downloaded, as files fetched into [artworkCacheProvider], by cover-art ID.
final lockScreenArtProvider = Provider<Map<String, Uri>>((ref) {
  ref.watch(clientProvider);
  return {};
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

  Future<void> set(DownloadSettings settings) async {
    state = settings;
    await settings.save(ref.read(sharedPreferencesProvider));
  }
}

final downloadSettingsProvider =
    NotifierProvider<DownloadSettingsNotifier, DownloadSettings>(
      DownloadSettingsNotifier.new,
    );

/// Saves download settings and applies them to the downloads. It is a provider of its own because [downloadManagerProvider] depends on [downloadSettingsProvider], so [DownloadSettingsNotifier] cannot read the manager.
class DownloadSettingsUpdater {
  DownloadSettingsUpdater(this._ref);

  final Ref _ref;

  Future<void> update(DownloadSettings settings) async {
    final automaticChanged =
        settings.automaticDownloads !=
        _ref.read(downloadSettingsProvider).automaticDownloads;
    await _ref.read(downloadSettingsProvider.notifier).set(settings);
    if (automaticChanged) await _ref.read(syncAutomaticDownloadsProvider)();
    await _ref.read(downloadManagerProvider)?.optimizeStorage();
  }
}

final downloadSettingsUpdaterProvider = Provider<DownloadSettingsUpdater>(
  DownloadSettingsUpdater.new,
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

  // The artwork downloads alongside the tracks rather than before them, so a slow cover holds back no track.
  Future<List<Track>> resolve(PinKind kind, String id) async {
    switch (kind) {
      case PinKind.track:
        return [await repository.track(id)];
      case PinKind.album:
        final album = await repository.album(id);
        unawaited(art(album.coverArt));
        return album.songs;
      case PinKind.playlist:
        final playlist = await repository.playlist(id);
        unawaited(art(playlist.coverArt));
        return playlist.entries;
      case PinKind.artist:
        final artist = await repository.artist(id);
        unawaited(art(artist.coverArt));
        final external = ref.read(externalInBackgroundProvider);
        final ids = [
          for (final a in forBackground(
            artist.albums,
            (a) => a.id,
            includeExternal: external,
          ))
            a.id,
        ];
        // A few albums at a time. One that fails fails the whole artist, so a sync never releases the tracks of an album it could not load.
        final albums = <Album>[];
        const parallel = 4;
        for (var i = 0; i < ids.length; i += parallel) {
          albums.addAll(
            await Future.wait(ids.skip(i).take(parallel).map(repository.album)),
          );
        }
        for (final album in albums) {
          unawaited(art(album.coverArt));
        }
        return [for (final album in albums) ...album.songs];
    }
  }

  final manager = DownloadManager(
    db: ref.watch(databaseProvider),
    backend: ref.watch(_transferBackendProvider),
    resolve: resolve,
    urlFor: (track, quality) async {
      final original = (
        url: client.downloadUri(track.id),
        extension: track.suffix,
      );
      if (quality == DownloadQuality.original) return original;
      final choice = await ref
          .read(transcodeDeciderProvider)
          ?.decide(track, quality);
      if (choice == null) {
        return (
          url: client.downloadUri(
            track.id,
            format: quality.format,
            maxBitRate: quality.maxBitRate,
          ),
          extension: quality.format ?? track.suffix,
        );
      }
      if (!choice.transcoded) return original;
      return (
        url: client.transcodeStreamUri(track.id, choice.transcodeParams!),
        extension: choice.stream?.extension ?? quality.format ?? track.suffix,
      );
    },
    settings: () => ref.read(downloadSettingsProvider),
    fetchArtwork: art,
  );
  unawaited(manager.start());
  ref.listen(
    downloadSettingsProvider.select((s) => s.simultaneous),
    (_, count) => unawaited(manager.backend.setMaxConcurrent(count)),
    fireImmediately: true,
  );
  ref.listen(
    waitingForWifiProvider,
    (_, held) => unawaited(manager.setHeld(held)),
    fireImmediately: true,
  );
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

/// The download state of an album, playlist, artist or track. Released when no widget shows it, so the items scrolled past do not keep their queries running.
final pinStateProvider = StreamProvider.autoDispose
    .family<PinState, (PinKind, String)>((ref, key) {
      final manager = ref.watch(downloadManagerProvider);
      return manager == null
          ? Stream.value(PinState.none)
          : manager.watchPin(key.$1, key.$2);
    });

/// The download of one track, released when no widget shows it.
final trackFileProvider = StreamProvider.autoDispose.family<TrackFile?, String>(
  (ref, trackId) {
    final manager = ref.watch(downloadManagerProvider);
    return manager == null ? Stream.value(null) : manager.watchTrack(trackId);
  },
);

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

  /// The answer of the server on how [track] reaches this device at the streaming quality, when one is at hand.
  StreamChoice? _choice(Track track) => ref
      .read(transcodeDeciderProvider)
      ?.cached(track.id, ref.read(streamingQualityProvider));

  @override
  Uri streamUri(Track track) {
    final client = ref.read(clientProvider)!;
    final choice = _choice(track);
    if (choice != null) {
      return choice.transcoded
          ? client.transcodeStreamUri(track.id, choice.transcodeParams!)
          : client.streamUri(track.id);
    }
    final quality = ref.read(streamingQualityProvider);
    return client.streamUri(
      track.id,
      format: quality.format,
      maxBitRate: quality.maxBitRate,
    );
  }

  @override
  Uri? streamUriFrom(Track track, Duration offset) {
    final client = ref.read(clientProvider);
    if (client == null) return null;
    // The original file is seekable, so only a transcoded stream starts again on the server.
    if (_choice(track) case final choice?) {
      return choice.transcoded
          ? client.transcodeStreamUri(
              track.id,
              choice.transcodeParams!,
              offset: offset,
            )
          : null;
    }
    final quality = ref.read(streamingQualityProvider);
    if (!client.hasTranscodeOffset ||
        (quality.format == null && quality.maxBitRate == null)) {
      return null;
    }
    return client.streamUri(
      track.id,
      format: quality.format,
      maxBitRate: quality.maxBitRate,
      offset: offset,
    );
  }

  @override
  Future<void> decide(List<Track> tracks) async {
    final decider = ref.read(transcodeDeciderProvider);
    if (decider == null || ref.read(isOfflineProvider)) return;
    final quality = ref.read(streamingQualityProvider);
    await Future.wait([for (final t in tracks) decider.decide(t, quality)]);
  }

  /// The extension of the stream of [track]: the one the server transcodes to, or else the format asked of the `stream` endpoint, or else the file itself.
  String _extension(Track track) {
    final choice = _choice(track);
    if (choice != null) {
      return choice.transcoded
          ? choice.stream?.extension ?? track.suffix
          : track.suffix;
    }
    return ref.read(streamingQualityProvider).format ?? track.suffix;
  }

  /// The file name of [track] in the cache, at the streaming quality of the current network.
  String cacheName(Track track) => PrefetchCache.fileName(
    track.id,
    ref.read(streamingQualityProvider).name,
    _extension(track),
  );

  /// Every name the file of [track] may have in the cache at the streaming quality, since the server may have chosen another format when it was fetched.
  Iterable<String> _cacheNames(Track track) {
    final quality = ref.read(streamingQualityProvider);
    return {
      _extension(track),
      quality.format ?? track.suffix,
      track.suffix,
      'opus',
      'mp3',
      'flac',
    }.map((e) => PrefetchCache.fileName(track.id, quality.name, e));
  }

  @override
  Future<String?> cachedPath(Track track) async {
    final cache = ref.read(prefetchCacheProvider);
    for (final name in _cacheNames(track)) {
      if (await cache.existing(name) case final file?) return file.path;
    }
    return null;
  }

  int _prefetchRun = 0;

  @override
  Future<void> prefetch(
    List<Track> upcoming, {
    required Set<Track> keep,
    required void Function(Track track, String path) ready,
    required void Function(Set<String> fileNames) removed,
  }) async {
    final run = ++_prefetchRun;
    final mode = ref.read(prefetchModeProvider);
    if (mode == PrefetchMode.off || ref.read(isOfflineProvider)) return;
    if (mode == PrefetchMode.wifi && ref.read(onCellularProvider)) return;
    final cache = ref.read(prefetchCacheProvider);
    final kept = {for (final t in keep) ..._cacheNames(t)};
    final external = ref.read(externalInBackgroundProvider);
    final tracks = forBackground(
      upcoming,
      (t) => t.id,
      includeExternal: external,
    ).toList();
    ref.read(prefetchedTrackIdsProvider.notifier).set([
      for (final t in tracks) t.id,
    ]);
    for (final track in tracks) {
      if (run != _prefetchRun) return;
      if (await localPath(track.id) != null) continue;
      try {
        final file = await cache.fetch(cacheName(track), streamUri(track));
        ready(track, file.path);
      } on Exception {
        // The song streams when its turn comes.
        continue;
      }
      final deleted = await cache.evict(keep: kept);
      if (deleted.isNotEmpty) removed(deleted.toSet());
    }
  }

  /// A local file only: the system media session shares the artwork URI with other apps, so a server URL with credentials never goes there.
  @override
  Uri? artUri(String? coverArt) {
    if (coverArt == null) return null;
    final local = ref.read(artworkStoreProvider)?.existing(coverArt);
    if (local != null) return local.uri;
    return ref.read(lockScreenArtProvider)[coverArt];
  }

  @override
  Future<Uri?> fetchArt(String? coverArt) async {
    if (coverArt == null) return null;
    final known = artUri(coverArt);
    if (known != null) return known;
    final client = ref.read(clientProvider);
    if (client == null || ref.read(isOfflineProvider)) return null;
    try {
      final file = await ref
          .read(artworkCacheProvider)
          .getSingleFile(
            client.unsignedCoverArtUri(coverArt, size: 800).toString(),
            key: 'art:$coverArt:800',
          );
      return ref.read(lockScreenArtProvider)[coverArt] = file.uri;
    } on Object {
      return null;
    }
  }

  @override
  double volumeFor(Track track) =>
      replayGainVolume(track, ref.read(replayGainProvider));

  @override
  Duration get crossfade =>
      // A sleep timer waiting for the end of a song holds crossfade off, so the next song does not fade in before the pause.
      ref.read(sleepTimerProvider)?.waitsForSongEnd ?? false
      ? Duration.zero
      : Duration(seconds: ref.read(crossfadeProvider));

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

/// The queues this device played before others replaced them, most recent first.
class PastQueuesNotifier extends AsyncNotifier<List<PastQueue>> {
  PastQueueStore get _store => PastQueueStore(
    File(p.join(ref.read(supportDirectoryProvider).path, 'past_queues.json')),
  );

  @override
  Future<List<PastQueue>> build() => _store.load();

  Future<void> push(PastQueue queue) async {
    state = AsyncData(await _store.push(queue));
  }

  Future<void> removeAt(int index) async {
    state = AsyncData(await _store.removeAt(index));
  }

  Future<void> clear() async {
    await _store.clear();
    state = const AsyncData([]);
  }
}

final pastQueuesProvider =
    AsyncNotifierProvider<PastQueuesNotifier, List<PastQueue>>(
      PastQueuesNotifier.new,
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
        handler.position,
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
  handler.onReplaced = (queue) =>
      ref.read(pastQueuesProvider.notifier).push(queue);
  return handler;
});
