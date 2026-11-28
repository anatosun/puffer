import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_service_mpris/audio_service_mpris.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'app/car_providers.dart';
import 'app/licences.dart';
import 'app/playback_providers.dart';
import 'app/providers.dart';
import 'app/provisioning.dart';
import 'data/db/database.dart';
import 'playback/car_library.dart';
import 'playback/player_handler.dart';
import 'playback/system_media_handler.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // just_audio has no Linux or Windows backend; media_kit (libmpv) provides one. macOS uses just_audio's own.
  // Pitch control puts mpv's scaletempo filter on every song, even at normal speed, and its work grows with the square of the sample rate: a 24-bit song at 192 kHz decoded 18 times slower with it. The app never changes the speed or the pitch.
  JustAudioMediaKit.pitch = false;
  // mpv loads 32 MB of a song by default, about five minutes of a CD-quality FLAC; 256 MB holds nearly any song whole, so it plays through a lost connection.
  JustAudioMediaKit.bufferSize = 256 << 20;
  JustAudioMediaKit.ensureInitialized(linux: true, windows: true);
  // The cache goes to disk: in memory, a song would take its full size in RAM.
  if (Platform.isLinux || Platform.isWindows) {
    final cache = Directory(
      p.join((await getApplicationCacheDirectory()).path, 'mpv'),
    );
    cache.createSync(recursive: true);
    JustAudioMediaKit.cacheDir = cache.path;
  }
  // A board with little memory, such as a Raspberry Pi Zero 2 W (512 MB) or a Raspberry Pi 3 (1 GB), keeps a third of the decoded artwork Flutter keeps by default.
  if (Platform.isLinux && (_memoryBytes() ?? 1 << 40) < 1536 << 20) {
    PaintingBinding.instance.imageCache
      ..maximumSizeBytes = 32 << 20
      ..maximumSize = 300;
  }
  registerFontLicences();

  final (handler, system) = await _initAudio();
  final (prefs, support) = await (
    SharedPreferences.getInstance(),
    getApplicationSupportDirectory(),
  ).wait;
  await provision(prefs, support);
  final (credentials, maCredentials) = await (
    loadCredentials(),
    loadMaCredentials(),
  ).wait;

  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      supportDirectoryProvider.overrideWithValue(support),
      initialCredentialsProvider.overrideWithValue(credentials),
      initialMaCredentialsProvider.overrideWithValue(maCredentials),
      databaseProvider.overrideWithValue(AppDatabase()),
      playerHandlerProvider.overrideWithValue(handler),
      systemMediaHandlerProvider.overrideWithValue(system),
    ],
  );
  // Android Auto can start the app without its screen, when no widget builds; the player and what the car browses are set up here.
  container
    ..listen(playbackProvider, (_, _) {})
    ..listen(queuePersistenceProvider, (_, _) {})
    ..listen(carSessionProvider, (_, _) {});

  runApp(UncontrolledProviderScope(container: container, child: const App()));
}

/// The memory of the machine from `/proc/meminfo`, or null where the file is missing or unreadable.
int? _memoryBytes() {
  try {
    final line = File('/proc/meminfo')
        .readAsLinesSync()
        .firstWhere((l) => l.startsWith('MemTotal:'));
    final kib = int.tryParse(line.split(RegExp(r'\s+'))[1]);
    return kib == null ? null : kib * 1024;
  } on Object {
    return null;
  }
}

/// Registers the handlers with the system media controls: the Android notification and lock screen, MPRIS on Linux, the System Media Transport Controls on Windows. Platforms without audio_service support use the player directly.
Future<(PlayerHandler, SystemMediaHandler)> _initAudio() async {
  if (Platform.isLinux) {
    // The bus name is org.mpris.MediaPlayer2.puffer.instance<PID>; the Flatpak may own it.
    AudioServiceMpris.init(
      dBusName: 'puffer',
      identity: 'Puffer',
      desktopEntry: 'io.github.anatosun.puffer',
      canControl: true,
      canPlay: true,
      canPause: true,
      canGoNext: true,
      canGoPrevious: true,
    );
  }
  final local = PlayerHandler();
  final system = SystemMediaHandler(local);
  try {
    await AudioService.init(
      builder: () => system,
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'io.github.anatosun.puffer.playback',
        androidNotificationChannelName: 'Playback',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
        androidBrowsableRootExtras: carRootExtras,
      ),
    );
  } on Object {
    // Without the system media controls the app plays all the same.
  }
  return (local, system);
}
