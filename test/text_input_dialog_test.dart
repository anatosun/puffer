import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:puffer/ui/widgets/text_input_dialog.dart';

void main() {
  /// Opens the dialog from a button and returns a getter for its result.
  Future<String? Function()> open(WidgetTester tester) async {
    String? result = 'not closed';
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await askText(
              context,
              title: 'New playlist',
              initial: ' Mix ',
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    return () => result;
  }

  testWidgets(
    'saving returns the trimmed text and the closing animation runs',
    (tester) async {
      final result = await open(tester);
      await tester.tap(find.text('Save'));
      // Every frame of the closing animation draws the field; none may use a disposed controller.
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(result(), 'Mix');
      expect(find.byType(AlertDialog), findsNothing);
    },
  );

  testWidgets('cancelling returns null', (tester) async {
    final result = await open(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(result(), isNull);
  });
}
