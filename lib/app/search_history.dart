import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';

/// The searches a person made on this device, most recent first. A search counts once it is submitted or one of its results is tapped, so the words typed on the way are not kept.
class RecentSearchesNotifier extends Notifier<List<String>> {
  static const _key = 'search.recent';

  /// Older searches are dropped beyond this many.
  static const limit = 10;

  @override
  List<String> build() =>
      ref.read(sharedPreferencesProvider).getStringList(_key) ?? const [];

  /// Puts [query] first. The same words in another case count as the same search.
  Future<void> add(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    final key = q.toLowerCase();
    await _save(
      [q, ...state.where((s) => s.toLowerCase() != key)].take(limit).toList(),
    );
  }

  Future<void> remove(String query) =>
      _save([...state.where((s) => s != query)]);

  Future<void> clear() => _save(const []);

  Future<void> _save(List<String> searches) async {
    state = searches;
    await ref.read(sharedPreferencesProvider).setStringList(_key, searches);
  }
}

final recentSearchesProvider =
    NotifierProvider<RecentSearchesNotifier, List<String>>(
      RecentSearchesNotifier.new,
    );
