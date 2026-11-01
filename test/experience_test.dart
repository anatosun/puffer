import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:puffer/app/experience.dart';
import 'package:puffer/app/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> container(Map<String, Object> stored) async {
  SharedPreferences.setMockInitialValues(stored);
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
}

void main() {
  test('shelves default to every shelf but favourites, in order', () async {
    final c = await container({});
    final shelves = c.read(homeShelvesProvider);
    expect(shelves.map((s) => s.item), HomeShelf.values);
    expect(shelves.where((s) => !s.visible).map((s) => s.item), [
      HomeShelf.starred,
    ]);
  });

  test(
    'moving and hiding shelves is stored, and unknown shelves are appended',
    () async {
      final c = await container({
        'experience.homeShelves': ['downloaded:1', 'recent:0'],
      });
      expect(
        c.read(homeShelvesProvider).take(2).map((s) => (s.item, s.visible)),
        [(HomeShelf.downloaded, true), (HomeShelf.recent, false)],
      );
      expect(c.read(homeShelvesProvider), hasLength(HomeShelf.values.length));

      await c.read(homeShelvesProvider.notifier).move(0, 1);
      await c
          .read(homeShelvesProvider.notifier)
          .setVisible(HomeShelf.recent, true);
      final prefs = c.read(sharedPreferencesProvider);
      expect(prefs.getStringList('experience.homeShelves')!.take(2), [
        'recent:1',
        'downloaded:1',
      ]);
    },
  );

  test('enum settings fall back to their default for unknown values', () async {
    final c = await container({
      'experience.accent': 'plaid',
      'experience.coverSize': 'large',
    });
    expect(c.read(accentProvider), AccentColour.amber);
    expect(c.read(coverSizeProvider), CoverSize.large);
    await c.read(startTabProvider.notifier).set(MainTab.library);
    expect(
      c.read(sharedPreferencesProvider).getString('experience.startTab'),
      'library',
    );
  });

  test(
    'tabs default to Home, Library and Search and keep two to five',
    () async {
      final c = await container({});
      expect(c.read(visibleTabsProvider), [
        MainTab.home,
        MainTab.library,
        MainTab.search,
      ]);
      final tabs = c.read(mainTabsProvider.notifier);
      await tabs.setVisible(MainTab.search, false);
      await tabs.setVisible(MainTab.home, false);
      // Hiding the last two tabs is refused, and Library always shows because Settings open from it.
      expect(c.read(visibleTabsProvider), [MainTab.home, MainTab.library]);
      await tabs.setVisible(MainTab.search, true);
      await tabs.setVisible(MainTab.library, false);
      expect(c.read(visibleTabsProvider), contains(MainTab.library));
      await tabs.setVisible(MainTab.search, false);
      for (final t in [
        MainTab.playlists,
        MainTab.artists,
        MainTab.albums,
        MainTab.downloaded,
      ]) {
        await tabs.setVisible(t, true);
      }
      // The fifth tab fills the bar, so Downloaded stays hidden.
      expect(c.read(visibleTabsProvider), hasLength(5));
      expect(c.read(visibleTabsProvider), isNot(contains(MainTab.downloaded)));
    },
  );

  test('a hidden start tab falls back to the first shown tab', () async {
    final c = await container({
      'experience.startTab': 'search',
      'experience.mainTabs': ['playlists:1', 'library:1', 'search:0'],
    });
    expect(c.read(effectiveStartTabProvider), MainTab.playlists);
  });

  test('locations belong to the tab with the longest matching path', () {
    final tabs = [MainTab.home, MainTab.library, MainTab.playlists];
    expect(tabFor('/library/playlists', tabs), MainTab.playlists);
    expect(tabFor('/library/artists', tabs), MainTab.library);
    expect(tabFor('/library/playlistsx', tabs), MainTab.library);
    expect(tabFor('/settings/playback', tabs), MainTab.library);
    expect(tabFor('/album/1', tabs), isNull);
    expect(
      tabFor('/library/downloaded/albums', [...tabs, MainTab.downloaded]),
      MainTab.downloaded,
    );
  });
}
