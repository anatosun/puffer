import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../theme.dart';

/// The image for [coverArt]: the downloaded file when there is one, otherwise the server image unless offline.
ImageProvider? artworkImage(WidgetRef ref, String? coverArt, {int size = 600}) {
  if (coverArt == null) return null;
  final local = ref.watch(artworkStoreProvider)?.existing(coverArt);
  if (local != null) return FileImage(local);
  if (ref.watch(isOfflineProvider)) return null;
  final client = ref.watch(clientProvider);
  if (client == null) return null;
  return CachedNetworkImageProvider(
    client.coverArtUri(coverArt, size: size).toString(),
    cacheKey: 'art:$coverArt:$size',
  );
}

/// Colours extracted from the artwork, for the album and now-playing backgrounds.
final artworkSchemeProvider =
    FutureProvider.family<ColorScheme?, (String, ImageProvider, Brightness)>((
      ref,
      key,
    ) async {
      try {
        return await ColorScheme.fromImageProvider(
          provider: key.$2,
          brightness: key.$3,
        );
      } on Exception {
        return null;
      }
    });

ColorScheme? artworkScheme(
  WidgetRef ref,
  String? coverArt,
  Brightness brightness,
) {
  if (!ref.watch(artworkColoursProvider)) return null;
  final image = artworkImage(ref, coverArt, size: 300);
  if (coverArt == null || image == null) return null;
  return ref.watch(artworkSchemeProvider((coverArt, image, brightness))).value;
}

/// [image] blurred to fill its parent, fading to the background towards the bottom, as in Plexamp. A change of [id] cross-fades to the new image.
class BlurredArtwork extends StatelessWidget {
  const BlurredArtwork({
    super.key,
    required this.image,
    required this.id,
    this.top = 0.25,
  });

  final ImageProvider image;
  final Object id;

  /// The opacity of the background over the top of the image.
  final double top;

  @override
  Widget build(BuildContext context) {
    final background = context.background;
    return Stack(
      fit: StackFit.expand,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 600),
          // The default layout gives the child loose constraints, which leaves the image at its own size; the backdrop fills its parent.
          layoutBuilder: (current, previous) =>
              Stack(fit: StackFit.expand, children: [...previous, ?current]),
          child: ImageFiltered(
            key: ValueKey(id),
            imageFilter: ImageFilter.blur(
              sigmaX: 60,
              sigmaY: 60,
              tileMode: TileMode.clamp,
            ),
            child: Image(
              image: image,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                background.withValues(alpha: top),
                background.withValues(alpha: 0.6),
                background,
              ],
              stops: const [0, 0.55, 1],
            ),
          ),
        ),
      ],
    );
  }
}

class Artwork extends ConsumerWidget {
  const Artwork(
    this.coverArt, {
    super.key,
    this.size,
    this.radius = 6,
    this.icon = Icons.album,
  });

  final String? coverArt;
  final double? size;
  final double radius;
  final IconData icon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final image = artworkImage(
      ref,
      coverArt,
      size: (size ?? 600) > 200 ? 800 : 300,
    );
    final placeholder = Container(
      color: context.colors.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(icon, color: context.subtle, size: (size ?? 120) * 0.4),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox.square(
        dimension: size,
        child: AspectRatio(
          aspectRatio: 1,
          child: image == null
              ? placeholder
              : Image(
                  image: image,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => placeholder,
                ),
        ),
      ),
    );
  }
}
