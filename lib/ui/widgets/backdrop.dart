import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/experience.dart';
import '../../app/playback_providers.dart';
import '../../app/providers.dart';
import '../../features/home/home_page.dart';
import '../theme.dart';
import 'artwork.dart';

/// The background of a page: [coverArt] blurred, else the artwork of what is playing. When nothing plays, the setting picks the accent colours blurred, the artwork of the album played last, or nothing. With artwork colours off, the plain background. The [child] is a scaffold with a transparent background.
class Backdrop extends ConsumerWidget {
  const Backdrop({
    super.key,
    this.coverArt,
    this.top = 0.35,
    required this.child,
  });

  final String? coverArt;

  /// The opacity of the background over the top of the artwork.
  final double top;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Opaque, so the page below does not show through during a route transition.
        ColoredBox(color: context.background),
        ?_blur(context, ref),
        child,
      ],
    );
  }

  Widget? _blur(BuildContext context, WidgetRef ref) {
    if (!ref.watch(artworkColoursProvider)) return null;
    final np = ref.watch(nowPlayingProvider).value;
    var art = coverArt ?? np?.coverArt;
    final idle = ref.watch(idleBackgroundProvider);
    if (art == null &&
        np == null &&
        idle == IdleBackground.lastPlayed &&
        !ref.watch(isOfflineProvider)) {
      art = ref.watch(albumListProvider('recent')).value?.firstOrNull?.coverArt;
    }
    if (artworkImage(ref, art, size: 300) case final image?) {
      return BlurredArtwork(image: image, id: art!, top: top);
    }
    // Without artwork to show, the accent colours stand in.
    if (idle == IdleBackground.none) return null;
    final colours = context.colors;
    return BlurredArtwork.colours([
      colours.primary,
      colours.tertiary,
      colours.secondaryContainer,
    ], top: top);
  }
}
