import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/subsonic/models.dart';
import '../../downloads/download_manager.dart';
import '../../ui/widgets/artwork.dart';
import '../../ui/widgets/download_indicator.dart';
import '../../ui/widgets/tiles.dart';
import '../../ui/theme.dart';

/// The header of album, playlist and artist pages: artwork over a gradient of its colours, the title, and the play, shuffle and download buttons.
class CollectionHeader extends ConsumerWidget {
  const CollectionHeader({
    super.key,
    required this.coverArt,
    required this.title,
    this.subtitle,
    this.onSubtitleTap,
    this.details,
    required this.tracks,
    required this.pinKind,
    required this.pinId,
    this.circular = false,
    this.trailing,
  });

  final String? coverArt;
  final String title;
  final String? subtitle;
  final VoidCallback? onSubtitleTap;
  final String? details;
  final List<Track> tracks;
  final PinKind pinKind;
  final String pinId;
  final bool circular;
  final Widget? trailing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = artworkScheme(ref, coverArt, Theme.of(context).brightness);
    final tint =
        scheme?.primaryContainer ?? context.colors.surfaceContainerHighest;
    final size = (MediaQuery.sizeOf(context).width * 0.62).clamp(160.0, 320.0);
    final textTheme = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [tint.withValues(alpha: 0.85), context.background],
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        MediaQuery.paddingOf(context).top + kToolbarHeight,
        20,
        8,
      ),
      child: Column(
        children: [
          circular
              ? ClipOval(
                  child: Artwork(
                    coverArt,
                    size: size,
                    radius: 0,
                    icon: Icons.person,
                  ),
                )
              : DecoratedBox(
                  decoration: BoxDecoration(
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: 30,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Artwork(coverArt, size: size, radius: 8),
                ),
          const SizedBox(height: 20),
          Text(
            title,
            textAlign: TextAlign.center,
            style: textTheme.headlineMedium,
          ),
          if (subtitle != null)
            GestureDetector(
              onTap: onSubtitleTap,
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  subtitle!,
                  style: textTheme.titleMedium?.copyWith(
                    color:
                        scheme?.primary ??
                        Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ),
          if (details != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(details!, style: TextStyle(color: context.muted)),
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              PinButton(pinKind, pinId),
              ?trailing,
              const Spacer(),
              IconButton.filledTonal(
                iconSize: 26,
                tooltip: 'Shuffle',
                onPressed: tracks.isEmpty
                    ? null
                    : () => playFrom(ref, tracks, 0, shuffle: true),
                icon: const Icon(Icons.shuffle),
              ),
              const SizedBox(width: 12),
              IconButton.filled(
                iconSize: 34,
                tooltip: 'Play',
                style: IconButton.styleFrom(
                  backgroundColor: scheme?.primary,
                  foregroundColor: scheme?.onPrimary,
                ),
                onPressed: tracks.isEmpty
                    ? null
                    : () => playFrom(ref, tracks, 0),
                icon: const Icon(Icons.play_arrow_rounded),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A star button for albums and artists. Adding to the library also pins the item when automatic downloads are on.
class StarButton extends ConsumerStatefulWidget {
  const StarButton({
    super.key,
    required this.starred,
    this.albumId,
    this.artistId,
  });

  final bool starred;
  final String? albumId;
  final String? artistId;

  @override
  ConsumerState<StarButton> createState() => _StarButtonState();
}

class _StarButtonState extends ConsumerState<StarButton> {
  late bool _starred = widget.starred;

  @override
  Widget build(BuildContext context) {
    final offline = ref.watch(isOfflineProvider);
    return IconButton(
      iconSize: 26,
      tooltip: _starred ? 'Remove from library' : 'Add to library',
      onPressed: offline
          ? null
          : () async {
              final value = !_starred;
              setState(() => _starred = value);
              try {
                await ref
                    .read(repositoryProvider)!
                    .setStarred(
                      starred: value,
                      albumId: widget.albumId,
                      artistId: widget.artistId,
                    );
                await ref.read(syncAutomaticDownloadsProvider)();
              } on Exception {
                if (mounted) setState(() => _starred = !value);
              }
            },
      icon: Icon(_starred ? Icons.favorite : Icons.favorite_border),
    );
  }
}

class TransparentAppBarScaffold extends StatelessWidget {
  const TransparentAppBarScaffold({
    super.key,
    required this.body,
    this.actions,
  });

  final Widget body;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) => Scaffold(
    extendBodyBehindAppBar: true,
    appBar: AppBar(backgroundColor: Colors.transparent, actions: actions),
    body: body,
  );
}
