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
    expect(shelves.map((s) => s.shelf), HomeShelf.values);
    expect(shelves.where((s) => !s.visible).map((s) => s.shelf), [
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
        c.read(homeShelvesProvider).take(2).map((s) => (s.shelf, s.visible)),
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
    await c.read(startTabProvider.notifier).set(StartTab.library);
    expect(
      c.read(sharedPreferencesProvider).getString('experience.startTab'),
      'library',
    );
  });
}
