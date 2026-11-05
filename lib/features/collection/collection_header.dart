import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/subsonic/models.dart';
import '../../downloads/download_manager.dart';
import '../../ui/widgets/artwork.dart';
import '../../ui/widgets/download_indicator.dart';
import '../../ui/widgets/tiles.dart';
import '../../ui/theme.dart';

/// The page of an album, playlist or artist. The artwork sits in a top bar that stretches when pulled down and collapses to the title when scrolled; below it come the title, the play, shuffle and download buttons, and [slivers].
class CollectionView extends ConsumerWidget {
  const CollectionView({
    super.key,
    required this.coverArt,
    this.image,
    required this.title,
    this.subtitle,
    this.onSubtitleTap,
    this.details,
    required this.tracks,
    required this.pinKind,
    required this.pinId,
    this.circular = false,
    this.trailing,
    this.actions,
    required this.slivers,
  });

  final String? coverArt;

  /// An image shown in place of [coverArt], such as the photo of an artist.
  final ImageProvider? image;
  final String title;
  final String? subtitle;
  final VoidCallback? onSubtitleTap;
  final String? details;
  final List<Track> tracks;
  final PinKind pinKind;
  final String pinId;
  final bool circular;
  final Widget? trailing;
  final List<Widget>? actions;
  final List<Widget> slivers;

  /// The playlist this view shows, which counts as played when played from here.
  String? get _playlistId => pinKind == PinKind.playlist ? pinId : null;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = artworkScheme(ref, coverArt, Theme.of(context).brightness);
    final tint = Color.alphaBlend(
      (scheme?.primaryContainer ?? context.colors.surfaceContainerHighest)
          .withValues(alpha: 0.85),
      context.background,
    );
    // With artwork colours, the blurred artwork behind the page shows through the open header.
    final blurred = scheme != null;
    final size = (MediaQuery.sizeOf(context).width * 0.62).clamp(160.0, 320.0);
    final top = MediaQuery.paddingOf(context).top;
    final expanded = size + 32;
    final textTheme = Theme.of(context).textTheme;

