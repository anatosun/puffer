import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/playback_providers.dart';
import '../../app/providers.dart';
import '../../downloads/download_settings.dart';
import '../../ui/messages.dart';
import '../../ui/theme.dart';

/// Opens the streaming quality of the current network, from the format badges of the player.
Future<void> showQualitySheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      builder: (_) => const _QualitySheet(),
    );

class _QualitySheet extends ConsumerWidget {
  const _QualitySheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cellular = ref.watch(onCellularProvider);
    final quality = ref.watch(streamingQualityProvider);
    final source = ref.watch(playingSourceProvider);
    final note = switch (source) {
      PlayingSource.musicAssistant => 'Music Assistant fetches the original file from the server and converts it for each speaker itself, so this setting applies to this device only.',
      PlayingSource.download => 'This song plays from its download. The quality of downloads is under Settings, Downloads.',
      _ => 'Original plays the file as it is on the server. The others ask the server to transcode, which uses less data.',
    };
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(
              'Streaming quality on ${cellular ? 'cellular' : 'Wi-Fi'}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              note,
              style: TextStyle(color: context.muted, fontSize: 13),
            ),
          ),
          RadioGroup<DownloadQuality>(
            groupValue: quality,
            onChanged: (value) {
              if (value == null) return;
              Navigator.pop(context);
              final set = ref.read(setStreamingQualityProvider);
              runPlayback(() => set(value));
            },
            child: Column(
              children: [
                for (final q in DownloadQuality.values)
                  RadioListTile<DownloadQuality>(
                    value: q,
                    title: Text(q.label),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
