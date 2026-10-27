import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';

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
    FutureProvider.family<ColorScheme?, (String, ImageProvider)>((
      ref,
      key,
    ) async {
      try {
        return await ColorScheme.fromImageProvider(
          provider: key.$2,
          brightness: Brightness.dark,
        );
      } on Exception {
        return null;
      }
    });

ColorScheme? artworkScheme(WidgetRef ref, String? coverArt) {
  final image = artworkImage(ref, coverArt, size: 300);
  if (coverArt == null || image == null) return null;
  return ref.watch(artworkSchemeProvider((coverArt, image))).value;
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
      color: const Color(0xFF222222),
      alignment: Alignment.center,
      child: Icon(icon, color: Colors.white24, size: (size ?? 120) * 0.4),
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
