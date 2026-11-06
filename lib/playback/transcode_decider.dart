import 'dart:io' show Platform;

import '../data/subsonic/models.dart';
import '../data/subsonic/subsonic_client.dart';
import '../data/subsonic/transcoding.dart';
import '../downloads/download_settings.dart';

/// The players the app runs on, which differ in the formats they play: ExoPlayer on Android, AVPlayer on Apple systems, mpv elsewhere.
enum ClientPlatform {
  android('Android'),
  apple('iOS'),
  desktop('Linux');

  const ClientPlatform(this.label);

  final String label;

  static ClientPlatform get current => Platform.isAndroid
      ? android
      : Platform.isIOS || Platform.isMacOS
      ? apple
      : desktop;

  /// The formats the player plays as they are.
  List<DirectPlayProfile> get playable => switch (this) {
    android => const [
      DirectPlayProfile(containers: ['mp3'], audioCodecs: ['mp3']),
      DirectPlayProfile(containers: ['flac'], audioCodecs: ['flac']),
      DirectPlayProfile(
        containers: ['ogg', 'opus', 'oga'],
        audioCodecs: ['opus', 'vorbis', 'flac'],
      ),
      DirectPlayProfile(
        containers: ['m4a', 'mp4', 'aac'],
        audioCodecs: ['aac', 'alac'],
      ),
      DirectPlayProfile(containers: ['wav'], audioCodecs: ['pcm']),
    ],
    // AVPlayer plays no Ogg.
    apple => const [
      DirectPlayProfile(containers: ['mp3'], audioCodecs: ['mp3']),
      DirectPlayProfile(containers: ['flac'], audioCodecs: ['flac']),
      DirectPlayProfile(
        containers: ['m4a', 'mp4', 'aac'],
        audioCodecs: ['aac', 'alac'],
      ),
      DirectPlayProfile(
        containers: ['wav', 'aiff', 'aif'],
        audioCodecs: ['pcm'],
      ),
    ],
    // mpv plays every format.
    desktop => const [DirectPlayProfile()],
  };

  bool get playsOpus => this != apple;
}

const _flac = TranscodingProfile(container: 'flac', audioCodec: 'flac');
const _mp3 = TranscodingProfile(container: 'mp3', audioCodec: 'mp3');
const _opus = TranscodingProfile(container: 'ogg', audioCodec: 'opus');

/// What the app tells the server it plays at [quality] on [platform]. At the original quality, any file the player plays comes as it is, and the others become FLAC, or MP3 when the server cannot make FLAC. At a lower quality, a file under its bit rate in a format the player plays comes as it is, so a 128 kbit/s MP3 is not transcoded again; the rest becomes the format of [quality], or MP3 where the player has no Opus.
ClientInfo clientInfoFor(DownloadQuality quality, ClientPlatform platform) {
  final bitRate = (quality.maxBitRate ?? 0) * 1000;
  final target = switch (quality.format) {
    null => const [_flac, _mp3],
    'opus' when platform.playsOpus => const [_opus],
    'opus' => const [_mp3],
    _ => const [_mp3],
  };
  return ClientInfo(
    name: clientName,
    platform: platform.label,
    maxAudioBitrate: bitRate,
    maxTranscodingAudioBitrate: bitRate,
    directPlayProfiles: platform.playable,
    transcodingProfiles: target,
  );
}

/// How this device gets a song: the file as it is on the server, or a stream the server transcodes.
class StreamChoice {
  const StreamChoice.original() : transcodeParams = null, stream = null;
  const StreamChoice.transcoded(String this.transcodeParams, this.stream);

  /// What `getTranscodeStream` needs; null for the original file.
  final String? transcodeParams;

  /// The transcoded stream, as the server describes it.
  final StreamDetails? stream;

  bool get transcoded => transcodeParams != null;
}

/// Asks the server how each song should reach this device, through the OpenSubsonic `transcoding` extension, and keeps the answers for an hour. Navidrome honours an answer for 48 hours, as long as the file does not change.
class TranscodeDecider {
  TranscodeDecider(
    this.client, {
    ClientPlatform? platform,
    DateTime Function()? now,
    this.lifetime = const Duration(hours: 1),
  }) : platform = platform ?? ClientPlatform.current,
       _now = now ?? DateTime.now;

  final SubsonicClient client;
  final ClientPlatform platform;
  final Duration lifetime;
  final DateTime Function() _now;

  final _answers = <String, ({StreamChoice choice, DateTime at})>{};
  final _asking = <String, Future<StreamChoice?>>{};

  static String _key(String trackId, DownloadQuality quality) =>
      '$trackId|${quality.name}';

  /// The answer already at hand for the song [trackId] at [quality], while it is fresh.
  StreamChoice? cached(String trackId, DownloadQuality quality) {
    final key = _key(trackId, quality);
    final answer = _answers[key];
    if (answer == null) return null;
    if (_now().difference(answer.at) < lifetime) return answer.choice;
    _answers.remove(key);
    return null;
  }

  /// How [track] reaches this device at [quality]. Null when the server gives no usable answer, and the app then falls back to the `stream` endpoint.
  Future<StreamChoice?> decide(Track track, DownloadQuality quality) async {
    if (cached(track.id, quality) case final choice?) return choice;
    final key = _key(track.id, quality);
    // The callback returns nothing: whenComplete waits for a future it returns, which here would be the request itself.
    return _asking[key] ??= _ask(track, quality).whenComplete(() {
      _asking.remove(key);
    });
  }

  Future<StreamChoice?> _ask(Track track, DownloadQuality quality) async {
    final TranscodeDecision decision;
    try {
      decision = await client.getTranscodeDecision(
        track.id,
        clientInfoFor(quality, platform),
      );
    } on Exception {
      return null;
    }
    final params = decision.transcodeParams;
    final choice = decision.canDirectPlay
        ? const StreamChoice.original()
        : decision.canTranscode && params != null
        ? StreamChoice.transcoded(params, decision.transcodeStream)
        : null;
    if (choice != null) {
      _answers[_key(track.id, quality)] = (choice: choice, at: _now());
    }
    return choice;
  }

  void clear() => _answers.clear();
}
