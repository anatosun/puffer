import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';

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
      iconSize: widget.dense ? 24 : 26,
      style: widget.dense
          ? IconButton.styleFrom(
              minimumSize: const Size(28, 40),
              fixedSize: const Size(28, 40),
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
