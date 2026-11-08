import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/playback_providers.dart';
import '../../app/providers.dart';
import '../../playback/sleep_timer.dart';
import '../../ui/theme.dart';

/// Opens the sleep timer: a length, the end of the song or album that plays, or off when one runs.
Future<void> showSleepTimerSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      builder: (_) => const _SleepTimerSheet(),
    );

class _SleepTimerSheet extends ConsumerWidget {
  const _SleepTimerSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sleep = ref.watch(sleepTimerProvider);
    final track = ref.watch(nowPlayingProvider.select((s) => s.value?.track));
    final timer = ref.read(sleepTimerProvider.notifier);
    void pick(SleepTimer value) {
      timer.set(value);
      Navigator.pop(context);
    }

    final status = switch (sleep?.mode) {
      null => 'Pauses playback after a while',
      SleepMode.endOfSong => 'Pauses at the end of this song',
      SleepMode.endOfAlbum => 'Pauses at the end of this album',
      SleepMode.after => () {
        ref.watch(clockProvider);
        final left = sleep!.remaining(DateTime.now())!;
        return 'Pauses in ${formatDuration(left)}';
      }(),
    };
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text(
                'Sleep timer',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                status,
                style: TextStyle(color: context.muted, fontSize: 13),
              ),
            ),
            if (sleep != null)
              ListTile(
                leading: const Icon(Icons.timer_off_outlined),
                title: const Text('Turn off'),
                onTap: () {
                  timer.set(null);
                  Navigator.pop(context);
                },
              ),
            for (final minutes in sleepTimerMinutes)
              ListTile(
                leading: const Icon(Icons.timer_outlined),
                title: Text(
                  minutes < 60
                      ? '$minutes minutes'
                      : minutes == 60
                      ? '1 hour'
                      : '${minutes ~/ 60} h ${minutes % 60} min',
                ),
                onTap: () => pick(
                  SleepTimer.after(
                    DateTime.now().add(Duration(minutes: minutes)),
                  ),
                ),
              ),
            if (track != null)
              ListTile(
                leading: const Icon(Icons.music_note_outlined),
                title: const Text('End of song'),
                onTap: () => pick(SleepTimer.endOfSong(track.id)),
              ),
            if (track?.albumId case final albumId?)
              ListTile(
                leading: const Icon(Icons.album_outlined),
                title: const Text('End of album'),
                onTap: () => pick(SleepTimer.endOfAlbum(track!.id, albumId)),
              ),
          ],
        ),
      ),
    );
  }
}
