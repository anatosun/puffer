import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:puffer/app/app.dart';
import 'package:puffer/app/playback_providers.dart';
import 'package:puffer/playback/playback_controller.dart';

class _FakeController extends Mock implements PlaybackController {}

Future<_FakeController> _pumpApp(WidgetTester tester) async {
  final controller = _FakeController();
  when(() => controller.current).thenReturn(
    NowPlaying(
      title: 'Song',
      duration: const Duration(minutes: 3),
      position: const Duration(seconds: 30),
      positionAt: DateTime.now(),
    ),
  );
  when(controller.play).thenAnswer((_) async {});
  when(controller.next).thenAnswer((_) async {});
  when(() => controller.seek(any())).thenAnswer((_) async {});
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(body: Text('home')),
      ),
      GoRoute(
        path: '/search',
        builder: (_, _) => const Scaffold(body: TextField()),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        playbackControllerProvider.overrideWithValue(controller),
        routerProvider.overrideWithValue(router),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        builder: (_, child) => KeyboardShortcuts(child: child!),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

void main() {
  setUpAll(() => registerFallbackValue(Duration.zero));

  testWidgets('keys control playback and open search', (tester) async {
    final controller = await _pumpApp(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    verify(controller.play).called(1);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    verify(() => controller.seek(const Duration(seconds: 40))).called(1);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    verify(controller.next).called(1);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('typing in a text field does not trigger shortcuts', (
    tester,
  ) async {
    final controller = await _pumpApp(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextField));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    verifyNever(controller.play);
    verifyNever(() => controller.seek(any()));
  });
}
