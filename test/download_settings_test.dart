import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:puffer/app/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('saving a download setting works while the manager depends on the '
      'settings', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    var synced = 0;
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        // As in the app, the manager follows the settings.
        downloadManagerProvider.overrideWith((ref) {
          ref.watch(downloadSettingsProvider);
          return null;
        }),
        syncAutomaticDownloadsProvider.overrideWithValue(() async => synced++),
      ],
    );
    addTearDown(container.dispose);
    container.listen(downloadManagerProvider, (_, _) {});

    final settings = container.read(downloadSettingsProvider);
    await container
        .read(downloadSettingsUpdaterProvider)
        .update(settings.copyWith(simultaneous: 5, automaticDownloads: true));

    expect(container.read(downloadSettingsProvider).simultaneous, 5);
    expect(prefs.getInt('downloads.simultaneous'), 5);
    expect(synced, 1);
  });
}
