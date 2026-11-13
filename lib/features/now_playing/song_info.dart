import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/playback_providers.dart';
import '../../app/providers.dart';
import '../../data/subsonic/models.dart';
import '../../playback/audio_format.dart';
import '../../ui/theme.dart';
import 'quality_sheet.dart';

/// What the server reports about [track], as label and value, in reading order. Fields the server leaves out are skipped. With [delivery], the rows describe what this device gets: a transcoded stream or download shows its own format, bit rate and size, and the file on the server moves to an "Original" row.
List<(String, String)> songInfo(Track track, {Delivery? delivery}) {
  final j = track.json;
  String? text(String key) {
    final value = j[key];
    return value == null || '$value'.isEmpty ? null : '$value';
  }

  int? number(String key) => (j[key] as num?)?.toInt();
  String? date(String key) {
    final parsed = DateTime.tryParse(text(key) ?? '');
    if (parsed == null) return null;
    final d = parsed.toLocal();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  String? decibels(num? value) => value == null
      ? null
      : '${value >= 0 ? '+' : ''}${value.toStringAsFixed(2)} dB';

  final size = number('size');
  final rate = number('samplingRate');
  final gain = j['replayGain'] as Map<String, dynamic>?;
  final channels = number('channelCount');
  final transcoded = delivery != null && isTranscoded(track, delivery);
  final deliveredSize = delivery?.size ?? (transcoded ? null : size);
  String megabytes(int bytes) =>
      '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  final original = describeFormat(track);
  return [
    if (delivery != null)
      (
        'Source',
        switch (delivery.source) {
          PlayingSource.download => 'Downloaded file',
          PlayingSource.musicAssistant => 'Music Assistant, from the server',
          PlayingSource.stream when transcoded =>
            'Stream, transcoded by the server',
          PlayingSource.stream => 'Stream from the server',
        },
      ),
    if (transcoded) ...[
      ('Format', delivery.format!.toUpperCase()),
      if (deliveredBitRate(track, delivery) case final bitRate?)
        ('Bit rate', '$bitRate kbps'),
    ] else ...[
      ('Format', track.suffix.toUpperCase()),
      if (text('contentType') case final type?) ('Type', type),
      if (number('bitRate') case final bitRate? when bitRate > 0)
        ('Bit rate', '$bitRate kbps'),
      if (rate != null && rate > 0)
        (
          'Sample rate',
          '${(rate / 1000).toStringAsFixed(rate % 1000 == 0 ? 0 : 1)} kHz',
        ),
      if (number('bitDepth') case final depth? when depth > 0)
        ('Bit depth', '$depth-bit'),
    ],
    if (channels != null && channels > 0)
      (
        'Channels',
        switch (channels) {
          1 => 'Mono',
          2 => 'Stereo',
          _ => '$channels',
        },
      ),
    if (deliveredSize != null && deliveredSize > 0)
      ('Size', megabytes(deliveredSize)),
    if (transcoded)
      (
        'Original',
        [
          original.codec,
          ?original.quality,
          if (size != null && size > 0) megabytes(size),
        ].join(' · '),
      ),
    ('Length', formatDuration(track.duration)),
    if (decibels(gain?['trackGain'] as num?) case final g?) ('Track gain', g),
    if (decibels(gain?['albumGain'] as num?) case final g?) ('Album gain', g),
    if (text('genre') case final genre?) ('Genre', genre),
    if (track.year case final year?) ('Year', '$year'),
    if (number('playCount') case final plays?) ('Plays', '$plays'),
    if (date('played') case final played?) ('Last played', played),
    if (date('created') case final added?) ('Added', added),
    if (text('path') case final path?) ('File', path),
  ];
}

/// The details of [track] as this device gets it, with the streaming quality on top.
Future<void> showSongInfo(BuildContext context, Track track) =>
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      builder: (_) => _SongInfo(track),
    );

class _SongInfo extends ConsumerWidget {
  const _SongInfo(this.track);

  final Track track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = songInfo(
      track,
      delivery: ref.watch(deliveryProvider(track.id)),
    );
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text(
                track.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            // Offline, nothing streams.
            if (!ref.watch(isOfflineProvider)) ...[
              ListTile(
                leading: const Icon(Icons.tune),
                title: const Text('Streaming quality'),
                subtitle: Text(ref.watch(streamingQualityProvider).label),
                trailing: Icon(Icons.chevron_right, color: context.faint),
                onTap: () {
                  Navigator.pop(context);
                  showQualitySheet(context);
                },
              ),
              const Divider(height: 8),
            ],
            for (final (label, value) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 110,
                      child: Text(
                        label,
                        style: TextStyle(color: context.muted),
                      ),
                    ),
                    Expanded(child: SelectableText(value)),
                  ],
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
