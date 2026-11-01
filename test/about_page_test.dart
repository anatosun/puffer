import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:puffer/app/playback_providers.dart';
import 'package:puffer/app/providers.dart';
import 'package:puffer/features/settings/about_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('the About page shows the version and the project links', (
    tester,
  ) async {
    PackageInfo.setMockInitialValues(
      appName: 'Puffer',
      packageName: 'app.puffer',
      version: '0.1.0-alpha.18',
      buildNumber: '18',
      buildSignature: '',
    );
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          nowPlayingProvider.overrideWithValue(const AsyncData(null)),
        ],
        child: const MaterialApp(home: AboutPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('0.1.0-alpha.18 (18)'), findsOneWidget);
    expect(find.text('github.com/anatosun/puffer'), findsOneWidget);
    expect(find.text('github.com/anatosun/puffer/releases'), findsOneWidget);
    expect(find.text('Report a problem'), findsOneWidget);
    expect(find.text('GNU General Public License, version 3'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Open-source licences'), 100);
    await tester.tap(find.text('Open-source licences'));
    await tester.pumpAndSettle();
    expect(find.text('Puffer'), findsWidgets);
  });
}
