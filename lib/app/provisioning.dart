import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/secret_store.dart';
import '../data/music_assistant/ma_client.dart';
import '../data/subsonic/subsonic_client.dart';
import 'playback_providers.dart';
import 'providers.dart';

/// The environment variable that names the provisioning file of a kiosk.
const provisioningVariable = 'PUFFER_CONFIG';

/// Whether the app runs as a kiosk, started with a provisioning file.
bool get isKiosk =>
    Platform.environment[provisioningVariable]?.isNotEmpty ?? false;

/// The servers, secrets and settings of a kiosk, read from one JSON file at every start, so the file stays the source of truth. See `distribution/kiosk/puffer.json.example`.
class Provisioning {
  const Provisioning({
    this.server,
    this.musicAssistant,
    this.settings = const {},
  });

  /// Parses the file; a missing section stays as the app has it.
  factory Provisioning.parse(String source) {
    final json = jsonDecode(source) as Map<String, dynamic>;
    final subsonic = json['subsonic'] as Map<String, dynamic>?;
    final ma = json['musicAssistant'] as Map<String, dynamic>?;
    return Provisioning(
      server: subsonic == null ? null : _server(subsonic),
      musicAssistant: ma == null ? null : _musicAssistant(ma),
      settings: (json['settings'] as Map<String, dynamic>?) ?? const {},
    );
  }

  final ServerCredentials? server;
  final MaCredentials? musicAssistant;

  /// Values for the preferences of the app, by key, such as `sendspin.enabled` or `ma.stayOnSpeaker`.
  final Map<String, dynamic> settings;

  /// A URL without http or https leaves Music Assistant as the app has it, so the kiosk still starts; the reason goes to the log.
  static MaCredentials? _musicAssistant(Map<String, dynamic> json) {
    try {
      return MaCredentials(
        baseUrl: normaliseMaUrl(json['url'] as String),
        token: (json['token'] as String).trim(),
      );
    } on FormatException catch (e) {
      stderr.writeln('$provisioningVariable: musicAssistant.url: ${e.message}');
      return null;
    }
  }

  static ServerCredentials _server(Map<String, dynamic> json) {
    final url = json['url'] as String;
    final username = json['username'] as String? ?? '';
    final localUrl = json['localUrl'] as String?;
    final apiKey = json['apiKey'] as String?;
    final base = apiKey != null
        ? ServerCredentials(
            baseUrl: normaliseBaseUrl(url),
            username: username,
            apiKey: apiKey,
          )
        : ServerCredentials.fromPassword(
            baseUrl: url,
            username: username,
            password: json['password'] as String,
          );
    return ServerCredentials(
      baseUrl: base.baseUrl,
      username: base.username,
      token: base.token,
      salt: base.salt,
      apiKey: base.apiKey,
      localUrl: localUrl == null ? null : normaliseBaseUrl(localUrl),
    );
  }

  /// Writes the credentials to [secrets] and the settings to [prefs], where the app reads them at start-up.
  Future<void> apply(SecretStore secrets, SharedPreferences prefs) async {
    if (server case final server?) {
      await secrets.write(key: credentialsKey, value: jsonEncode(server));
    }
    if (musicAssistant case final ma?) {
      await secrets.write(key: maCredentialsKey, value: jsonEncode(ma));
    }
    for (final MapEntry(:key, :value) in settings.entries) {
      await switch (value) {
        bool v => prefs.setBool(key, v),
        int v => prefs.setInt(key, v),
        double v => prefs.setDouble(key, v),
        String v => prefs.setString(key, v),
        List<dynamic> v => prefs.setStringList(key, v.cast<String>()),
        _ => throw FormatException('Unsupported value for setting $key'),
      };
    }
  }
}

/// Reads the provisioning file that [provisioningVariable] names, if any, and makes the app keep its secrets in a file next to its data, since a kiosk has no keychain to unlock. A file that cannot be read stops the start-up with the reason, which a kiosk shows in its log.
Future<void> provision(SharedPreferences prefs, Directory support) async {
  final path = Platform.environment[provisioningVariable];
  if (path == null || path.isEmpty) return;
  final file = File(path);
  secureStorage = FileSecretStore(File('${support.path}/secrets.json'));
  if (!file.existsSync()) return;
  final provisioning = Provisioning.parse(await file.readAsString());
  await provisioning.apply(secureStorage, prefs);
}
