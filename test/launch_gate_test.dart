import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:puffer/app/experience.dart';
import 'package:puffer/app/providers.dart';
import 'package:puffer/ui/widgets/launch_animation.dart';
import 'package:puffer/ui/widgets/launch_gate.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Widget app() => const MaterialApp(
    home: LaunchGate(child: Scaffold(body: Text('Home'))),
  );

  testWidgets(
    'the launch animation plays over the first screen, then gives way',
    (tester) async {
      await tester.pumpWidget(app());
      expect(find.byType(PufferLaunchAnimation), findsOneWidget);
      // The animation starts after the first frame, runs 3.6 s, then fades out over 250 ms.
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(find.byType(PufferLaunchAnimation), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1700));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(find.byType(PufferLaunchAnimation), findsNothing);
      expect(find.text('Home'), findsOneWidget);
    },
  );

  testWidgets('a tap skips the launch animation', (tester) async {
    await tester.pumpWidget(app());
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byType(PufferLaunchAnimation));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(find.byType(PufferLaunchAnimation), findsNothing);
  });

  testWidgets(
    'with reduced motion the animation shows its last frame and ends',
    (tester) async {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: app(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(find.byType(PufferLaunchAnimation), findsNothing);
    },
  );

  testWidgets('the start-up animation setting turns the animation off', (
    tester,
  ) async {
    Future<void> start(Map<String, Object> stored) async {
      SharedPreferences.setMockInitialValues(stored);
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
          child: Consumer(
            builder: (context, ref, _) => MaterialApp(
              home: LaunchGate(
                enabled: ref.read(launchAnimationProvider),
                child: const Scaffold(body: Text('Home')),
              ),
            ),
          ),
        ),
      );
    }

    await start({});
    expect(find.byType(PufferLaunchAnimation), findsOneWidget);

    await start({'experience.launchAnimation': false});
    expect(find.byType(PufferLaunchAnimation), findsNothing);
    expect(find.text('Home'), findsOneWidget);
  });
}
