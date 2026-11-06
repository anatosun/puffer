import 'models.dart';

/// A format the client plays as it is: [containers] and [audioCodecs], each empty for any.
class DirectPlayProfile {
  const DirectPlayProfile({
    this.containers = const [],
    this.audioCodecs = const [],
    this.protocols = const ['http'],
  });

  final List<String> containers;
  final List<String> audioCodecs;
  final List<String> protocols;

  Json toJson() => {
    'containers': containers,
    'audioCodecs': audioCodecs,
    'protocols': protocols,
  };
}

/// A format the server may transcode to for the client.
class TranscodingProfile {
  const TranscodingProfile({
    required this.container,
    required this.audioCodec,
    this.protocol = 'http',
  });

  final String container;
  final String audioCodec;
  final String protocol;

  Json toJson() => {
    'container': container,
    'audioCodec': audioCodec,
    'protocol': protocol,
  };
}

/// The playback abilities of the client, the request body of `getTranscodeDecision` in the OpenSubsonic `transcoding` extension. Bit rates are in bit/s, 0 for no limit.
class ClientInfo {
  const ClientInfo({
    required this.name,
    required this.platform,
    this.maxAudioBitrate = 0,
    this.maxTranscodingAudioBitrate = 0,
    this.directPlayProfiles = const [],
    this.transcodingProfiles = const [],
  });

  final String name;
  final String platform;
  final int maxAudioBitrate;
  final int maxTranscodingAudioBitrate;
  final List<DirectPlayProfile> directPlayProfiles;

  /// Tried by the server in this order.
  final List<TranscodingProfile> transcodingProfiles;

  Json toJson() => {
    'name': name,
    'platform': platform,
    if (maxAudioBitrate > 0) 'maxAudioBitrate': maxAudioBitrate,
    if (maxTranscodingAudioBitrate > 0)
      'maxTranscodingAudioBitrate': maxTranscodingAudioBitrate,
    'directPlayProfiles': [for (final p in directPlayProfiles) p.toJson()],
    'transcodingProfiles': [for (final p in transcodingProfiles) p.toJson()],
  };
}

/// A stream described by `getTranscodeDecision`: the source file or the transcoded result.
class StreamDetails {
  const StreamDetails(this.json);

  final Json json;

  String get container => json['container'] as String? ?? '';
  String get codec => json['codec'] as String? ?? '';

  /// In bit/s.
  int? get audioBitrate => (json['audioBitrate'] as num?)?.toInt();
  int? get audioSamplerate => (json['audioSamplerate'] as num?)?.toInt();
  int? get audioBitdepth => (json['audioBitdepth'] as num?)?.toInt();
  int? get audioChannels => (json['audioChannels'] as num?)?.toInt();

  /// The file extension that lets the player recognise the stream: `opus` for Opus in Ogg, `m4a` for MP4 audio, the container otherwise.
  String get extension =>
      switch ((container.toLowerCase(), codec.toLowerCase())) {
        (_, 'opus') => 'opus',
        ('mp4', _) => 'm4a',
        (final c, final codec) => c.isEmpty ? codec : c,
      };
}

/// The answer of `getTranscodeDecision`: whether the client plays the file as it is, or how the server transcodes it.
class TranscodeDecision {
  const TranscodeDecision(this.json);

  final Json json;

  bool get canDirectPlay => json['canDirectPlay'] == true;
  bool get canTranscode => json['canTranscode'] == true;

  /// The value `getTranscodeStream` needs, already escaped by the server.
  String? get transcodeParams {
    final params = json['transcodeParams'] as String?;
    return params == null || params.isEmpty ? null : params;
  }

  StreamDetails? get sourceStream => switch (json['sourceStream']) {
    final Json s => StreamDetails(s),
    _ => null,
  };

  StreamDetails? get transcodeStream => switch (json['transcodeStream']) {
    final Json s => StreamDetails(s),
    _ => null,
  };
}
