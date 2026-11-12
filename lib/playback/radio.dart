import '../data/subsonic/models.dart';
import 'playback_controller.dart';

/// Plays [mix] after the song that plays, which plays on: the songs queued after it make way, and the mix plays in its order, without shuffle. With nothing loaded, the mix plays from its first song. Returns false, and changes nothing, when the mix has no song besides the one that plays.
Future<bool> playRadio(PlaybackController controller, List<Track> mix) async {
  final np = controller.current;
  if (np == null) {
    if (mix.isEmpty) return false;
    await controller.playTracks(mix);
    return true;
  }
  final playing = np.track?.id;
  final rest = [
    for (final t in mix)
      if (t.id != playing) t,
  ];
  if (rest.isEmpty) return false;
  if (np.shuffle) await controller.setShuffle(false);
  await controller.replaceUpcoming(rest);
  return true;
}
