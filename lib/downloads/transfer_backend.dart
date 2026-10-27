import 'dart:async';

import 'package:background_downloader/background_downloader.dart';

import '../data/db/database.dart';

class TransferUpdate {
  const TransferUpdate(this.id, {this.status, this.progress, this.path});

  final String id;
  final FileStatus? status;
  final double? progress;

  /// Absolute path of the file, set when [status] is [FileStatus.complete].
  final String? path;
}

/// File transfers, separated from [DownloadManager] so tests can replace them.
abstract class TransferBackend {
  Stream<TransferUpdate> get updates;
  Future<void> start();
  Future<void> enqueue({
    required String id,
    required Uri url,
    required String directory,
    required String filename,
    required bool wifiOnly,
  });
  Future<void> cancel(String id);
}

class BackgroundDownloaderBackend implements TransferBackend {
  static const _group = 'tracks';

  final _downloader = FileDownloader();
  final _updates = StreamController<TransferUpdate>.broadcast();
  StreamSubscription<TaskUpdate>? _subscription;

  @override
  Stream<TransferUpdate> get updates => _updates.stream;

  @override
  Future<void> start() async {
    _subscription ??= _downloader.updates.listen(_onUpdate);
    await _downloader.start();
  }

  Future<void> _onUpdate(TaskUpdate update) async {
    if (update.task.group != _group) return;
    final id = update.task.taskId;
    switch (update) {
      case TaskStatusUpdate(:final status, :final task):
        final mapped = switch (status) {
          TaskStatus.enqueued || TaskStatus.waitingToRetry => FileStatus.queued,
          TaskStatus.running => FileStatus.downloading,
          TaskStatus.complete => FileStatus.complete,
          TaskStatus.paused => FileStatus.paused,
          TaskStatus.canceled => null,
          TaskStatus.notFound || TaskStatus.failed => FileStatus.failed,
        };
        if (mapped == null) return;
        final path = mapped == FileStatus.complete
            ? await task.filePath()
            : null;
        _updates.add(TransferUpdate(id, status: mapped, path: path));
      case TaskProgressUpdate(:final progress):
        if (progress >= 0) _updates.add(TransferUpdate(id, progress: progress));
    }
  }

  @override
  Future<void> enqueue({
    required String id,
    required Uri url,
    required String directory,
    required String filename,
    required bool wifiOnly,
  }) async {
    await _downloader.cancelTaskWithId(id);
    await _downloader.enqueue(
      DownloadTask(
        taskId: id,
        url: url.toString(),
        filename: filename,
        directory: directory,
        baseDirectory: BaseDirectory.applicationSupport,
        group: _group,
        updates: Updates.statusAndProgress,
        requiresWiFi: wifiOnly,
        retries: 3,
        allowPause: true,
      ),
    );
  }

  @override
  Future<void> cancel(String id) async => _downloader.cancelTaskWithId(id);
}
