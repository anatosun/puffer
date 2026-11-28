import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:puffer/app/playback_providers.dart';
import 'package:puffer/app/providers.dart';
import 'package:puffer/features/login/music_assistant_setup_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('skipping Music Assistant goes on to the options, once', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final router = GoRouter(
      initialLocation: '/setup/music-assistant',
      routes: [
        GoRoute(
          path: '/setup/music-assistant',
          builder: (_, _) => const MusicAssistantSetupPage(),
        ),
        GoRoute(
          path: '/setup/preferences',
          builder: (_, _) => const Text('Options'),
        ),
        GoRoute(path: '/home', builder: (_, _) => const Text('Home')),
      ],
    );
    addTearDown(router.dispose);
    late WidgetRef ref;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: Consumer(
          builder: (context, r, _) {
            ref = r;
            return MaterialApp.router(routerConfig: router);
          },
        ),
      ),
    );

    expect(find.text('Play on your speakers'), findsOneWidget);
    // The form scrolls; in the 800 by 600 test window, Connect sits below the fold.
    expect(find.text('Connect', skipOffstage: false), findsOneWidget);
    expect(ref.read(maSetupOfferedProvider), isFalse);

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    expect(find.text('Options'), findsOneWidget);
    expect(ref.read(maSetupOfferedProvider), isTrue);
    expect(prefs.getBool('setup.musicAssistantOffered'), isTrue);
  });
}
