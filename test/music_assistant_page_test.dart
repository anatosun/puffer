import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:puffer/app/playback_providers.dart';
import 'package:puffer/app/providers.dart';
import 'package:puffer/app/sendspin_providers.dart';
import 'package:puffer/data/music_assistant/ma_client.dart';
import 'package:puffer/features/cast/music_assistant_page.dart';
import 'package:puffer/sendspin/session.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _open(WidgetTester tester, MaConnectionStatus status) async {
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        connectivityProvider.overrideWithValue(const AsyncData([])),
        initialMaCredentialsProvider.overrideWithValue(
          MaCredentials(baseUrl: Uri.parse('http://ma:8095'), token: 't'),
        ),
        maClientProvider.overrideWithValue(null),
        maStatusProvider.overrideWithValue(AsyncData(status)),
        maSubsonicProvidersProvider.overrideWithValue(const AsyncData([])),
        nowPlayingProvider.overrideWithValue(const AsyncData(null)),
        sendspinServiceProvider.overrideWithValue(const AsyncData(null)),
        sendspinStatusProvider.overrideWithValue(
          const AsyncData(SendspinStatus()),
        ),
      ],
      child: const MaterialApp(home: MusicAssistantPage()),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets(
    'a rejected token brings back the form, with the server filled in',
    (tester) async {
      await _open(tester, MaConnectionStatus.unauthorized);
      expect(find.textContaining('rejected the access token'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'http://ma:8095'), findsOneWidget);
      expect(find.text('Connect'), findsOneWidget);
      expect(find.text('Disconnect'), findsOneWidget);
    },
  );

  testWidgets('a working sign-in shows the connection, not the form', (
    tester,
  ) async {
    await _open(tester, MaConnectionStatus.connected);
    expect(find.text('Connect'), findsNothing);
    expect(find.textContaining('rejected the access token'), findsNothing);
  });
}
