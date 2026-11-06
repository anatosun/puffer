import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:puffer/app/providers.dart';
import 'package:puffer/app/search_history.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SharedPreferences prefs;

  ProviderContainer container() {
    final c = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(c.dispose);
    return c;
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  test('the latest search comes first, once, and survives a restart', () async {
    final history = container().read(recentSearchesProvider.notifier);
    await history.add('Miles Davis');
    await history.add('  coltrane ');
    await history.add('');
    await history.add('miles davis');
    expect(container().read(recentSearchesProvider), [
      'miles davis',
      'coltrane',
    ]);
  });

  test('only the latest searches are kept', () async {
    final history = container().read(recentSearchesProvider.notifier);
    for (var i = 0; i < RecentSearchesNotifier.limit + 3; i++) {
      await history.add('search $i');
    }
    final kept = container().read(recentSearchesProvider);
    expect(kept, hasLength(RecentSearchesNotifier.limit));
    expect(kept.first, 'search ${RecentSearchesNotifier.limit + 2}');
  });

  test('a search can be removed, and all of them cleared', () async {
    final c = container();
    final history = c.read(recentSearchesProvider.notifier);
    await history.add('a');
    await history.add('b');
    await history.remove('a');
    expect(c.read(recentSearchesProvider), ['b']);
    await history.clear();
    expect(container().read(recentSearchesProvider), isEmpty);
  });
}
