import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/experience.dart';
import '../../app/providers.dart';
import '../../downloads/download_settings.dart';

// Controls that Settings and the first setup share.

/// Light, dark, or as the system.
class ThemeModePicker extends ConsumerWidget {
  const ThemeModePicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
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
  );
}

/// The accent colours to pick from. The wallpaper's colours (Material You) exist on Android only.
class AccentPicker extends ConsumerWidget {
  const AccentPicker({super.key});

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

/// The streaming quality on one kind of network.
class StreamingQualityTile extends ConsumerWidget {
  const StreamingQualityTile(this.title, this.provider, {super.key});

  final String title;
  final NotifierProvider<StreamingQualityNotifier, DownloadQuality> provider;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ListTile(
    title: Text(title),
    trailing: DropdownButton<DownloadQuality>(
      value: ref.watch(provider),
      underline: const SizedBox.shrink(),
      items: [
        for (final q in DownloadQuality.values)
          DropdownMenuItem(value: q, child: Text(q.label)),
      ],
      onChanged: (q) => ref.read(provider.notifier).set(q!),
    ),
  );
}
