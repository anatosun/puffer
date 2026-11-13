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

/// Starts [mix] from a menu, where a person picked a song, album or artist rather than the song that plays: the mix replaces the queue and plays from its first song. When that song already plays, as for an instant mix of the song playing, it plays on and only the songs after it change. Returns false, and changes nothing, when the mix has no song besides [seed], the song it was made from.
Future<bool> startMix(
  PlaybackController controller,
  List<Track> mix, {
  String? seed,
}) async {
  if (!mix.any((t) => t.id != seed)) return false;
  final playing = controller.current?.track?.id;
  if (playing != null && mix.first.id == playing) {
    return playRadio(controller, mix);
  }
  await controller.playTracks(mix);
  return true;
}
