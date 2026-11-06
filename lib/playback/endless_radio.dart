import '../data/subsonic/models.dart';
import 'playback_controller.dart';

/// Whether [np] plays the last song of a queue that does not repeat, when endless radio adds songs.
bool atQueueEnd(NowPlaying np) {
  final index = np.index;
  return np.track != null &&
      np.repeat == Repeat.off &&
      index != null &&
      np.queue.isNotEmpty &&
      index >= np.queue.length - 1;
}

/// The first [count] songs of [mix] that are not in the queue already.
List<Track> songsToAdd(
  List<Track> mix,
  Iterable<String> queued, {
  int count = 20,
}) {
  final skip = queued.toSet();
  return mix.where((t) => skip.add(t.id)).take(count).toList();
}
