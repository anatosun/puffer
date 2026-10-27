import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';

/// An enum setting stored by name under [key].
class EnumSettingNotifier<T extends Enum> extends Notifier<T> {
  EnumSettingNotifier(this.key, this.values, this.defaultValue);

  final String key;
  final List<T> values;
  final T defaultValue;

  @override
  T build() =>
      values.asNameMap()[ref.read(sharedPreferencesProvider).getString(key)] ??
      defaultValue;

  Future<void> set(T value) async {
    state = value;
    await ref.read(sharedPreferencesProvider).setString(key, value.name);
  }
}

enum AccentColour {
  amber('Amber', Color(0xFFE5A00D)),
  coral('Coral', Color(0xFFFF6B5A)),
  rose('Rose', Color(0xFFE5487B)),
  violet('Violet', Color(0xFF8C6CF0)),
  blue('Blue', Color(0xFF3D8BF2)),
  teal('Teal', Color(0xFF1FB5A3)),
  green('Green', Color(0xFF4CAF50));

  const AccentColour(this.label, this.color);

  final String label;
  final Color color;
}

final accentProvider =
    NotifierProvider<EnumSettingNotifier<AccentColour>, AccentColour>(
      () => EnumSettingNotifier(
        'experience.accent',
        AccentColour.values,
        AccentColour.amber,
      ),
    );

enum StartTab {
  home('Home', '/home'),
  library('Library', '/library'),
  search('Search', '/search');

  const StartTab(this.label, this.path);

  final String label;
  final String path;
}

final startTabProvider =
    NotifierProvider<EnumSettingNotifier<StartTab>, StartTab>(
      () => EnumSettingNotifier(
        'experience.startTab',
        StartTab.values,
        StartTab.home,
      ),
    );

/// Cover size of album grids and shelves: the target column width of grids and the card width of shelves.
enum CoverSize {
  small('Small', 130, 120),
  medium('Medium', 180, 150),
  large('Large', 240, 190);

  const CoverSize(this.label, this.gridWidth, this.shelfWidth);

  final String label;
  final double gridWidth;
  final double shelfWidth;

  int columns(double available) => (available / gridWidth).floor().clamp(2, 8);
}

final coverSizeProvider =
    NotifierProvider<EnumSettingNotifier<CoverSize>, CoverSize>(
      () => EnumSettingNotifier(
        'experience.coverSize',
        CoverSize.values,
        CoverSize.medium,
      ),
    );

/// A shelf of the home screen. [albumList] is the `getAlbumList2` type of album shelves.
enum HomeShelf {
  recent('Recently played', 'recent'),
  newest('Recently added', 'newest'),
  playlists('Recent playlists', null),
  frequent('Most played', 'frequent'),
  random('Discover', 'random'),
  starred('Favourites', 'starred'),
  downloaded('Downloaded', null);

  const HomeShelf(this.label, this.albumList);

  final String label;
  final String? albumList;
}

class ShelfSetting {
  const ShelfSetting(this.shelf, {required this.visible});

  final HomeShelf shelf;
  final bool visible;
}

/// The home shelves in display order, each shown or hidden. Stored as `name:1` or `name:0` entries.
class HomeShelvesNotifier extends Notifier<List<ShelfSetting>> {
  static const _key = 'experience.homeShelves';

  @override
  List<ShelfSetting> build() {
    final stored =
        ref.read(sharedPreferencesProvider).getStringList(_key) ?? const [];
    final byName = HomeShelf.values.asNameMap();
    final result = <ShelfSetting>[];
    for (final entry in stored) {
      final [name, visible] = entry.split(':');
      final shelf = byName[name];
      if (shelf != null) {
        result.add(ShelfSetting(shelf, visible: visible == '1'));
      }
    }
    // Shelves added in later versions appear at the end, shown unless they are new extras.
    for (final shelf in HomeShelf.values) {
      if (result.every((s) => s.shelf != shelf)) {
        result.add(ShelfSetting(shelf, visible: shelf != HomeShelf.starred));
      }
    }
    return result;
  }

  Future<void> _save(List<ShelfSetting> shelves) async {
    state = shelves;
    await ref.read(sharedPreferencesProvider).setStringList(_key, [
      for (final s in shelves) '${s.shelf.name}:${s.visible ? 1 : 0}',
    ]);
  }

  Future<void> move(int from, int to) {
    final shelves = [...state];
    shelves.insert(to, shelves.removeAt(from));
    return _save(shelves);
  }

  Future<void> setVisible(HomeShelf shelf, bool visible) => _save([
    for (final s in state)
      s.shelf == shelf ? ShelfSetting(shelf, visible: visible) : s,
  ]);
}

final homeShelvesProvider =
    NotifierProvider<HomeShelvesNotifier, List<ShelfSetting>>(
      HomeShelvesNotifier.new,
    );
