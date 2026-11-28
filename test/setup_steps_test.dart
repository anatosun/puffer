import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:puffer/app/playback_providers.dart';
import 'package:puffer/app/providers.dart';
import 'package:puffer/app/setup.dart';
import 'package:puffer/features/login/preferences_setup_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _container(
  Map<String, Object> stored, {
  MaCredentials? ma,
}) async {
  SharedPreferences.setMockInitialValues(stored);
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      initialMaCredentialsProvider.overrideWithValue(ma),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test(
    'the setup offers Music Assistant, then the options, then home',
    () async {
      var c = await _container({});
      expect(nextSetupPage(c.read), '/setup/music-assistant');

      c = await _container({'setup.musicAssistantOffered': true});
      expect(nextSetupPage(c.read), '/setup/preferences');

      c = await _container({
        'setup.musicAssistantOffered': true,
        'setup.preferencesOffered': true,
      });
      expect(nextSetupPage(c.read), '/home');
    },
  );

  test('signed in to Music Assistant, its step is not offered', () async {
    final c = await _container(
      {},
      ma: MaCredentials(baseUrl: Uri.parse('http://ma:8095'), token: 't'),
    );
    expect(nextSetupPage(c.read), '/setup/preferences');
  });

  testWidgets('Continue on the options goes home and does not come back', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'setup.musicAssistantOffered': true,
    });
    final prefs = await SharedPreferences.getInstance();
    final router = GoRouter(
      initialLocation: '/setup/preferences',
      routes: [
        GoRoute(
          path: '/setup/preferences',
          builder: (_, _) => const PreferencesSetupPage(),
        ),
        GoRoute(path: '/home', builder: (_, _) => const Text('Home')),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    expect(find.text('Make it yours'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsOneWidget);
    expect(prefs.getBool('setup.preferencesOffered'), isTrue);
  });
}
