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
import 'app/licences.dart';
import 'app/playback_providers.dart';
import 'app/providers.dart';
import 'app/provisioning.dart';
import 'data/db/database.dart';
import 'playback/player_handler.dart';

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
  registerFontLicences();

  final handler = await _initAudio();
  final (prefs, support) = await (
    SharedPreferences.getInstance(),
    getApplicationSupportDirectory(),
  ).wait;
  await provision(prefs, support);
  final (credentials, maCredentials) = await (
    loadCredentials(),
    loadMaCredentials(),
  ).wait;

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        supportDirectoryProvider.overrideWithValue(support),
        initialCredentialsProvider.overrideWithValue(credentials),
        initialMaCredentialsProvider.overrideWithValue(maCredentials),
        databaseProvider.overrideWithValue(AppDatabase()),
        playerHandlerProvider.overrideWithValue(handler),
      ],
      child: const App(),
    ),
  );
}

/// Registers the handler with the system media controls: MPRIS on Linux, the System Media Transport Controls on Windows. Platforms without audio_service support use the handler directly.
Future<PlayerHandler> _initAudio() async {
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
  try {
    return await AudioService.init(
      builder: PlayerHandler.new,
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'io.github.anatosun.puffer.playback',
        androidNotificationChannelName: 'Playback',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
      ),
    );
  } on Object {
    return PlayerHandler();
  }
}