    Widget artwork(double side) {
      final picture = image == null
          ? Artwork(
              coverArt,
              size: side,
              radius: circular ? 0 : 8,
              icon: circular ? Icons.person : Icons.album,
            )
          : Image(
              image: image!,
              width: side,
              height: side,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) =>
                  Artwork(coverArt, size: side, radius: 0),
            );
      if (circular) return ClipOval(child: picture);
      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(
                alpha: Theme.of(context).brightness == Brightness.dark
                    ? 0.35
                    : 0.15,
              ),
              blurRadius: 24,
              spreadRadius: -4,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: image == null
            ? picture
            : ClipRRect(borderRadius: BorderRadius.circular(8), child: picture),
      );
    }

    return CustomScrollView(
      // Bouncing lets the header stretch on every platform.
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      slivers: [
        SliverAppBar(
          pinned: true,
          stretch: true,
          expandedHeight: expanded,
          backgroundColor: blurred ? Colors.transparent : tint,
          surfaceTintColor: Colors.transparent,
          actions: actions,
          flexibleSpace: LayoutBuilder(
            builder: (context, constraints) {
              final collapsedHeight = kToolbarHeight + top;
              // 1 when fully open, 0 when collapsed, above 1 while stretched.
              final openness =
                  (constraints.maxHeight - collapsedHeight) /
                  (expanded + top - collapsedHeight);
              return Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(
                    color: blurred
                        ? tint.withValues(alpha: 1 - openness.clamp(0.0, 1.0))
                        : tint,
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 8,
                    child: Opacity(
                      opacity: openness.clamp(0.0, 1.0),
                      child: Center(
                        child: artwork(
                          (size * openness).clamp(1.0, size * 1.5),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: top,
                    left: 56,
                    right: 56,
                    height: kToolbarHeight,
                    child: Opacity(
                      opacity: (1 - openness * 3).clamp(0.0, 1.0),
                      child: Center(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.titleMedium,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        SliverToBoxAdapter(
          child: Container(
            decoration: blurred
                ? null
                : BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [tint, context.background],
                    ),
                  ),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: Column(
              children: [
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
                          color: scheme?.primary ?? context.colors.primary,
                        ),
                      ),
                    ),
                  ),
                if (details != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      details!,
                      style: TextStyle(color: context.muted),
                    ),
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
                          : () => playFrom(
                              ref,
                              tracks,
                              0,
                              shuffle: true,
                              playlistId: _playlistId,
                            ),
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
                          : () => playFrom(
                              ref,
                              tracks,
                              0,
                              playlistId: _playlistId,
                            ),
                      icon: const Icon(Icons.play_arrow_rounded),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        ...slivers,
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }
}

/// The page while its content loads or fails to load.
class CollectionPlaceholder extends StatelessWidget {
  const CollectionPlaceholder({super.key, required this.body});

  final Widget body;

  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(), body: body);
}

/// A heart button for tracks, albums and artists. Adding to the library also pins the item when automatic downloads are on.
class StarButton extends ConsumerStatefulWidget {
  const StarButton({
    super.key,
    required this.starred,
    this.trackId,
    this.albumId,
    this.artistId,
    this.json,
    this.color,
    this.offColor,
    this.dense = false,
    this.compact = false,
  });

  final bool starred;
  final String? trackId;
  final String? albumId;
  final String? artistId;

  /// The JSON of the item, updated once the server accepts the change, so the item shows the new state until it reloads.
  final Map<String, dynamic>? json;

  /// The colour of the filled heart.
  final Color? color;

  /// The colour of the empty heart; the theme's icon colour when null.
  final Color? offColor;

  /// A narrower button, for rows that hold more than the heart.
  final bool dense;

  /// A small button, for the rows of track lists.
  final bool compact;

  @override
  ConsumerState<StarButton> createState() => _StarButtonState();
}

class _StarButtonState extends ConsumerState<StarButton> {
  StarTarget get _target => (
    trackId: widget.trackId,
    albumId: widget.albumId,
    artistId: widget.artistId,
  );

  @override
  Widget build(BuildContext context) {
    final offline = ref.watch(isOfflineProvider);
    final starred = isStarred(ref, _target, fallback: widget.starred);
    return IconButton(
      iconSize: widget.compact
          ? 18
          : widget.dense
          ? 24
          : 26,
      style: widget.dense || widget.compact
          ? IconButton.styleFrom(
              minimumSize: Size(28, widget.compact ? 28 : 40),
              fixedSize: Size(28, widget.compact ? 28 : 40),
              padding: EdgeInsets.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            )
          : null,
      tooltip: starred ? 'Remove from library' : 'Add to library',
      onPressed: offline
          ? null
          : () => saveStar(ref, _target, !starred, json: widget.json),
      icon: Icon(
        starred ? Icons.favorite : Icons.favorite_border,
        color: starred ? widget.color : widget.offColor,
      ),
    );
  }
}

/// The item a heart belongs to: exactly one of the ids is set.
typedef StarTarget = ({String? trackId, String? albumId, String? artistId});

String _starKey(StarTarget t) => t.trackId != null
    ? 'track:${t.trackId}'
    : t.albumId != null
    ? 'album:${t.albumId}'
    : 'artist:${t.artistId}';

/// Hearts changed in this session, by item, so every heart of an item shows the same state: the button, a double tap on the artwork, and the item when it shows again.
class StarOverridesNotifier extends Notifier<Map<String, bool>> {
  @override
  Map<String, bool> build() => const {};

  void set(String key, bool starred) => state = {...state, key: starred};
}

final starOverridesProvider =
    NotifierProvider<StarOverridesNotifier, Map<String, bool>>(
      StarOverridesNotifier.new,
    );

/// Whether [target] has a heart: the change made in this session, else [fallback] from the server.
bool isStarred(WidgetRef ref, StarTarget target, {required bool fallback}) =>
    ref.watch(starOverridesProvider)[_starKey(target)] ?? fallback;

/// Adds [target] to the library or removes it. The heart changes at once and goes back when the server refuses. Adding also pins the item when automatic downloads are on.
Future<bool> saveStar(
  WidgetRef ref,
  StarTarget target,
  bool starred, {
  Map<String, dynamic>? json,
}) async {
  // Everything is read before the first wait, since the widget behind [ref] may close meanwhile, as a menu does.
  final key = _starKey(target);
  final overrides = ref.read(starOverridesProvider.notifier);
  final repository = ref.read(repositoryProvider);
  final sync = ref.read(syncAutomaticDownloadsProvider);
  if (repository == null) return false;
  overrides.set(key, starred);
  try {
    await repository.setStarred(
      starred: starred,
      trackId: target.trackId,
      albumId: target.albumId,
      artistId: target.artistId,
    );
    rememberStar(json, starred);
    await sync();
    return true;
  } on Exception {
    overrides.set(key, !starred);
    return false;
  }
}

/// Records a heart in the JSON of an item, which may be a constant map.
void rememberStar(Map<String, dynamic>? json, bool starred) {
  if (json == null) return;
  try {
    if (starred) {
      json['starred'] = DateTime.now().toUtc().toIso8601String();
    } else {
      json.remove('starred');
    }
  } on UnsupportedError {
    // A constant map.
  }
}
