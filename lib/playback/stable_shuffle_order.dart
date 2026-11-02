import 'package:just_audio/just_audio.dart';

/// The default shuffle order of just_audio, except that a song replaced in place (removed and inserted again at the same queue position, as when its cached file replaces its stream) keeps its place in the shuffle order. Call [replacing] before the removal.
class StableShuffleOrder extends DefaultShuffleOrder {
  StableShuffleOrder({super.random});

  int? _replacing;
  int? _slot;

  /// The next removal and insertion of [index] replace the song at that position.
  void replacing(int index) {
    _replacing = index;
    _slot = null;
  }

  @override
  void removeRange(int start, int end) {
    if (_replacing == start && end == start + 1) {
      _slot = indices.indexOf(start);
    } else {
      _replacing = null;
    }
    super.removeRange(start, end);
  }

  @override
  void insert(int index, int count) {
    final slot = _slot;
    if (_replacing != index || count != 1 || slot == null || slot < 0) {
      _replacing = null;
      _slot = null;
      return super.insert(index, count);
    }
    _replacing = null;
    _slot = null;
    for (var i = 0; i < indices.length; i++) {
      if (indices[i] >= index) indices[i] += 1;
    }
    indices.insert(slot.clamp(0, indices.length), index);
  }
}
