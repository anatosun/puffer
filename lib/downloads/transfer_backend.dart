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

/// File transfers, separated from [DownloadManager] so tests can replace them. They require no particular network: [DownloadManager] holds them back while only cellular is available and downloads over cellular are off, because the Wi-Fi constraint of background_downloader never let them start on some phones.
abstract class TransferBackend {
  Stream<TransferUpdate> get updates;
  Future<void> start();

  /// [expectedBytes] is the size the file should reach, for progress when the server sends no `Content-Length`, as with transcoded streams. [directory] is under the support directory of the app, or an absolute path when [absolute] is true.
  Future<void> enqueue({
    required String id,
    required Uri url,
    required String directory,
    required String filename,
    bool absolute = false,
    int? expectedBytes,
  });
  Future<void> cancel(String id);

  /// Limits the number of transfers running at the same time.
  Future<void> setMaxConcurrent(int count);
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
        // An estimated size can be too small, so the progress stops short of complete until the transfer ends.
        if (progress >= 0) {
          _updates.add(TransferUpdate(id, progress: progress.clamp(0, 0.99)));
        }
    }
  }

  @override
  Future<void> enqueue({
    required String id,
    required Uri url,
    required String directory,
    required String filename,
    bool absolute = false,
    int? expectedBytes,
  }) async {
    await _downloader.cancelTaskWithId(id);
    await _downloader.enqueue(
      DownloadTask(
        taskId: id,
        url: url.toString(),
        filename: filename,
        directory: directory,
        baseDirectory: absolute
            ? BaseDirectory.root
            : BaseDirectory.applicationSupport,
        group: _group,
        // background_downloader reports progress only for a known size. It reads this header when the response has no Content-Length.
        headers: {
          if (expectedBytes != null && expectedBytes > 0)
            'Known-Content-Length': '$expectedBytes',
        },
        updates: Updates.statusAndProgress,
        retries: 3,
        allowPause: true,
      ),
    );
  }

  @override
  Future<void> cancel(String id) async => _downloader.cancelTaskWithId(id);

  /// The holding queue of background_downloader is native, so it keeps starting transfers while the app is suspended. It is lost when the app is killed; [DownloadManager.setHeld] enqueues the queued files again at start-up.
  @override
  Future<void> setMaxConcurrent(int count) => _downloader.configure(
    globalConfig: (Config.holdingQueue, (count, null, null)),
  );
}
