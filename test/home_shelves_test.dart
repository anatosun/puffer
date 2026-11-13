import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:flutter_test/flutter_test.dart';
import 'package:puffer/app/providers.dart';
import 'package:puffer/data/subsonic/models.dart';
import 'package:puffer/features/home/home_page.dart';
import 'package:puffer/features/library/downloaded.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<ProviderContainer> container({required bool offline}) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        isOfflineProvider.overrideWithValue(offline),
        albumListProvider.overrideWith(
          (ref, type) => Stream.value(const [
            Album({'id': 'a1', 'name': 'One'}),
            Album({'id': 'a2', 'name': 'Two'}),
            Album({'id': 'a3', 'name': 'Three'}),
          ]),
        ),
        playlistsProvider.overrideWith(
          (ref) => Stream.value(const [
            Playlist({'id': 'p1', 'name': 'Streamed'}),
            Playlist({'id': 'p2', 'name': 'Downloaded'}),
          ]),
        ),
        downloadedTracksProvider.overrideWith(
          (ref) async => const [
            Track({'id': 't1', 'albumId': 'a3'}),
            Track({'id': 't2', 'albumId': 'a1'}),
          ],
        ),
        downloadedPlaylistsProvider.overrideWith(
          (ref) async => const [
            Playlist({'id': 'p2', 'name': 'Downloaded'}),
          ],
        ),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  /// The IDs [shelf] lists once it has loaded.
  Future<List<String>> listed<T>(
    ProviderContainer c,
    ProviderListenable<AsyncValue<List<T>>> shelf,
    String Function(T) id,
  ) async {
    final sub = c.listen(shelf, (_, _) {});
    addTearDown(sub.close);
    for (var i = 0; i < 100 && !sub.read().hasValue; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    return [for (final item in sub.read().value!) id(item)];
  }

  Future<List<String>> albums(ProviderContainer c) =>
      listed(c, shelfAlbumsProvider('newest'), (Album a) => a.id);

  Future<List<String>> playlists(ProviderContainer c) =>
      listed(c, shelfPlaylistsProvider, (Playlist p) => p.id);

  test('online, the shelves show what the server lists', () async {
    final c = await container(offline: false);
    expect(await albums(c), ['a1', 'a2', 'a3']);
    expect(await playlists(c), ['p1', 'p2']);
  });

  test('offline, the shelves stay with the albums and playlists that can play, in their order', () async {
    final c = await container(offline: true);
    expect(await albums(c), ['a1', 'a3']);
    expect(await playlists(c), ['p2']);
  });
}
