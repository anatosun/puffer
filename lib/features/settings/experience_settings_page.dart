import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
          SwitchListTile(
            title: const Text('Colours from artwork'),
            subtitle: const Text(
              'Album pages and the player take their colours from the album artwork',
            ),
            value: ref.watch(artworkColoursProvider),
            onChanged: (v) => ref.read(artworkColoursProvider.notifier).set(v),
          ),
        ],
      ),
    );
  }
}
