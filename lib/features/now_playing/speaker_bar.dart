import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/playback_providers.dart';
import '../../app/sendspin_providers.dart';
import '../../ui/theme.dart';

/// Shown while Music Assistant plays on this phone as a speaker and the app cannot follow that player, which happens without a Music Assistant sign-in: the app then knows what plays but not the queue. Otherwise the app follows the player or group the phone plays in (followSpeakerProvider), and the mini player shows the music instead.
class SpeakerBar extends ConsumerWidget {
  const SpeakerBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(sendspinStatusProvider).value;
    if (status == null || !status.playing) return const SizedBox.shrink();
    if (ref.watch(speakerSourceProvider) != null) {
      return const SizedBox.shrink();
    }
    final title = [status.title, status.artist].nonNulls.join(' — ');
    // Without a Music Assistant player to follow, a tap opens the Music Assistant settings, where signing in makes the queue visible.
    return GestureDetector(
      onTap: () => GoRouter.of(context).push('/settings/music-assistant'),
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
