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
  /// The colour of the wallpaper on Android 12 and later (Material You), amber elsewhere.
  wallpaper('Wallpaper', Color(0xFFE5A00D)),
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

/// A tab of the navigation bar. Home, Library and Search show by default; the others open a library list straight from the bar.
enum MainTab {
  home('Home', '/home', Icons.home_outlined, Icons.home),
  library(
    'Library',
    '/library',
    Icons.library_music_outlined,
    Icons.library_music,
  ),
  search('Search', '/search', Icons.search, Icons.search),
  playlists(
    'Playlists',
    '/library/playlists',
    Icons.queue_music_outlined,
    Icons.queue_music,
  ),
  artists('Artists', '/library/artists', Icons.mic_none, Icons.mic),
  albums('Albums', '/library/albums', Icons.album_outlined, Icons.album),
  downloaded(
    'Downloaded',
    '/library/downloaded',
    Icons.arrow_circle_down_outlined,
    Icons.arrow_circle_down,
  );

  const MainTab(this.label, this.path, this.icon, this.selectedIcon);

  final String label;
  final String path;
  final IconData icon;
  final IconData selectedIcon;
}

/// The tab whose path is the longest prefix of [location], so `/library/playlists` belongs to Playlists when that tab shows and to Library otherwise. Settings open from the library and belong to it.
MainTab? tabFor(String location, List<MainTab> tabs) {
  if (location.startsWith('/settings')) location = '/library';
  MainTab? best;
  for (final tab in tabs) {
    final match = location == tab.path || location.startsWith('${tab.path}/');
    if (match && (best == null || tab.path.length > best.path.length)) {
      best = tab;
    }
  }
  return best;
}

/// The tab the app opens on, stored by name. [effectiveStartTabProvider] falls back to the first shown tab when this one is hidden.
final startTabProvider =
    NotifierProvider<EnumSettingNotifier<MainTab>, MainTab>(
      () => EnumSettingNotifier(
        'experience.startTab',
        MainTab.values,
        MainTab.home,
      ),
    );

final effectiveStartTabProvider = Provider<MainTab>((ref) {
  final start = ref.watch(startTabProvider);
  final tabs = ref.watch(visibleTabsProvider);
  return tabs.contains(start) ? start : tabs.first;
});

/// The background of the pages when nothing is playing.
enum IdleBackground {
  accent('Accent colour'),
  lastPlayed('Last played album'),
  none('None');

  const IdleBackground(this.label);

  final String label;
}

