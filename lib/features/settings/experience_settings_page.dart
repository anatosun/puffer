import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/experience.dart';
import '../../app/providers.dart';
import '../../ui/theme.dart';
import 'settings_section.dart';
import '../../ui/widgets/backdrop.dart';

class ExperienceSettingsPage extends ConsumerWidget {
  const ExperienceSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Backdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
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
              onChanged: (v) =>
                  ref.read(artworkColoursProvider.notifier).set(v),
            ),
            ListTile(
              enabled: ref.watch(artworkColoursProvider),
              title: const Text('When nothing plays'),
              subtitle: const Text('The background behind the pages'),
              trailing: DropdownButton<IdleBackground>(
                value: ref.watch(idleBackgroundProvider),
                underline: const SizedBox.shrink(),
                items: [
                  for (final b in IdleBackground.values)
                    DropdownMenuItem(value: b, child: Text(b.label)),
                ],
                onChanged: ref.watch(artworkColoursProvider)
                    ? (b) => ref.read(idleBackgroundProvider.notifier).set(b!)
                    : null,
              ),
            ),
            const SettingsSection('Layout'),
            ListTile(
              title: const Text('Start on'),
              trailing: DropdownButton<MainTab>(
                value: ref.watch(effectiveStartTabProvider),
                underline: const SizedBox.shrink(),
                items: [
                  for (final t in ref.watch(visibleTabsProvider))
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
            const SettingsSection('Player'),
            _Switch(
              provider: playerRatingProvider,
              title: 'Rating',
              subtitle: 'The stars of the current song, which a tap changes',
            ),
            _Switch(
              provider: playerFavouriteProvider,
              title: 'Favourite button',
              subtitle:
                  'A heart next to the stars adds the song to your library',
            ),
            _Switch(
              provider: playerFormatProvider,
              title: 'Format badges',
              subtitle:
                  'The codec and the quality of what plays, around the stars',
            ),
            ListTile(
              title: const Text('Waveform'),
              subtitle: const Text(
                'The loudness of the song in the seek bar, when the server offers it',
              ),
              trailing: DropdownButton<WaveformStyle>(
                value: ref.watch(waveformStyleProvider),
                underline: const SizedBox.shrink(),
                items: [
                  for (final w in WaveformStyle.values)
                    DropdownMenuItem(value: w, child: Text(w.label)),
                ],
                onChanged: (w) =>
                    ref.read(waveformStyleProvider.notifier).set(w!),
              ),
            ),
            _Switch(
              provider: remainingTimeProvider,
              title: 'Remaining time',
              subtitle: 'The time on the right counts down; off, it shows the length of the song',
            ),
            _Switch(
              provider: swipeToSkipProvider,
              title: 'Swipe the artwork to skip',
              subtitle: 'Swiping sideways plays the next or previous song',
            ),
            _Switch(
              provider: upNextProvider,
              title: 'Up next',
              subtitle: 'The next song shows under the controls',
            ),
            const SettingsSection('Tabs'),
            const _Hint('From two to five tabs. Press and drag to reorder.'),
            _ToggleList(
              provider: mainTabsProvider,
              label: (t) => t.label,
              icon: (t) => t.icon,
            ),
            const SettingsSection('Library'),
            _ToggleList(
              provider: librarySectionsProvider,
              label: (s) => s.title,
              icon: (s) => s.icon,
            ),
            const SettingsSection('Home'),
            SwitchListTile(
              title: const Text('Greeting'),
              subtitle: const Text(
                'The title of Home greets you by the time of day',
              ),
              value: ref.watch(greetingProvider),
              onChanged: (v) => ref.read(greetingProvider.notifier).set(v),
            ),
            SwitchListTile(
              title: const Text('Continue listening'),
              subtitle: const Text('Home opens with the album you played last'),
              value: ref.watch(continueListeningProvider),
              onChanged: (v) =>
                  ref.read(continueListeningProvider.notifier).set(v),
            ),
            _ToggleList(provider: homeShelvesProvider, label: (s) => s.label),
          ],
        ),
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

/// A switch for a [BoolSettingNotifier].
class _Switch extends ConsumerWidget {
  const _Switch({
    required this.provider,
    required this.title,
    required this.subtitle,
  });

  final NotifierProvider<BoolSettingNotifier, bool> provider;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) => SwitchListTile(
    title: Text(title),
    subtitle: Text(subtitle),
    value: ref.watch(provider),
    onChanged: (v) => ref.read(provider.notifier).set(v),
  );
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
    child: Text(text, style: TextStyle(color: context.muted, fontSize: 13)),
  );
}

/// An ordered list of settings: the checkbox shows or hides an entry, pressing and dragging moves it. A checkbox greys out when the change would cross the limits of the list.
class _ToggleList<T extends Enum> extends ConsumerWidget {
  const _ToggleList({required this.provider, required this.label, this.icon});

  final NotifierProvider<OrderedToggleNotifier<T>, List<ToggleItem<T>>>
  provider;
  final String Function(T) label;
  final IconData Function(T)? icon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(provider);
    final notifier = ref.read(provider.notifier);
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: items.length,
      onReorderItem: notifier.move,
      itemBuilder: (context, i) {
        final entry = items[i];
        return ReorderableDelayedDragStartListener(
          key: ValueKey(entry.item),
          index: i,
          child: CheckboxListTile(
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(label(entry.item)),
            secondary: icon == null ? null : Icon(icon!(entry.item)),
            value: entry.visible,
            enabled: notifier.canToggle(entry.item),
            onChanged: (v) => notifier.setVisible(entry.item, v ?? false),
          ),
        );
      },
    );
  }
}
