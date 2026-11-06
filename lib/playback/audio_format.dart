import '../data/subsonic/models.dart';

const _lossless = {
  'flac',
  'alac',
  'wav',
  'aiff',
  'aif',
  'ape',
  'wv',
  'dsf',
  'dff',
};

/// Where the audio of a song comes from on this device.
enum PlayingSource { stream, download, musicAssistant }

/// What this device gets of a song from [source]. [format] is the extension of the transcoded stream or of the downloaded file, null for the file as it is on the server. [maxBitRate] is the bit rate asked of the server in kbit/s, and [size] the bytes of the downloaded file.
typedef Delivery = ({
  PlayingSource source,
  String? format,
  int? maxBitRate,
  int? size,
});

/// Whether [delivery] is in another format than the file of [track] on the server.
bool isTranscoded(Track track, Delivery delivery) =>
    delivery.format != null &&
    delivery.format!.toLowerCase() != track.suffix.toLowerCase();

/// The bit rate of a transcoded [delivery] in kbit/s: the one asked of the server, or else the average over the downloaded file. Null when neither is known.
int? deliveredBitRate(Track track, Delivery delivery) {
  if (delivery.maxBitRate case final rate?) return rate;
  final size = delivery.size;
  final ms = track.duration.inMilliseconds;
  if (size == null || size <= 0 || ms <= 0) return null;
  // Bytes times 8 over milliseconds is kbit/s.
  return (size * 8 / ms).round();
}

/// The format of what plays, as the player shows it in two badges: the [codec], and the [quality] when known.
typedef PlayingFormat = ({String codec, String? quality});

/// The transcoded [format] at [maxBitRate] kbit/s when it differs from the file on the server; otherwise the file itself, with bit depth and sample rate for lossless files (`24/96`, or `44.1 kHz` without the depth) and the bit rate for lossy ones.
PlayingFormat describeFormat(Track track, {String? format, int? maxBitRate}) {
  final suffix = track.suffix.toLowerCase();
  if (format != null && format.toLowerCase() != suffix) {
    return (
      codec: format.toUpperCase(),
      quality: maxBitRate == null ? null : '$maxBitRate kbps',
    );
  }
  final codec = suffix.toUpperCase();
  final rate = track.json['samplingRate'] as int?;
  final depth = track.json['bitDepth'] as int?;
  if (_lossless.contains(suffix) && rate != null && rate > 0) {
    final khz = rate % 1000 == 0
        ? '${rate ~/ 1000}'
        : (rate / 1000).toStringAsFixed(1);
    return (
      codec: codec,
      quality: depth != null && depth > 0 ? '$depth/$khz' : '$khz kHz',
    );
  }
  final bitRate = track.bitRate;
  return (
    codec: codec,
    quality: bitRate != null && bitRate > 0 ? '$bitRate kbps' : null,
  );
}
