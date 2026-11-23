import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:puffer/ui/interface_scale.dart';
import 'package:puffer/ui/layout.dart';
import 'package:puffer/ui/on_screen_keyboard.dart';

TextEditingValue at(String text, int offset) => TextEditingValue(
  text: text,
  selection: TextSelection.collapsed(offset: offset),
);

void main() {
  group('editing', () {
    test('typing inserts at the cursor and replaces a selection', () {
      expect(insertText(at('ac', 1), 'b'), at('abc', 2));
      const selected = TextEditingValue(
        text: 'hello',
        selection: TextSelection(baseOffset: 1, extentOffset: 4),
      );
      expect(insertText(selected, 'i'), at('hio', 2));
      expect(insertText(const TextEditingValue(text: 'ab'), 'c'), at('abc', 3));
    });

    test(
      'delete removes the character before the cursor, or the selection',
      () {
        expect(deleteBackward(at('abc', 2)), at('ac', 1));
        expect(deleteBackward(at('abc', 0)), at('abc', 0));
        expect(deleteBackward(at('a👍🏽', 5)), at('a', 1));
        const selected = TextEditingValue(
          text: 'hello',
          selection: TextSelection(baseOffset: 1, extentOffset: 4),
        );
        expect(deleteBackward(selected), at('ho', 1));
      },
    );
  });

  test('a short window lying on its side is short landscape', () {
    expect(isShortLandscapeSize(const Size(800, 480)), isTrue);
    expect(isShortLandscapeSize(const Size(480, 320)), isTrue);
    expect(isShortLandscapeSize(const Size(480, 800)), isFalse);
    expect(isShortLandscapeSize(const Size(1024, 600)), isFalse);
    expect(isShortLandscapeSize(const Size(1280, 400)), isFalse);
  });

  testWidgets('the keyboard opens on a text field, types and submits', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = TextEditingController();
    String? submitted;
    await tester.pumpWidget(
      MaterialApp(
        builder: (_, child) =>
            OnScreenKeyboardHost(enabled: true, child: child!),
        home: Scaffold(
          body: TextField(
            controller: controller,
            textInputAction: TextInputAction.search,
            onSubmitted: (v) => submitted = v,
          ),
        ),
      ),
    );
    expect(find.byType(OnScreenKeyboard), findsNothing);
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(find.byType(OnScreenKeyboard), findsOneWidget);
    // The page learns the height of the keyboard as an inset.
    final scaffold = tester.element(find.byType(Scaffold));
    expect(
      MediaQuery.viewInsetsOf(scaffold).bottom,
      OnScreenKeyboard.heightFor(const Size(800, 480)),
    );

    await tester.tap(find.byIcon(Icons.arrow_upward));
    await tester.pump();
    await tester.tap(find.text('P'));
    await tester.pump();
    await tester.tap(find.text('u'));
    await tester.tap(find.text('f'));
    await tester.tap(find.text('x'));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.backspace_outlined));
    await tester.pump();
    expect(controller.text, 'Puf');
    await tester.tap(find.text('123'));
    await tester.pump();
    await tester.tap(find.text('1'));
    await tester.pump();
    expect(controller.text, 'Puf1');

    await tester.tap(find.byIcon(Icons.search));
    await tester.pump();
    expect(submitted, 'Puf1');
    // A search gives up the focus, which closes the keyboard.
    expect(find.byType(OnScreenKeyboard), findsNothing);

    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(find.byType(OnScreenKeyboard), findsOneWidget);
    await tester.tap(find.byIcon(Icons.keyboard_hide_outlined));
    await tester.pump();
    expect(find.byType(OnScreenKeyboard), findsNothing);
  });

  testWidgets('without the setting, text fields use the platform keyboard', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (_, child) =>
            OnScreenKeyboardHost(enabled: false, child: child!),
        home: const Scaffold(body: TextField()),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(find.byType(OnScreenKeyboard), findsNothing);
    expect(tester.testTextInput.isVisible, isTrue);
  });

  testWidgets('the interface scale shrinks the logical window', (tester) async {
    tester.view.physicalSize = const Size(800, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late Size size;
    late double ratio;
    var taps = 0;
    await tester.pumpWidget(
      InterfaceScale(
        scale: 1.25,
        child: Builder(
          builder: (context) {
            size = MediaQuery.sizeOf(context);
            ratio = MediaQuery.devicePixelRatioOf(context);
            return Directionality(
              textDirection: TextDirection.ltr,
              child: Align(
                alignment: Alignment.bottomRight,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => taps++,
                  child: const SizedBox(width: 40, height: 40),
                ),
              ),
            );
          },
        ),
      ),
    );
    expect(size, const Size(640, 384));
    expect(ratio, 1.25);
    // The bottom-right box, 40 logical pixels wide, covers the last 50 physical pixels.
    await tester.tapAt(const Offset(780, 460));
    expect(taps, 1);
    await tester.tapAt(const Offset(740, 420));
    expect(taps, 1);
  });
}
