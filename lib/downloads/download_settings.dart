import 'package:shared_preferences/shared_preferences.dart';

/// Download quality: the original file, or a transcoded stream in [format] at [maxBitRate] kbit/s.
enum DownloadQuality {
  original(null, null, 'Original'),
  opus192('opus', 192, 'Opus 192 kbit/s'),
  opus128('opus', 128, 'Opus 128 kbit/s'),
  mp3320('mp3', 320, 'MP3 320 kbit/s');

  const DownloadQuality(this.format, this.maxBitRate, this.label);

  final String? format;
  final int? maxBitRate;
  final String label;
}

class DownloadSettings {
  const DownloadSettings({
    this.quality = DownloadQuality.original,
    this.overCellular = false,
    this.automaticDownloads = false,
    this.optimizeStorage = false,
    this.storageLimitBytes = 8 * 1024 * 1024 * 1024,
  });

  final DownloadQuality quality;
  final bool overCellular;
  final bool automaticDownloads;
  final bool optimizeStorage;
  final int storageLimitBytes;

  DownloadSettings copyWith({
    DownloadQuality? quality,
    bool? overCellular,
    bool? automaticDownloads,
    bool? optimizeStorage,
    int? storageLimitBytes,
  }) => DownloadSettings(
    quality: quality ?? this.quality,
    overCellular: overCellular ?? this.overCellular,
    automaticDownloads: automaticDownloads ?? this.automaticDownloads,
    optimizeStorage: optimizeStorage ?? this.optimizeStorage,
    storageLimitBytes: storageLimitBytes ?? this.storageLimitBytes,
  );

  static DownloadSettings load(SharedPreferences prefs) => DownloadSettings(
    quality:
        DownloadQuality.values.asNameMap()[prefs.getString(
          'downloads.quality',
        )] ??
        DownloadQuality.original,
    overCellular: prefs.getBool('downloads.overCellular') ?? false,
    automaticDownloads: prefs.getBool('downloads.automatic') ?? false,
    optimizeStorage: prefs.getBool('downloads.optimize') ?? false,
    storageLimitBytes:
        prefs.getInt('downloads.limit') ?? 8 * 1024 * 1024 * 1024,
  );

  Future<void> save(SharedPreferences prefs) async {
    await prefs.setString('downloads.quality', quality.name);
    await prefs.setBool('downloads.overCellular', overCellular);
    await prefs.setBool('downloads.automatic', automaticDownloads);
    await prefs.setBool('downloads.optimize', optimizeStorage);
    await prefs.setInt('downloads.limit', storageLimitBytes);
  }
}
