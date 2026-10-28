import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/db/database.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/artwork.dart';
import '../../ui/widgets/backdrop.dart';
import 'album_lists.dart';
import 'downloaded.dart';

/// The songs in transfer, one row each with its progress, and a retry for the failed ones.
class TransfersPage extends ConsumerWidget {
  const TransfersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final waitingForWifi = ref.watch(waitingForWifiProvider);
    final manager = ref.watch(downloadManagerProvider);
    return Backdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: const Text('Downloading')),
        body: AsyncList(ref.watch(transfersProvider), (transfers) {
          final failed = transfers
              .where((t) => t.file.status == FileStatus.failed)
              .length;
          return ListView.builder(
            itemCount: transfers.length + 1,
            itemBuilder: (context, i) => i == 0
                ? _Summary(
                    count: transfers.length,
                    failed: failed,
                    onRetry: manager?.retryFailed,
                  )
                : _TransferTile(
                    transfers[i - 1],
                    waitingForWifi: waitingForWifi,
                  ),
          );
        }, empty: 'No downloads in progress'),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.count, required this.failed, this.onRetry});

  final int count;
  final int failed;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      ListTile(
        title: Text(
          count == 1 ? '1 song left' : '$count songs left',
          style: Theme.of(context).textTheme.titleLarge,
        ),
      ),
      if (failed > 0)
        ListTile(
          leading: const Icon(Icons.error_outline, color: Colors.orangeAccent),
          title: Text(
            failed == 1 ? '1 download failed' : '$failed downloads failed',
          ),
          trailing: TextButton(onPressed: onRetry, child: const Text('Retry')),
        ),
    ],
  );
}

class _TransferTile extends StatelessWidget {
  const _TransferTile(this.transfer, {required this.waitingForWifi});

  final Transfer transfer;
  final bool waitingForWifi;

  @override
  Widget build(BuildContext context) {
    final file = transfer.file;
    final track = transfer.track;
    final failed = file.status == FileStatus.failed;
    final status = transferStatus(file, waitingForWifi: waitingForWifi);
    return ListTile(
      leading: Artwork(track?.coverArt ?? file.coverArt, size: 44, radius: 4),
      title: Text(transfer.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            [?track?.artist, status].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: failed ? Colors.orangeAccent : context.muted,
            ),
          ),
          if (file.status == FileStatus.downloading)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: LinearProgressIndicator(
                value: file.progress,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
        ],
      ),
    );
  }
}
