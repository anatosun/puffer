import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/subsonic/models.dart';
import 'experience.dart';
import 'providers.dart';

/// When each playlist last started playing on this device. The Subsonic API records plays of songs but not of playlists, so the app keeps this itself.
class PlaylistHistoryNotifier extends Notifier<Map<String, DateTime>> {
  static const _key = 'playlists.played';

  /// Older entries are dropped beyond this many playlists.
  static const _limit = 200;

  @override
  Map<String, DateTime> build() {
    final stored =
        ref.read(sharedPreferencesProvider).getStringList(_key) ?? const [];
    return {
      for (final entry in stored)
        if (entry.split(':') case [final id, final millis]
            when int.tryParse(millis) != null)
          id: DateTime.fromMillisecondsSinceEpoch(int.parse(millis)),
    };
  }

  Future<void> played(String id, {DateTime? at}) async {
    final entries = {...state, id: at ?? DateTime.now()}.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    state = Map.fromEntries(entries.take(_limit));
    await ref.read(sharedPreferencesProvider).setStringList(_key, [
      for (final e in state.entries)
        '${e.key}:${e.value.millisecondsSinceEpoch}',
    ]);
  }
}

final playlistHistoryProvider =
    NotifierProvider<PlaylistHistoryNotifier, Map<String, DateTime>>(
      PlaylistHistoryNotifier.new,
    );

/// [playlists], most recent first: by the later of the last play on this device and the last change on the server.
List<Playlist> byRecency(
  List<Playlist> playlists,
  Map<String, DateTime> played,
) {
  final epoch = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime recency(Playlist p) {
    final changed = DateTime.tryParse(p.changed ?? '') ?? epoch;
    final last = played[p.id] ?? epoch;
    return last.isAfter(changed) ? last : changed;
  }

  return [...playlists]..sort((a, b) => recency(b).compareTo(recency(a)));
}

/// [playlists] by name, ignoring case.
List<Playlist> byName(List<Playlist> playlists) =>
    [...playlists]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

enum PlaylistSort {
  recent('Recently played or changed'),
  name('Name');

  const PlaylistSort(this.label);

  final String label;
}

final playlistSortProvider =
    NotifierProvider<EnumSettingNotifier<PlaylistSort>, PlaylistSort>(
      () => EnumSettingNotifier(
        'library.playlistSort',
        PlaylistSort.values,
        PlaylistSort.recent,
      ),
    );
