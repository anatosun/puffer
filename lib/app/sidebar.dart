import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/collection/playlist_edit.dart';
import '../features/home/home_page.dart';
import '../ui/theme.dart';
import '../ui/widgets/brand_mark.dart';
import '../ui/widgets/tiles.dart';
import 'experience.dart';
import 'providers.dart';

/// The navigation of a wide window: the tabs the person chose, the playlists, and the settings. Songs dragged with the mouse onto a playlist are added to it.
class Sidebar extends ConsumerWidget {
  const Sidebar({super.key, required this.location, required this.selected});

  static const width = 240.0;

  final String location;

  /// The tab of the page, which pages outside every tab keep from the tab they were opened from.
  final MainTab? selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tabs = ref.watch(visibleTabsProvider);
    final playlists = ref.watch(playlistsProvider).value ?? const [];
    final settings = location.startsWith('/settings');
    return Material(
      color: context.colors.surfaceContainerLow,
      child: SizedBox(
        width: width,
        child: SafeArea(
          right: false,
          child: CustomScrollView(
            slivers: [
              const SliverPadding(
                padding: EdgeInsets.fromLTRB(8, 8, 20, 4),
                sliver: SliverToBoxAdapter(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Row(
                      children: [
                        BrandMark(size: 64),
                        SizedBox(width: 8),
                        Text(
                          'Puffer',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SliverList.list(
                children: [
                  for (final t in tabs)
                    _Entry(
                      icon: t == selected && !settings
                          ? t.selectedIcon
                          : t.icon,
                      label: t.label,
                      selected: t == selected && !settings,
                      onTap: () => context.go(t.path),
                    ),
                  _Entry(
                    icon: settings ? Icons.settings : Icons.settings_outlined,
                    label: 'Settings',
                    selected: settings,
                    onTap: () => context.go('/settings'),
                  ),
                ],
              ),
              if (playlists.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                    child: Text(
                      'PLAYLISTS',
                      style: TextStyle(
                        color: context.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ),
                SliverList.builder(
                  itemCount: playlists.length,
                  itemBuilder: (context, i) {
                    final p = playlists[i];
                    final path = '/playlist/${p.id}';
                    // Songs dropped on a playlist of the person are added to it.
                    return DragTarget<DraggedSongs>(
                      onWillAcceptWithDetails: (_) =>
                          ownsPlaylist(ref, p) && !ref.read(isOfflineProvider),
                      onAcceptWithDetails: (details) =>
                          addToPlaylist(context, p, details.data.tracks),
                      builder: (context, candidates, _) => SecondaryTap(
                        onTap: () => showPlaylistActions(context, ref, p),
                        child: _Entry(
                          leading: PlaylistArtwork(p, size: 28, radius: 4),
                          label: p.name,
                          selected: location == path,
                          target: candidates.isNotEmpty,
                          onTap: () => context.go(path),
                        ),
                      ),
                    );
                  },
                ),
              ],
              const SliverPadding(padding: EdgeInsets.only(bottom: 12)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Entry extends StatelessWidget {
  const _Entry({
    this.icon,
    this.leading,
    required this.label,
    required this.selected,
    this.target = false,
    required this.onTap,
  });

  final IconData? icon;
  final Widget? leading;
  final String label;
  final bool selected;

  /// Whether songs dragged over the entry would be dropped on it.
  final bool target;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
    child: ListTile(
      dense: true,
      tileColor: target ? context.colors.primary.withValues(alpha: 0.25) : null,
      visualDensity: VisualDensity.compact,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      selected: selected,
      selectedColor: context.colors.onSurface,
      selectedTileColor: context.colors.onSurface.withValues(alpha: 0.08),
      leading: leading ?? Icon(icon, size: 22),
      minLeadingWidth: 28,
      title: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 14,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      onTap: onTap,
    ),
  );
}