final idleBackgroundProvider =
    NotifierProvider<EnumSettingNotifier<IdleBackground>, IdleBackground>(
      () => EnumSettingNotifier(
        'experience.idleBackground',
        IdleBackground.values,
        IdleBackground.accent,
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

/// A section of the Library tab.
enum LibrarySection {
  playlists('Playlists', Icons.queue_music),
  artists('Artists', Icons.mic_none),
  albums('Albums', Icons.album_outlined),
  genres('Genres', Icons.category_outlined),
  years('Years', Icons.calendar_month_outlined),
  songs('Songs', Icons.music_note_outlined);

  const LibrarySection(this.title, this.icon);

  final String title;
  final IconData icon;
}

/// An entry of an ordered list a person arranges, shown or hidden.
class ToggleItem<T> {
  const ToggleItem(this.item, {required this.visible});

  final T item;
  final bool visible;
}

/// The values of [T] in the order a person chose, each shown or hidden, stored under [key] as `name:1` or `name:0` entries. Values added in later versions appear at the end, shown when [shownByDefault] says so. Hiding stops at [minVisible] shown entries and showing at [maxVisible]; entries that [locked] names always show.
class OrderedToggleNotifier<T extends Enum>
    extends Notifier<List<ToggleItem<T>>> {
  OrderedToggleNotifier(
    this.key,
    this.values, {
    required this.shownByDefault,
    this.minVisible = 0,
    this.maxVisible,
    this.locked,
  });

  final String key;
  final List<T> values;
  final bool Function(T) shownByDefault;
  final int minVisible;
  final int? maxVisible;
  final bool Function(T)? locked;

  @override
  List<ToggleItem<T>> build() {
    final stored =
        ref.read(sharedPreferencesProvider).getStringList(key) ?? const [];
    final byName = values.asNameMap();
    final result = <ToggleItem<T>>[];
    for (final entry in stored) {
      final [name, visible] = entry.split(':');
      final item = byName[name];
      if (item != null && result.every((s) => s.item != item)) {
        result.add(
          ToggleItem(
            item,
            visible: visible == '1' || (locked?.call(item) ?? false),
          ),
        );
      }
    }
    for (final item in values) {
      if (result.every((s) => s.item != item)) {
        result.add(ToggleItem(item, visible: shownByDefault(item)));
      }
    }
    return result;
  }

  int get _visibleCount => state.where((s) => s.visible).length;

  /// Whether [item] can be shown or hidden without crossing the limits.
  bool canToggle(T item) {
    final visible = state.firstWhere((s) => s.item == item).visible;
    if (locked?.call(item) ?? false) return false;
    return visible
        ? _visibleCount > minVisible
        : maxVisible == null || _visibleCount < maxVisible!;
  }

  Future<void> _save(List<ToggleItem<T>> items) async {
    state = items;
    await ref.read(sharedPreferencesProvider).setStringList(key, [
      for (final s in items) '${s.item.name}:${s.visible ? 1 : 0}',
    ]);
  }

  Future<void> move(int from, int to) {
    final items = [...state];
    items.insert(to, items.removeAt(from));
    return _save(items);
  }

  Future<void> setVisible(T item, bool visible) async {
    final current = state.firstWhere((s) => s.item == item).visible;
    if (current == visible || !canToggle(item)) return;
    await _save([
      for (final s in state)
        s.item == item ? ToggleItem(item, visible: visible) : s,
    ]);
  }
}

/// The home shelves in display order. Favourites, added later, start hidden.
final homeShelvesProvider =
    NotifierProvider<
      OrderedToggleNotifier<HomeShelf>,
      List<ToggleItem<HomeShelf>>
    >(
      () => OrderedToggleNotifier(
        'experience.homeShelves',
        HomeShelf.values,
        shownByDefault: (s) => s != HomeShelf.starred,
      ),
    );

/// The tabs of the navigation bar in order: from two to five shown, as the Material navigation bar allows. Library always shows, since Settings open from it.
final mainTabsProvider =
    NotifierProvider<OrderedToggleNotifier<MainTab>, List<ToggleItem<MainTab>>>(
      () => OrderedToggleNotifier(
        'experience.mainTabs',
        MainTab.values,
        shownByDefault: (t) =>
            t == MainTab.home || t == MainTab.library || t == MainTab.search,
        minVisible: 2,
        maxVisible: 5,
        locked: (t) => t == MainTab.library,
      ),
    );

final visibleTabsProvider = Provider<List<MainTab>>((ref) {
  final tabs = [
    for (final t in ref.watch(mainTabsProvider))
      if (t.visible) t.item,
  ];
  return tabs.length >= 2
      ? tabs
      : const [MainTab.home, MainTab.library, MainTab.search];
});

/// The sections of the Library tab in order, each shown or hidden.
final librarySectionsProvider =
    NotifierProvider<
      OrderedToggleNotifier<LibrarySection>,
      List<ToggleItem<LibrarySection>>
    >(
      () => OrderedToggleNotifier(
        'experience.librarySections',
        LibrarySection.values,
        shownByDefault: (_) => true,
      ),
    );

// ------------------------------------------------------------ player

/// The heart in the player, which adds the current song to the library.
final playerFavouriteProvider = NotifierProvider<BoolSettingNotifier, bool>(
  () => BoolSettingNotifier('experience.playerFavourite', true),
);

/// The codec and quality badges around the rating in the player.
final playerFormatProvider = NotifierProvider<BoolSettingNotifier, bool>(
  () => BoolSettingNotifier('experience.playerFormat', true),
);

/// The time on the right of the seek bar counts down what remains; otherwise it shows the length of the song.
final remainingTimeProvider = NotifierProvider<BoolSettingNotifier, bool>(
  () => BoolSettingNotifier('experience.remainingTime', true),
);

/// Swiping the artwork sideways skips to the next or previous song.
final swipeToSkipProvider = NotifierProvider<BoolSettingNotifier, bool>(
  () => BoolSettingNotifier('experience.swipeToSkip', true),
);

/// The next song, under the controls of the player.
final upNextProvider = NotifierProvider<BoolSettingNotifier, bool>(
  () => BoolSettingNotifier('experience.upNext', true),
);

/// How the seek bar draws the loudness of the song, when the server offers waveforms.
enum WaveformStyle {
  smooth('Smooth'),
  detailed('Detailed'),
  off('Off');

  const WaveformStyle(this.label);

  final String label;
}

final waveformStyleProvider =
    NotifierProvider<EnumSettingNotifier<WaveformStyle>, WaveformStyle>(
      () => EnumSettingNotifier(
        'experience.waveformStyle',
        WaveformStyle.values,
        WaveformStyle.smooth,
      ),
    );
