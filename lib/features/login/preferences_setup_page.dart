import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/experience.dart';
import '../../app/providers.dart';
import '../../app/setup.dart';
import '../../downloads/download_settings.dart';
import '../../ui/theme.dart';
import '../settings/setting_controls.dart';
import '../settings/settings_section.dart';

/// The last step of the first setup: the options a person most likely wants to choose at once. Each control is the one in Settings, so a choice here shows there, and each already holds its default, so Continue with nothing changed keeps the defaults.
class PreferencesSetupPage extends ConsumerWidget {
  const PreferencesSetupPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void done() {
      ref.read(setupPreferencesOfferedProvider.notifier).set(true);
      context.go(nextSetupPage(ref.read));
    }

    final downloads = ref.watch(downloadSettingsProvider);
    final updater = ref.read(downloadSettingsUpdaterProvider);
    return Scaffold(
      appBar: AppBar(automaticallyImplyLeading: false),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    children: [
                      Text(
                        'Make it yours',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          'You can change all of these later in Settings.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: context.muted),
                        ),
                      ),
                      const SettingsSection('Appearance'),
                      const ThemeModePicker(),
                      const AccentPicker(),
                      SwitchListTile(
                        title: const Text('Colours from artwork'),
                        subtitle: const Text(
                          'Album pages and the player take their colours from the album artwork',
                        ),
                        value: ref.watch(artworkColoursProvider),
                        onChanged: (v) =>
                            ref.read(artworkColoursProvider.notifier).set(v),
                      ),
                      SwitchListTile(
                        title: const Text('Start-up animation'),
                        subtitle: const Text(
                          'The pufferfish plays when the app opens',
                        ),
                        value: ref.watch(launchAnimationProvider),
                        onChanged: (v) =>
                            ref.read(launchAnimationProvider.notifier).set(v),
                      ),
                      const SettingsSection('Streaming quality'),
                      StreamingQualityTile('On Wi-Fi', wifiQualityProvider),
                      StreamingQualityTile(
                        'On cellular',
                        cellularQualityProvider,
                      ),
                      const SettingsSection('Downloads'),
                      ListTile(
                        title: const Text('Download quality'),
                        trailing: DropdownButton<DownloadQuality>(
                          value: downloads.quality,
                          underline: const SizedBox.shrink(),
                          items: [
                            for (final q in DownloadQuality.values)
                              DropdownMenuItem(value: q, child: Text(q.label)),
                          ],
                          onChanged: (q) =>
                              updater.update(downloads.copyWith(quality: q)),
                        ),
                      ),
                      SwitchListTile(
                        title: const Text('Download over cellular'),
                        value: downloads.overCellular,
                        onChanged: (v) =>
                            updater.update(downloads.copyWith(overCellular: v)),
                      ),
                      SwitchListTile(
                        title: const Text('Automatic downloads'),
                        subtitle: const Text(
                          'Download songs, albums and artists when you add them to your library',
                        ),
                        value: downloads.automaticDownloads,
                        onChanged: (v) => updater.update(
                          downloads.copyWith(automaticDownloads: v),
                        ),
                      ),
                      const SettingsSection('Listening history'),
                      SwitchListTile(
                        title: const Text('Report plays to the server'),
                        subtitle: const Text(
                          'Keeps "Recently played" and "Most played" up to date',
                        ),
                        value: ref.watch(scrobblingProvider),
                        onChanged: (v) =>
                            ref.read(scrobblingProvider.notifier).set(v),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: FilledButton(
                    onPressed: done,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: const Text('Continue'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
