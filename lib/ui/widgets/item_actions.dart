import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/playback_providers.dart';
import '../../app/providers.dart';
import '../../data/subsonic/models.dart';
import '../../downloads/download_manager.dart';
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

        return SafeArea(
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
              const Divider(height: 1),
              if (mix != null && !offline)
                ListTile(
                  leading: const Icon(Icons.auto_awesome),
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
                ListTile(
                  enabled: !offline,
                  leading: Icon(
                    starred ? Icons.favorite : Icons.favorite_border,
                  ),
                  title: Text(
                    starred ? 'Remove from library' : 'Add to library',
                  ),
                  onTap: () async {
                    close();
                    try {
                      await repository.setStarred(
                        starred: !starred,
                        trackId: kind == PinKind.track ? id : null,
                        albumId: kind == PinKind.album ? id : null,
                        artistId: kind == PinKind.artist ? id : null,
                      );
                      ref.invalidate(starredProvider);
                      await ref.read(syncAutomaticDownloadsProvider)();
                    } on Exception catch (e) {
                      messenger.showSnackBar(SnackBar(content: Text('$e')));
                    }
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
  mix: () => ref.read(repositoryProvider)!.instantMix(track),
  albumId: track.albumId,
  artistId: track.artistId,
);
