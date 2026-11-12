import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:puffer/playback/player_handler.dart';

void main() {
  final playing = PlaybackState(
    processingState: AudioProcessingState.ready,
    playing: true,
    updatePosition: const Duration(seconds: 10),
    updateTime: DateTime.now().subtract(const Duration(seconds: 1)),
  );

  test(
    'the media controls hear nothing when only more of the song has loaded',
    () {
      final next = playing.copyWith(
        updatePosition: const Duration(seconds: 11),
        bufferedPosition: const Duration(seconds: 40),
      );
      expect(sameState(playing, next), isTrue);
    },
  );

  test(
    'the media controls hear of a seek, a pause, another song and buffering',
    () {
      expect(
        sameState(
          playing,
          playing.copyWith(updatePosition: const Duration(seconds: 30)),
        ),
        isFalse,
      );
      expect(
        sameState(
          playing,
          playing.copyWith(
            playing: false,
            updatePosition: const Duration(seconds: 11),
          ),
        ),
        isFalse,
      );
      expect(
        sameState(
          playing,
          playing.copyWith(
            queueIndex: 1,
            updatePosition: const Duration(seconds: 11),
          ),
        ),
        isFalse,
      );
      expect(
        sameState(
          playing,
          playing.copyWith(
            processingState: AudioProcessingState.buffering,
            updatePosition: const Duration(seconds: 11),
          ),
        ),
        isFalse,
      );
    },
  );
}
