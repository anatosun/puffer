import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/playback_providers.dart';
import '../../app/providers.dart';
import '../../data/subsonic/models.dart';
import '../../downloads/download_manager.dart';
import 'star_button.dart';
import '../../features/collection/playlist_edit.dart';
import '../../features/now_playing/song_info.dart';
import '../messages.dart';
import 'artwork.dart';
import 'download_indicator.dart';

/// The long-press menu of a track, album, playlist or artist. "Remove Download" and "Remove from Library" are separate entries.
Future<void> showItemActions(
  BuildContext context,
  WidgetRef ref, {
  required PinKind kind,
  required String id,
  required String title,
  String? subtitle,
  String? coverArt,
  bool? starred,
  Future<List<Track>> Function()? tracks,
  Future<List<Track>> Function()? mix,
  String? albumId,
  String? artistId,
  Playlist? playlist,
  int? rating,
  void Function(int rating)? onRated,
  VoidCallback? info,
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
        final messenger = ScaffoldMessenger.of(context);
        final router = GoRouter.of(context);
        void close() => Navigator.pop(sheetContext);

        // The actions scroll when they do not fit, on short screens or with large text.
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: Artwork(
                    coverArt,
                    size: 48,
                    icon: kind == PinKind.artist ? Icons.person : Icons.album,
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
                if (mix != null && !offline)
                  ListTile(
                    leading: const Icon(Icons.radio),
                    title: Text(
                      kind == PinKind.track ? 'Instant mix' : 'Start radio',
                    ),
                    onTap: () async {
                      close();
                      await runPlayback(() async {
                        final tracks = await mix();
                        if (tracks.isEmpty) {
                          showMessage('The server found no similar songs');
                          return;
                        }
                        await handler.playTracks(tracks);
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
                    title: const Text('Rename'),
                    onTap: () {
                      close();
                      renamePlaylist(context, ref, playlist);
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
                if (albumId != null && kind != PinKind.album)
                  ListTile(
                    leading: const Icon(Icons.album_outlined),
                    title: const Text('Go to album'),
                    onTap: () {
                      close();
                      router.push('/album/$albumId');
                    },
                  ),
                if (artistId != null && kind != PinKind.artist)
                  ListTile(
                    leading: const Icon(Icons.person_outline),
                    title: const Text('Go to artist'),
                    onTap: () {
                      close();
                      router.push('/artist/$artistId');
                    },
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

Future<void> showTrackActions(
  BuildContext context,
  WidgetRef ref,
  Track track,
) => showItemActions(
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
  artistId: track.artistId,
  info: () => showSongInfo(context, track),
);

/// Keeps a rating in the JSON of a model loaded from the server, so its menu shows it next time. Models built from constant maps stay as they are.
void rememberRating(Map<String, dynamic> json, int rating) {
  try {
    json['userRating'] = rating;
  } on UnsupportedError {
    // A constant map.
  }
}

/// Sends a rating from 0 to 5 to the server and reports whether it was saved.
Future<bool> rate(WidgetRef ref, String id, int rating) async {
  try {
    await ref.read(clientProvider)!.setRating(id, rating);
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
    this.compact = false,
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

  /// Small stars with 28-pixel touch targets, for the rows of track lists.
  final bool compact;

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
    mainAxisSize: widget.dense || widget.large || widget.compact
        ? MainAxisSize.min
        : MainAxisSize.max,
    children: [
      for (var star = 1; star <= 5; star++)
        IconButton(
          tooltip: '$star stars',
          iconSize: widget.large
              ? 30
              : widget.compact
              ? 18
              : null,
          visualDensity: widget.large
              ? VisualDensity.standard
              : VisualDensity.compact,
          padding: widget.dense || widget.compact ? EdgeInsets.zero : null,
          constraints: widget.compact
              ? const BoxConstraints.tightFor(width: 26, height: 28)
              : widget.dense
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
