import 'package:flutter_test/flutter_test.dart';
import 'package:puffer/data/db/database.dart';
import 'package:puffer/features/library/downloaded.dart';

TrackFile file(FileStatus status, {double progress = 0}) => TrackFile(
  trackId: 't',
  status: status,
  progress: progress,
  createdAt: DateTime(2026),
);

void main() {
  test('a downloading file shows its progress', () {
    expect(
      transferStatus(file(FileStatus.downloading, progress: 0.42)),
      '42 %',
    );
  });

  test('a queued file waits, for Wi-Fi when it may not use cellular', () {
    expect(transferStatus(file(FileStatus.queued)), 'Waiting');
    expect(
      transferStatus(file(FileStatus.queued), waitingForWifi: true),
      'Waiting for Wi-Fi',
    );
  });

  test('paused and failed files say so', () {
    expect(transferStatus(file(FileStatus.paused)), 'Paused');
    expect(transferStatus(file(FileStatus.failed)), 'Failed');
  });
}
