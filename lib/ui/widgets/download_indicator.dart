import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/db/database.dart';
import '../../downloads/download_manager.dart';
import '../theme.dart';

/// The download states shared by every item, so tracks, albums, playlists and artists use the same icons.
enum DownloadDisplay { none, queued, downloading, complete, partial }

class DownloadIcon extends StatelessWidget {
  const DownloadIcon(this.display, {super.key, this.progress, this.size = 18});

  final DownloadDisplay display;
  final double? progress;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return SizedBox.square(
      dimension: size,
      child: switch (display) {
        DownloadDisplay.none => const SizedBox.shrink(),
        DownloadDisplay.queued => Icon(
          Icons.schedule,
          size: size,
          color: context.muted,
        ),
        DownloadDisplay.downloading => CircularProgressIndicator(
          value: progress,
          strokeWidth: 2,
          color: color,
        ),
        DownloadDisplay.complete => Icon(
          Icons.arrow_circle_down,
          size: size,
          color: color,
        ),
        DownloadDisplay.partial => Icon(
          Icons.downloading,
          size: size,
          color: context.muted,
        ),
      },
    );
  }
}

DownloadDisplay displayForFile(TrackFile? file) => switch (file?.status) {
  null || FileStatus.evicted => DownloadDisplay.none,
  FileStatus.queued || FileStatus.paused => DownloadDisplay.queued,
  FileStatus.downloading => DownloadDisplay.downloading,
  FileStatus.complete => DownloadDisplay.complete,
  FileStatus.failed => DownloadDisplay.partial,
};

DownloadDisplay displayForPin(PinState state) {
  if (!state.pinned) return DownloadDisplay.none;
  if (state.isComplete) return DownloadDisplay.complete;
  if (state.isPartial) return DownloadDisplay.partial;
  return state.progress == 0
      ? DownloadDisplay.queued
      : DownloadDisplay.downloading;
}

class TrackDownloadIcon extends ConsumerWidget {
  const TrackDownloadIcon(this.trackId, {super.key, this.hideComplete = false});

  final String trackId;
  final bool hideComplete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final file = ref.watch(trackFileProvider(trackId)).value;
    final display = displayForFile(file);
    if (hideComplete && display == DownloadDisplay.complete) {
      return const SizedBox.shrink();
    }
    return DownloadIcon(display, progress: file?.progress, size: 16);
  }
}

/// The download button of an album, playlist or artist page.
class PinButton extends ConsumerWidget {
  const PinButton(this.kind, this.id, {super.key});

  final PinKind kind;
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state =
        ref.watch(pinStateProvider((kind, id))).value ?? PinState.none;
    final manager = ref.watch(downloadManagerProvider);
    final display = displayForPin(state);
    return IconButton(
      tooltip: state.pinned ? 'Remove download' : 'Download',
      iconSize: 28,
      onPressed: manager == null
          ? null
          : () async {
              HapticFeedback.mediumImpact();
              if (state.pinned) {
                final confirmed = await confirmRemoveDownload(context);
                if (confirmed) await manager.unpin(kind, id);
              } else {
                await pinWithFeedback(context, () => manager.pin(kind, id));
              }
            },
      icon: switch (display) {
        DownloadDisplay.none => const Icon(Icons.arrow_circle_down_outlined),
        DownloadDisplay.downloading ||
        DownloadDisplay.queued => SizedBox.square(
          dimension: 24,
          child: CircularProgressIndicator(
            value: state.fraction == 0 ? null : state.fraction,
            strokeWidth: 2.5,
          ),
        ),
        _ => DownloadIcon(display, size: 28),
      },
    );
  }
}

Future<bool> confirmRemoveDownload(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove download?'),
        content: const Text(
          'The music stays in your library and can be streamed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    ) ??
    false;

Future<void> pinWithFeedback(
  BuildContext context,
  Future<void> Function() pin,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await pin();
  } catch (e) {
    // Errors as well as exceptions, so a download never fails without a word.
    messenger.showSnackBar(SnackBar(content: Text('Download failed: $e')));
  }
}
