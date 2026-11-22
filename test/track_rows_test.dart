import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:puffer/app/playback_providers.dart';
import 'package:puffer/app/providers.dart';
import 'package:puffer/data/subsonic/models.dart';
import 'package:puffer/ui/widgets/tiles.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  /// The rows of [songs] on a phone: as on the page of an album by [albumArtist], or as in a playlist without one.
  Widget rows(List<Track> songs, {String? albumArtist}) => ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      connectivityProvider.overrideWithValue(const AsyncData([])),
      nowPlayingProvider.overrideWithValue(const AsyncData(null)),
      maClientProvider.overrideWithValue(null),
    ],
    child: MaterialApp(
      home: Material(
        child: Consumer(
          builder: (context, ref, _) {
            final album = albumArtist != null;
            return ListView(
              children: [
                for (var i = 0; i < songs.length; i++)
                  TrackTile(
                    key: ValueKey(songs[i].id),
                    tracks: songs,
                    index: i,
                    showArtwork: !album,
                    showNumber: album,
                    showArtist: !album || albumShowsArtists(albumArtist, songs),
                  ),
              ],
            );
          },
        ),
      ),
    ),
  );

  Track song(String id, String artist, {int rating = 0}) => Track({
    'id': id,
    'title': 'Song $id',
    'artist': artist,
    'duration': 200,
    'userRating': ?(rating > 0 ? rating : null),
  });

  double heightOf(WidgetTester tester, String id) =>
      tester.getSize(find.byKey(ValueKey(id))).height;

  testWidgets('in a playlist the stars sit below the artist, and every row '
      'keeps their room', (tester) async {
    await tester.pumpWidget(
      rows([song('1', 'Someone', rating: 4), song('2', 'Someone else')]),
    );
    final artist = tester.getTopLeft(find.text('Someone'));
    final stars = tester.getTopLeft(find.byType(TrackStars));
    expect(stars.dy, greaterThan(artist.dy));
    expect(stars.dx, closeTo(artist.dx, 1));
    expect(heightOf(tester, '1'), heightOf(tester, '2'));
  });

  testWidgets('a list without ratings has no line for the stars', (
    tester,
  ) async {
    await tester.pumpWidget(rows([song('1', 'Someone'), song('2', 'Other')]));
    final rated = heightOf(tester, '1');
    await tester.pumpWidget(
      rows([song('3', 'Someone', rating: 2), song('4', 'Other')]),
    );
    expect(heightOf(tester, '4'), greaterThan(rated));
  });

  testWidgets('an album hides the artist when every song is by the album '
      'artist', (tester) async {
    await tester.pumpWidget(
      rows([
        song('1', 'The band', rating: 3),
        song('2', 'The band'),
      ], albumArtist: 'The band'),
    );
    expect(find.text('The band'), findsNothing);
    // The stars go below the title, and the unrated song keeps their room.
    final title = tester.getCenter(find.text('Song 1'));
    final stars = tester.getCenter(find.byType(TrackStars));
    expect(stars.dy, greaterThan(title.dy));
    expect(heightOf(tester, '1'), heightOf(tester, '2'));
  });

  testWidgets('one song by another artist shows the artist on every row of '
      'the album', (tester) async {
    await tester.pumpWidget(
      rows([
        song('1', 'The band', rating: 5),
        song('2', 'The band feat. Guest'),
        song('3', 'The band'),
      ], albumArtist: 'The band'),
    );
    expect(find.text('The band'), findsNWidgets(2));
    expect(find.text('The band feat. Guest'), findsOneWidget);
    // The stars go below the artist, and every row has the same height.
    final artist = tester.getCenter(find.text('The band').first);
    final stars = tester.getCenter(find.byType(TrackStars));
    expect(stars.dy, greaterThan(artist.dy));
    expect(heightOf(tester, '1'), heightOf(tester, '2'));
    expect(heightOf(tester, '1'), heightOf(tester, '3'));
  });
}
