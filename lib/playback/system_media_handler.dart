import 'dart:async';

import 'package:audio_service/audio_service.dart';

import 'player_handler.dart';
import 'playback_controller.dart';

/// What the system media controls show and drive: the Android notification and lock screen, Android Auto, MPRIS on Linux, the media controls of Windows. It shows [local], the player of this device, unless [showRemote] gives it what a Music Assistant player plays; then its buttons act on that player through [remoteControls].
///
/// The app itself calls [local] directly, never this handler, so pausing this device (as the Sendspin speaker does when it starts) never reaches a speaker.
class SystemMediaHandler extends BaseAudioHandler {
  SystemMediaHandler(this.local) {
    local.mediaItem.listen((item) {
      if (!_remote) mediaItem.add(item);
    });
    local.playbackState.listen((state) {
      if (!_remote) playbackState.add(state);
    });
    local.queue.listen((items) {
      if (!_remote) queue.add(items);
    });
  }

  final PlayerHandler local;

  /// The controller of the Music Assistant player that is the output, or null for this device. It is asked at each press, so a press right after switching back to this device reaches this device.
  PlaybackController? Function()? remoteControls;

  /// Whether the controls show a Music Assistant player.
  bool _remote = false;

  /// The song shown for the player, to fetch its artwork once.
  String? _remoteSong;

  PlaybackController? get _target => remoteControls?.call();

  /// Shows [np], what a Music Assistant player plays, or this device again when null.
  void showRemote(NowPlaying? np) {
    if (np == null) {
      if (!_remote) return;
      _remote = false;
      _remoteSong = null;
      queue.add(local.queue.value);
      mediaItem.add(local.mediaItem.value);
      playbackState.add(local.playbackState.value);
      return;
    }
    if (!_remote) queue.add(const []);
    _remote = true;
    final song = np.track?.id ?? '${np.title}\u0000${np.artist}';
    final known = local.source?.artUri(np.coverArt) ?? np.imageUrl;
    final item = MediaItem(
      id: song,
      title: np.title,
      artist: np.artist,
      album: np.album,
      duration: np.duration > Duration.zero ? np.duration : null,
      artUri: known,
    );
    if (!_sameItem(mediaItem.value, item)) mediaItem.add(item);
    if (song != _remoteSong) {
      _remoteSong = song;
      if (known == null && np.coverArt != null) {
        unawaited(_fetchArt(song, np.coverArt));
      }
    }
    final next = PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        if (np.playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {MediaAction.seek},
      androidCompactActionIndices: const [0, 1, 2],
      processingState: np.buffering
          ? AudioProcessingState.buffering
          : AudioProcessingState.ready,
      playing: np.playing,
      updatePosition: np.position,
      updateTime: np.positionAt,
    );
    // The player reports its position each second, which the controls work out by themselves.
    if (!sameState(playbackState.value, next)) playbackState.add(next);
  }

  Future<void> _fetchArt(String song, String? coverArt) async {
    final uri = await local.source?.fetchArt(coverArt);
    final item = mediaItem.value;
    if (uri == null || !_remote || song != _remoteSong || item == null) return;
    mediaItem.add(item.copyWith(artUri: uri));
  }

  static bool _sameItem(MediaItem? a, MediaItem b) =>
      a != null &&
      a.id == b.id &&
      a.title == b.title &&
      a.artist == b.artist &&
      a.album == b.album &&
      a.duration == b.duration &&
      (a.artUri == b.artUri || b.artUri == null);

  @override
  Future<void> play() => _target?.play() ?? local.play();

  @override
  Future<void> pause() => _target?.pause() ?? local.pause();

  @override
  Future<void> seek(Duration position) =>
      _target?.seek(position) ?? local.seek(position);

  @override
  Future<void> skipToNext() => _target?.next() ?? local.skipToNext();

  @override
  Future<void> skipToPrevious() =>
      _target?.previous() ?? local.skipToPrevious();

  /// Dismissing the controls of a speaker pauses it, rather than clearing the queue of this device.
  @override
  Future<void> stop() => _target?.pause() ?? local.stop();

  @override
  Future<void> skipToQueueItem(int index) =>
      _target?.skipTo(index) ?? local.skipToQueueItem(index);

  @override
  Future<void> fastForward() => local.fastForward();

  @override
  Future<void> rewind() => local.rewind();

  @override
  Future<void> seekForward(bool begin) => local.seekForward(begin);

  @override
  Future<void> seekBackward(bool begin) => local.seekBackward(begin);

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) =>
      local.setShuffleMode(shuffleMode);

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) =>
      local.setRepeatMode(repeatMode);

  // A car browses and plays on this device.
  @override
  Future<List<MediaItem>> getChildren(
    String parentMediaId, [
    Map<String, dynamic>? options,
  ]) => local.getChildren(parentMediaId, options);

  @override
  Future<List<MediaItem>> search(
    String query, [
    Map<String, dynamic>? extras,
  ]) => local.search(query, extras);

  @override
  Future<void> playFromMediaId(
    String mediaId, [
    Map<String, dynamic>? extras,
  ]) => local.playFromMediaId(mediaId, extras);

  @override
  Future<void> playFromSearch(String query, [Map<String, dynamic>? extras]) =>
      local.playFromSearch(query, extras);
}
