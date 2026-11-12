import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/playback_providers.dart';
import '../../app/providers.dart';
import '../../data/subsonic/models.dart';
import '../../downloads/download_manager.dart';
import '../../playback/radio.dart';
import 'star_button.dart';
import '../../features/collection/playlist_edit.dart';
import '../../features/now_playing/song_info.dart';
import '../messages.dart';
import '../open_page.dart';
import 'artwork.dart';
import 'download_indicator.dart';

/// The long-press menu of a track, album, playlist or artist. "Remove Download" and "Remove from Library" are separate entries. The header shows [cover] when there is one, such as the cover of a playlist, and the artwork of [coverArt] otherwise.
Future<void> showItemActions(
  BuildContext context,
  WidgetRef ref, {
  required PinKind kind,
  required String id,
  required String title,
  String? subtitle,
  String? coverArt,
  Widget? cover,
  bool? starred,
  Future<List<Track>> Function()? tracks,
  Future<List<Track>> Function()? mix,
  String? albumId,
  List<ArtistLink> artists = const [],
  Playlist? playlist,
  int? rating,
  void Function(int rating)? onRated,
  VoidCallback? info,
  List<ItemAction> extras = const [],
}) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    builder: (sheetContext) => Consumer(
      builder: (sheetContext, ref, _) {
        final pin =
            ref.watch(pinStateProvider((kind, id))).value ?? PinState.none;
        final manager = ref.watch(downloadManagerProvider);
        final repository = ref.watch(repositoryProvider);
        final handler = ref.watch(playbackControllerProvider);
        final offline = ref.watch(isOfflineProvider);
        final canMix = ref.watch(canMixProvider);
        final messenger = ScaffoldMessenger.of(context);
        void close() => Navigator.pop(sheetContext);

        // The actions scroll when they do not fit, on short screens or with large text.
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading:
                      cover ??
                      Artwork(
                        coverArt,
                        size: 48,
                        icon: kind == PinKind.artist
                            ? Icons.person
                            : Icons.album,
                      ),
                  title: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: subtitle == null
                      ? null
                      : Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                ),
                if (rating != null && !offline)
                  Padding(
                    padding: const EdgeInsets.only(left: 8, bottom: 4),
                    child: RatingStars(
                      rating: rating,
                      onChanged: (value) async {
                        if (await rate(ref, id, value)) onRated?.call(value);
                      },
                    ),
                  ),
                const Divider(height: 1),
                if (mix != null && canMix && !offline)
                  ListTile(
                    leading: const Icon(Icons.radio),
                    title: Text(
                      kind == PinKind.track ? 'Instant mix' : 'Start radio',
                    ),
                    onTap: () async {
                      close();
                      await runPlayback(() async {
                        if (!await playRadio(handler, await mix())) {
                          showMessage('The server found no similar songs');
                        }
                      });
                    },
                  ),
                if (tracks != null) ...[
                  ListTile(
                    leading: const Icon(Icons.playlist_play),
                    title: const Text('Play next'),
                    onTap: () async {
                      close();
                      await runPlayback(
                        () async => handler.playNext(await tracks()),
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.playlist_add),
                    title: const Text('Add to queue'),
                    onTap: () async {
                      close();
                      await runPlayback(
                        () async => handler.addTracks(await tracks()),
                      );
                    },
                  ),
                ],
                if (tracks != null && !offline)
                  ListTile(
                    leading: const Icon(Icons.playlist_add_check),
                    title: const Text('Add to playlist'),
                    onTap: () {
                      close();
                      showAddToPlaylist(context, ref, tracks);
                    },
                  ),
                if (playlist != null &&
                    !offline &&
                    ownsPlaylist(ref, playlist)) ...[
                  ListTile(
                    leading: const Icon(Icons.edit_outlined),
                    title: const Text('Edit details'),
                    onTap: () {
                      close();
                      editPlaylistDetails(context, ref, playlist);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.delete_outline),
                    title: const Text('Delete playlist'),
                    onTap: () {
                      close();
                      deletePlaylist(context, ref, playlist);
                    },
                  ),
                ],
                if (manager != null)
                  pin.pinned
                      ? ListTile(
                          leading: const Icon(Icons.remove_circle_outline),
                          title: const Text('Remove download'),
                          onTap: () async {
                            close();
                            await manager.unpin(kind, id);
                          },
                        )
                      : ListTile(
                          enabled: !offline,
                          leading: const Icon(Icons.arrow_circle_down_outlined),
                          title: const Text('Download'),
                          onTap: () async {
                            close();
                            await pinWithFeedback(
                              context,
                              () => manager.pin(kind, id),
                            );
                          },
                        ),
                if (starred != null &&
                    repository != null &&
                    kind != PinKind.playlist)
                  Builder(
                    builder: (_) {
                      final target = (
                        trackId: kind == PinKind.track ? id : null,
                        albumId: kind == PinKind.album ? id : null,
                        artistId: kind == PinKind.artist ? id : null,
                      );
                      final on = isStarred(ref, target, fallback: starred);
                      return ListTile(
                        enabled: !offline,
                        leading: Icon(
                          on ? Icons.favorite : Icons.favorite_border,
                        ),
                        title: Text(
                          on ? 'Remove from library' : 'Add to library',
                        ),
                        onTap: () async {
                          // The menu closes before the server answers, so the list of starred items is refreshed through the app's container.
                          final container = ProviderScope.containerOf(
                            context,
                            listen: false,
                          );
                          final saving = saveStar(ref, target, !on);
                          close();
                          if (await saving) {
                            container.invalidate(starredProvider);
                          } else {
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text('The server refused the change'),
                              ),
                            );
                          }
                        },
                      );
                    },
                  ),
                if (info != null)
                  ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: const Text('Song info'),
                    onTap: () {
                      close();
                      info();
                    },
                  ),
                for (final extra in extras)
                  ListTile(
                    leading: Icon(extra.icon),
                    title: Text(extra.label),
                    subtitle: extra.detail == null ? null : Text(extra.detail!),
                    onTap: () {
                      close();
                      extra.onTap();
                    },
                  ),
                if (albumId != null && kind != PinKind.album)
                  ListTile(
                    leading: const Icon(Icons.album_outlined),
                    title: const Text('Go to album'),
                    onTap: () => openPage(context, '/album/$albumId'),
                  ),
                // One entry per artist the item credits, named so a song by several artists leads to each of them. The menu of an artist leads to its own page.
                for (final artist in artists)
                  ListTile(
                    leading: const Icon(Icons.person_outline),
                    title: Text(
                      artist.name.isEmpty
                          ? 'Go to artist'
                          : 'Go to ${artist.name}',
                    ),
                    onTap: () => openPage(context, '/artist/${artist.id}'),
                  ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

/// Starred items, refreshed after a person adds or removes one.
final starredProvider = FutureProvider<Starred?>((ref) async {
  final client = ref.watch(clientProvider);
  if (client == null || ref.watch(isOfflineProvider)) return null;
  return client.getStarred();
});

/// An entry a caller adds at the end of the menu, such as the player's sleep timer.
typedef ItemAction = ({
  IconData icon,
  String label,
  String? detail,
  VoidCallback onTap,
});

Future<void> showTrackActions(
  BuildContext context,
  WidgetRef ref,
  Track track, {
  List<ItemAction> extras = const [],
}) => showItemActions(
  context,
  ref,
  kind: PinKind.track,
  id: track.id,
  title: track.title,
  subtitle: [track.artist, track.album].nonNulls.join(' · '),
  coverArt: track.coverArt,
  starred: track.starred,
  tracks: () async => [track],
  rating: track.rating,
  onRated: (value) => rememberRating(track.json, value),
  mix: () => ref.read(repositoryProvider)!.instantMix(track),
  albumId: track.albumId,
  artists: track.artists,
  info: () => showSongInfo(context, track),
  extras: extras,
);

/// Keeps a rating in the JSON of a model loaded from the server, so its menu shows it next time. Models built from constant maps stay as they are.
void rememberRating(Map<String, dynamic> json, int rating) {
  try {
    json['userRating'] = rating;
  } on UnsupportedError {
    // A constant map.
  }
}

/// Ratings changed in this session, by track ID, so the stars of a row follow a change made in the menu or the player.
class RatingOverridesNotifier extends Notifier<Map<String, int>> {
  @override
  Map<String, int> build() => const {};

  void set(String id, int rating) => state = {...state, id: rating};
}

final ratingOverridesProvider =
    NotifierProvider<RatingOverridesNotifier, Map<String, int>>(
      RatingOverridesNotifier.new,
    );

/// Sends a rating from 0 to 5 to the server and reports whether it was saved.
Future<bool> rate(WidgetRef ref, String id, int rating) async {
  try {
    await ref.read(clientProvider)!.setRating(id, rating);
    ref.read(ratingOverridesProvider.notifier).set(id, rating);
    return true;
  } on Exception catch (e) {
    showMessage('$e');
    return false;
  }
}

/// Five stars; tapping the current rating clears it.
class RatingStars extends StatefulWidget {
  const RatingStars({
    super.key,
    required this.rating,
    required this.onChanged,
    this.color,
    this.alignment = MainAxisAlignment.start,
    this.dense = false,
    this.large = false,
  });

  final int rating;
  final ValueChanged<int> onChanged;

  /// The colour of the filled stars; the primary colour of the theme when null.
  final Color? color;
  final MainAxisAlignment alignment;

  /// Narrower buttons, for rows that hold more than the stars.
  final bool dense;

  /// Larger stars with full-size touch targets of 48 pixels, for the player.
  final bool large;

  @override
  State<RatingStars> createState() => _RatingStarsState();
}

class _RatingStarsState extends State<RatingStars> {
  late int _rating = widget.rating;

  @override
  void didUpdateWidget(RatingStars old) {
    super.didUpdateWidget(old);
    if (widget.rating != old.rating) _rating = widget.rating;
  }

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: widget.alignment,
    mainAxisSize: widget.dense || widget.large
        ? MainAxisSize.min
        : MainAxisSize.max,
    children: [
      for (var star = 1; star <= 5; star++)
        IconButton(
          tooltip: '$star stars',
          iconSize: widget.large ? 30 : null,
          visualDensity: widget.large
              ? VisualDensity.standard
              : VisualDensity.compact,
          padding: widget.dense ? EdgeInsets.zero : null,
          constraints: widget.dense
              ? const BoxConstraints.tightFor(width: 30, height: 40)
              : null,
          icon: Icon(
            star <= _rating ? Icons.star_rounded : Icons.star_outline_rounded,
            color: star <= _rating
                ? widget.color ?? Theme.of(context).colorScheme.primary
                : null,
          ),
          onPressed: () {
            HapticFeedback.selectionClick();
            final value = star == _rating ? 0 : star;
            setState(() => _rating = value);
            widget.onChanged(value);
          },
        ),
    ],
  );
}
