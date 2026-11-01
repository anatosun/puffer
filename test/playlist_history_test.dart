import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:puffer/app/playlist_history.dart';
import 'package:puffer/app/providers.dart';
import 'package:puffer/data/subsonic/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

Playlist playlist(String id, String changed) =>
    Playlist({'id': id, 'name': id, 'changed': changed});

void main() {
  test('a played playlist comes before playlists changed earlier', () {
    final playlists = [
      playlist('edited', '2026-10-20T10:00:00Z'),
      playlist('old', '2025-01-01T10:00:00Z'),
      playlist('older', '2024-01-01T10:00:00Z'),
    ];
    final sorted = byRecency(playlists, {
      'old': DateTime.utc(2026, 10, 25),
      // A play before the last change leaves the change as the recency.
      'older': DateTime.utc(2026, 10, 1),
    });
    expect(sorted.map((p) => p.id), ['old', 'edited', 'older']);
  });

  test('plays are stored and survive a restart', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    await c
        .read(playlistHistoryProvider.notifier)
        .played('p1', at: DateTime.utc(2026, 10, 1));
    await c
        .read(playlistHistoryProvider.notifier)
        .played('p2', at: DateTime.utc(2026, 10, 2));

    final restarted = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    expect(restarted.read(playlistHistoryProvider), {
      'p1': DateTime.utc(2026, 10, 1).toLocal(),
      'p2': DateTime.utc(2026, 10, 2).toLocal(),
    });
  });

  test('playlists sort by name ignoring case', () {
    expect(
      byName([
        Playlist(const {'id': '1', 'name': 'beta'}),
        Playlist(const {'id': '2', 'name': 'Alpha'}),
      ]).map((p) => p.name),
      ['Alpha', 'beta'],
    );
  });
}
