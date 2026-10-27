import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/experience.dart';
import '../../app/providers.dart';
import 'settings_section.dart';

class ExperienceSettingsPage extends ConsumerWidget {
  const ExperienceSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Experience')),
      body: ListView(
        children: [
          const SettingsSection('Appearance'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SegmentedButton<ThemeMode>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: ThemeMode.system,
                  label: Text('System'),
                  icon: Icon(Icons.brightness_auto),
                ),
                ButtonSegment(
                  value: ThemeMode.light,
                  label: Text('Light'),
                  icon: Icon(Icons.light_mode_outlined),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  label: Text('Dark'),
                  icon: Icon(Icons.dark_mode_outlined),
                ),
              ],
              selected: {ref.watch(themeModeProvider)},
              onSelectionChanged: (s) =>
                  ref.read(themeModeProvider.notifier).set(s.single),
            ),
          ),
          const _AccentPicker(),
          SwitchListTile(
            title: const Text('Colours from artwork'),
            subtitle: const Text(
              'Album pages and the player take their colours from the album artwork',
            ),
            value: ref.watch(artworkColoursProvider),
            onChanged: (v) => ref.read(artworkColoursProvider.notifier).set(v),
          ),
          const SettingsSection('Layout'),
          ListTile(
            title: const Text('Start on'),
            trailing: DropdownButton<StartTab>(
              value: ref.watch(startTabProvider),
              underline: const SizedBox.shrink(),
              items: [
                for (final t in StartTab.values)
                  DropdownMenuItem(value: t, child: Text(t.label)),
              ],
              onChanged: (t) => ref.read(startTabProvider.notifier).set(t!),
            ),
          ),
          ListTile(
            title: const Text('Cover size'),
            trailing: SegmentedButton<CoverSize>(
              showSelectedIcon: false,
              segments: [
                for (final c in CoverSize.values)
                  ButtonSegment(value: c, label: Text(c.label)),
              ],
              selected: {ref.watch(coverSizeProvider)},
              onSelectionChanged: (s) =>
                  ref.read(coverSizeProvider.notifier).set(s.single),
            ),
          ),
          const SettingsSection('Home'),
          const _ShelfList(),
        ],
      ),
    );
  }
}

class _AccentPicker extends ConsumerWidget {
  const _AccentPicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(accentProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          // Material You exists on Android only.
          for (final accent in AccentColour.values.where(
            (a) => a != AccentColour.wallpaper || Platform.isAndroid,
          ))
            Tooltip(
              message: accent.label,
              child: InkResponse(
                onTap: () => ref.read(accentProvider.notifier).set(accent),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: accent == AccentColour.wallpaper
                        ? null
                        : accent.color,
                    gradient: accent == AccentColour.wallpaper
                        ? const SweepGradient(
                            colors: [
                              Colors.red,
                              Colors.amber,
                              Colors.green,
                              Colors.blue,
                              Colors.purple,
                              Colors.red,
                            ],
                          )
                        : null,
                    shape: BoxShape.circle,
                    border: accent == selected
                        ? Border.all(
                            color: Theme.of(context).colorScheme.onSurface,
                            width: 3,
                          )
                        : null,
                  ),
                  child: accent == selected
                      ? const Icon(Icons.check, size: 20, color: Colors.white)
                      : null,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The home shelves: the checkbox shows or hides a shelf, pressing and dragging moves it.
class _ShelfList extends ConsumerWidget {
  const _ShelfList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shelves = ref.watch(homeShelvesProvider);
    final notifier = ref.read(homeShelvesProvider.notifier);
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: shelves.length,
      onReorderItem: notifier.move,
      itemBuilder: (context, i) {
        final setting = shelves[i];
        return ReorderableDelayedDragStartListener(
          key: ValueKey(setting.shelf),
          index: i,
          child: CheckboxListTile(
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(setting.shelf.label),
            value: setting.visible,
            onChanged: (v) => notifier.setVisible(setting.shelf, v ?? false),
          ),
        );
      },
    );
  }
}
