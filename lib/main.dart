import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'data/db/database.dart';
import 'playback/player_handler.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // just_audio has no Linux backend; media_kit (libmpv) provides one for development on the desktop.
  JustAudioMediaKit.ensureInitialized(linux: true, windows: false);

  final handler = await _initAudio();
  final results = await (
    SharedPreferences.getInstance(),
    getApplicationSupportDirectory(),
    loadCredentials(),
  ).wait;

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(results.$1),
        supportDirectoryProvider.overrideWithValue(results.$2),
        initialCredentialsProvider.overrideWithValue(results.$3),
        databaseProvider.overrideWithValue(AppDatabase()),
        playerHandlerProvider.overrideWithValue(handler),
      ],
      child: const App(),
    ),
  );
}

/// Registers the handler with the system media controls. Platforms without audio_service support use the handler directly.
Future<PlayerHandler> _initAudio() async {
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
