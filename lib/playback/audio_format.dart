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
