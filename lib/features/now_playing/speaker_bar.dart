import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/playback_providers.dart';
import '../../app/sendspin_providers.dart';
import '../../ui/theme.dart';
import 'now_playing.dart';

/// Shown while Music Assistant plays on this phone as a speaker and the app does not follow that player, for example without a Music Assistant sign-in. When it follows, the mini player shows the music instead.
class SpeakerBar extends ConsumerWidget {
  const SpeakerBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(sendspinStatusProvider).value;
    if (status == null || !status.playing) return const SizedBox.shrink();
    final source = ref.watch(speakerSourceProvider);
    if (source != null && ref.watch(outputProvider) == source) {
      return const SizedBox.shrink();
    }
    final title = [status.title, status.artist].nonNulls.join(' — ');
    // A tap opens the player on what plays here; without a Music Assistant player to follow, it opens the Music Assistant settings, where signing in makes the queue visible.
    void open() {
      if (source != null) {
        ref.read(outputProvider.notifier).select(source);
        openNowPlaying(context);
      } else {
        GoRouter.of(context).push('/settings/music-assistant');
      }
    }

    return GestureDetector(
      onTap: open,
      child: Container(
        margin: const EdgeInsets.fromLTRB(8, 0, 8, 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: context.colors.secondaryContainer,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(
              Icons.speaker_group,
              color: context.colors.onSecondaryContainer,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title.isEmpty ? 'Playing on this phone' : title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: context.colors.onSecondaryContainer,
                    ),
                  ),
                  Text(
                    'From ${status.serverName ?? 'Music Assistant'}${status.groupName == null ? '' : ' · ${status.groupName}'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: context.colors.onSecondaryContainer.withValues(
                        alpha: 0.8,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.keyboard_arrow_up,
              color: context.colors.onSecondaryContainer,
            ),
          ],
        ),
      ),
    );
  }
}
