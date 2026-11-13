import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:puffer/app/providers.dart';
import 'package:puffer/features/cast/output_sheet.dart';
import 'package:puffer/ui/messages.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  /// The top bar of a page with the speaker button, in offline mode when [offlineMode], on a device with [network] or none.
  Future<SharedPreferences> pump(
    WidgetTester tester, {
    required bool offlineMode,
    required bool network,
  }) async {
    SharedPreferences.setMockInitialValues({'offlineMode': offlineMode});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          connectivityProvider.overrideWithValue(
            AsyncData([
              network ? ConnectivityResult.wifi : ConnectivityResult.none,
            ]),
          ),
        ],
        child: MaterialApp(
          scaffoldMessengerKey: messengerKey,
          home: Scaffold(appBar: AppBar(actions: const [OutputButton()])),
        ),
      ),
    );
    return prefs;
  }

  testWidgets('in offline mode, the offline icon offers to go online', (
    tester,
  ) async {
    final prefs = await pump(tester, offlineMode: true, network: true);
    await tester.tap(find.byTooltip('Offline'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stay offline'));
    await tester.pumpAndSettle();
    expect(prefs.getBool('offlineMode'), isTrue);

    await tester.tap(find.byTooltip('Offline'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Go online'));
    await tester.pumpAndSettle();
    expect(prefs.getBool('offlineMode'), isFalse);
    expect(find.byTooltip('Offline'), findsNothing);
  });

  testWidgets('without a network, the offline icon says why', (tester) async {
    await pump(tester, offlineMode: false, network: false);
    await tester.tap(find.byTooltip('Offline'));
    await tester.pump();
    expect(find.text('This device has no network connection'), findsOneWidget);
    expect(find.text('Go online'), findsNothing);
  });
}
