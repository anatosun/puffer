import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:puffer/data/subsonic/models.dart';
import 'package:puffer/playback/endless_radio.dart';
import 'package:puffer/playback/past_queues.dart';
import 'package:puffer/playback/playback_controller.dart';
import 'package:puffer/playback/sleep_timer.dart';

Track song(String id, {String? album, String? artist}) => Track({
  'id': id,
  'title': 'Song $id',
  'album': ?album,
  'albumId': ?(album == null ? null : 'al-$album'),
  'artist': ?artist,
});

NowPlaying playing(int index, int length, {Repeat repeat = Repeat.off}) =>
    NowPlaying(
      track: song('$index'),
      title: 'Song $index',
      positionAt: DateTime(2026),
      repeat: repeat,
      index: index,
      queue: [
        for (var i = 0; i < length; i++) QueueEntry(id: '$i', title: '$i'),
      ],
    );

void main() {
  group('past queues', () {
    late Directory dir;
    late PastQueueStore store;
    PastQueue queue(List<Track> tracks, {int index = 0}) =>
        PastQueue(tracks, index, const Duration(seconds: 30), DateTime(2026));

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('past_queues');
      store = PastQueueStore(File('${dir.path}/past.json'));
    });
    tearDown(() => dir.delete(recursive: true));

    test('a queue is named after its album, its artist, or its first song', () {
      expect(
        queue([
          song('1', album: 'Kind of Blue'),
          song('2', album: 'Kind of Blue'),
        ]).label,
        'Kind of Blue',
      );
      expect(
        queue([
          song('1', album: 'A', artist: 'Miles'),
          song('2', album: 'B', artist: 'Miles'),
        ]).label,
        'Miles',
      );
      expect(
        queue([song('1', artist: 'Miles'), song('2', artist: 'Bill')]).label,
        'Song 1 and 1 more',
      );
      expect(queue([song('1')]).label, 'Song 1');
    });

    test(
      'the latest five are kept, newest first, and survive a restart',
      () async {
        for (var i = 0; i < PastQueueStore.limit + 2; i++) {
          await store.push(queue([song('$i')]));
        }
        final restarted = await PastQueueStore(store.file).load();
        expect(restarted, hasLength(PastQueueStore.limit));
        expect(restarted.first.tracks.single.id, '${PastQueueStore.limit + 1}');
        expect(restarted.first.position, const Duration(seconds: 30));
      },
    );

    test('the same songs again replace the earlier entry, and playing one removes it', () async {
      await store.push(queue([song('a'), song('b')]));
      await store.push(queue([song('c')]));
      final queues = await store.push(queue([song('a'), song('b')], index: 1));
      expect(queues.map((q) => q.tracks.first.id), ['a', 'c']);
      expect(queues.first.index, 1);
      expect((await store.removeAt(0)).map((q) => q.tracks.first.id), ['c']);
    });
  });

  group('endless radio', () {
    test(
      'adds songs only at the last song of a queue that does not repeat',
      () {
        expect(atQueueEnd(playing(4, 5)), isTrue);
        expect(atQueueEnd(playing(3, 5)), isFalse);
        expect(atQueueEnd(playing(4, 5, repeat: Repeat.all)), isFalse);
        expect(atQueueEnd(playing(4, 5, repeat: Repeat.one)), isFalse);
      },
    );

    test('leaves out the songs already queued and repeats none', () {
      final mix = [song('seed'), song('a'), song('b'), song('a'), song('c')];
      expect(songsToAdd(mix, ['seed', 'b'], count: 5).map((t) => t.id), [
        'a',
        'c',
      ]);
      expect(songsToAdd(mix, const [], count: 2).map((t) => t.id), [
        'seed',
        'a',
      ]);
    });
  });

  group('sleep timer', () {
    test('the end of a song comes with any other song', () {
      const timer = SleepTimer.endOfSong('1');
      expect(timer.endsWith(song('1')), isFalse);
      expect(timer.endsWith(song('2')), isTrue);
      expect(timer.endsWith(null), isFalse);
      expect(timer.waitsForSongEnd, isTrue);
    });

    test('the end of an album comes with a song of another album', () {
      const timer = SleepTimer.endOfAlbum('1', 'al-A');
      expect(timer.endsWith(song('2', album: 'A')), isFalse);
      expect(timer.endsWith(song('3', album: 'B')), isTrue);
    });

    test('a timer after a while counts down and never fades songs early', () {
      final start = DateTime(2026, 11, 6, 23);
      final timer = SleepTimer.after(start.add(const Duration(minutes: 30)));
      expect(
        timer.remaining(start.add(const Duration(minutes: 10))),
        const Duration(minutes: 20),
      );
      expect(
        timer.remaining(start.add(const Duration(hours: 1))),
        Duration.zero,
      );
      expect(timer.endsWith(song('9')), isFalse);
      expect(timer.waitsForSongEnd, isFalse);
    });
  });
}
